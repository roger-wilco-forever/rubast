# frozen_string_literal: true

module Rubast
  module Analysis
    class Validator
      MIN_INTEGER = -(2**63)
      MAX_INTEGER = (2**63) - 1

      def call(program)
        Session.new.call(program)
      end

      module Types
        private

        def members(type)
          case type
          when IR::UnionType then type.types
          when :string_or_nil then %i[string nil]
          else [type]
          end
        end

        def join_types(types, origin)
          values = types.flat_map { |type| members(type) }.reject { |type| type == :never }
          return :never if values.empty?
          return :unknown if values.include?(:unknown)

          check_hash_shapes(values, origin)
          objects = values.grep(IR::ObjectType)
          return join_scalars(values) if objects.empty?

          unsupported(origin) unless values.all? { |type| type.equal?(objects.first) }
          objects.first
        end

        def join_scalars(values)
          integers = values.grep(IR::IntegerType)
          values -= integers
          unless integers.empty?
            values << IR::IntegerType.new(minimum: integers.map(&:minimum).min, maximum: integers.map(&:maximum).max)
          end
          values = values.uniq
          values.one? ? values.first : IR::UnionType.new(types: values.freeze)
        end

        def literal_type(node)
          case node
          when IR::NilLiteral then :nil
          when IR::IntegerLiteral then IR::IntegerType.new(minimum: node.value, maximum: node.value)
          when IR::BooleanLiteral then :boolean
          when IR::StringLiteral then node.frozen ? :frozen_string : :string
          when IR::SymbolLiteral then IR::SymbolType.new(name: node.value)
          end
        end

        def effect_type(node, locals)
          case node
          when IR::Return then :never
          when IR::SafeChomp then safe_chomp_type(node, locals)
          when IR::InterpolatedString then continuing_type(node.parts, locals, :string)
          end
        end

        def continuing_type(expressions, locals, result)
          Array(expressions).any? { |expression| type_of(expression, locals) == :never } ? :never : result
        end

        def integer_type(minimum, maximum, origin)
          unless (MIN_INTEGER..MAX_INTEGER).cover?(minimum) && (MIN_INTEGER..MAX_INTEGER).cover?(maximum)
            raise CompilationError.new(code: "E_INTEGER_RANGE",
                                       message: "integer result exceeds the current 64-bit range", span: origin.span)
          end
          IR::IntegerType.new(minimum: minimum, maximum: maximum)
        end

        def integer_operands?(types)
          types.all? { |type| type.is_a?(IR::IntegerType) || type == :unknown || type == :never }
        end
      end

      module Operations
        ARITHMETIC = %i[+ - * / % +@ -@].freeze
        COMPARISONS = %i[< <= > >=].freeze

        private

        def validate_scalar(node, locals)
          value = validate_expression(node, locals)
          unsupported(node) if type_of(value, locals).is_a?(IR::ObjectType)
          value
        end

        def validate_dispatch(node, locals)
          case node
          when IR::Call then validate_call(node, locals)
          when IR::BlockCall then validate_block_call(node, locals)
          when IR::BlockPass then validate_block_pass(node, locals)
          when IR::Yield then validate_yield(node, locals)
          else validate_super(node, locals)
          end
        end

        def validate_operation(node, receiver, receiver_type, locals)
          arity = %i[! +@ -@].include?(node.name) ? 0 : 1
          unsupported(node) unless node.arguments.length == arity
          arguments, types = validate_arguments(node.arguments, (0...arity).to_a, locals)
          operands = [receiver, *arguments]
          operand_types = [receiver_type, *types.values]
          result_type = operation_type(node, operand_types)
          record_division_error(node, operand_types, locals)
          IR::Operation.new(name: node.name, operands: operands.freeze, result_type: result_type, span: node.span)
        end

        def record_division_error(node, types, locals)
          return unless %i[/ %].include?(node.name) && types.last.is_a?(IR::IntegerType)

          divisor = types.last
          return unless (divisor.minimum..divisor.maximum).cover?(0) && !types.include?(:never)

          record_exception(:ZeroDivisionError, locals, node)
        end

        def operation_type(node, types)
          return arithmetic_operation_type(node, types) if ARITHMETIC.include?(node.name)

          unsupported(node) unless %i[== != !].include?(node.name) || COMPARISONS.include?(node.name)
          unsupported(node) if COMPARISONS.include?(node.name) && !integer_operands?(types)
          reject_delegated_equality(node, types)
          types.include?(:never) ? :never : :boolean
        end

        def reject_delegated_equality(node, types)
          return unless %i[== !=].include?(node.name) && types.last.is_a?(IR::ObjectType)

          # Integer/String equality can call the right object's operator; add delegation with its own contract.
          delegates = members(types.first).any? { |type| type.is_a?(IR::IntegerType) || string_type?(type) }
          unsupported(node) if delegates
        end

        def arithmetic_operation_type(node, types)
          unsupported(node) unless integer_operands?(types)
          return :never if types.include?(:never)
          return :unknown if types.include?(:unknown)

          arithmetic_type(node, types)
        end

        def arithmetic_type(node, types)
          left = [types.first.minimum, types.first.maximum]
          if types.one?
            bounds = node.name == :-@ ? [-left.last, -left.first] : left
          else
            right = [types.last.minimum, types.last.maximum]
            if %i[/ %].include?(node.name) && (right.first..right.last).cover?(0)
              return zero_divisor_type(node, left, right)
            end

            bounds = arithmetic_bounds(node.name, left, right)
          end
          integer_type(bounds.min, bounds.max, node)
        end

        def zero_divisor_type(node, left, right)
          return :never if right == [0, 0]

          ranges = [[right.first, -1], [1, right.last]].select { |first, last| first <= last }
          values = ranges.flat_map { |range| arithmetic_bounds(node.name, left, range) }
          integer_type(values.min, values.max, node)
        end

        def arithmetic_bounds(name, left, right)
          case name
          when :+ then [left.first + right.first, left.last + right.last]
          when :- then [left.first - right.last, left.last - right.first]
          when :* then left.product(right).map { |a, b| a * b }
          when :/ then left.product(right).map { |a, b| a.div(b) }
          when :% then modulo_bounds(right)
          end
        end

        def modulo_bounds(right)
          right.first.positive? ? [0, right.last - 1] : [right.first + 1, 0]
        end
      end

      module State
        private

        def snapshot(locals)
          # ponytail: snapshot the arena; track reachable objects if large graphs make joins expensive.
          fields = @objects.to_h { |object| [object.object_id, [object, object.fields.dup]] }
          { locals: locals.dup, fields: fields, captures: capture_snapshot }
        end

        def restore(state, locals)
          state.fetch(:captures).each { |scope, values| scope.replace(values) }
          locals.replace(state.fetch(:locals))
          state.fetch(:fields).each_value { |object, fields| object.fields.replace(fields) }
        end

        def merge_states(states, locals, origin)
          return if states.empty?

          merge_captures(states, origin)
          merge_locals(states, locals, origin) if locals
          ids = states.flat_map { |state| state.fetch(:fields).keys }.uniq
          ids.each do |id|
            entries = states.filter_map { |state| state.fetch(:fields)[id] }
            merge_fields(entries.first.first, entries.map(&:last), origin)
          end
        end

        def merge_locals(states, locals, origin)
          names = states.flat_map { |state| state.fetch(:locals).keys }.uniq
          locals.replace(names.to_h do |name|
            [name, join_types(states.map { |state| state.fetch(:locals).fetch(name, :nil) }, origin)]
          end)
        end

        def merge_fields(object, maps, origin)
          fields = maps.flat_map(&:keys).uniq.to_h do |name|
            entries = array_type?(object) && name.is_a?(Integer) ? maps.select { |map| map.key?(name) } : maps
            [name, join_types(entries.map { |map| map[name] }, origin)]
          end
          object.fields.replace(Hash.new(maps.first.default).merge(fields))
        end
      end

      module ControlFlow
        private

        def validate_flow(node, locals)
          case node
          when IR::Sequence then validate_sequence(node, locals)
          when IR::Conditional then validate_conditional(node, locals)
          when IR::Loop then validate_loop(node, locals)
          when IR::LoopExit then validate_loop_exit(node, locals)
          when IR::Return then validate_return(node, locals)
          when IR::Protected then validate_protected(node, locals)
          else validate_exception_exit(node, locals)
          end
        end

        def validate_exception_exit(node, locals)
          node.is_a?(IR::Retry) ? validate_retry(node, locals) : validate_call_error(node, locals)
        end

        def validate_return(node, locals)
          unsupported(node) unless @return_context
          value = validate_expression(node.value, locals)
          type = type_of(value, locals)
          check_exiting_traversals(node)
          @return_context.fetch(:exits) << [type, control_exit_state(@return_context, locals)] unless type == :never
          node.with(value: value)
        end

        def validate_sequence(node, locals)
          result_type = :nil
          dead_state = nil
          exit_counts = nil
          expressions = node.expressions.map do |expression|
            value = validate_expression(expression, locals)
            if dead_state
              exit_counts.each { |list, count| list.slice!(count..) }
            else
              result_type = type_of(value, locals)
              if result_type == :never
                dead_state = snapshot(locals)
                exit_counts = loop_exit_lists.map { |list| [list, list.length] }
              end
            end
            value
          end
          restore(dead_state, locals) if dead_state
          node.with(expressions: expressions.freeze, result_type: result_type)
        end

        def validate_conditional(node, locals)
          return validate_retry_conditional(node, locals) if @retry_narrowing

          # ponytail: narrow only proven nil? outcomes; add wider predicate refinement with execution evidence.
          predicate = validate_scalar(node.predicate, locals)
          return validate_known_conditional(node, predicate, locals) unless known_predicate(predicate).nil?

          join_conditional(node, predicate, locals)
        end

        def join_conditional(node, predicate, locals)
          before = snapshot(locals)
          consequent = validate_expression(node.consequent, locals)
          first = snapshot(locals)
          restore(before, locals)
          alternative = validate_expression(node.alternative, locals)
          second = snapshot(locals)
          states = []
          states << first unless consequent.result_type == :never
          states << second unless alternative.result_type == :never
          restore(before, locals)
          merge_states(states, locals, node)
          type = join_types([consequent.result_type, alternative.result_type], node)
          type = :never if type_of(predicate, before.fetch(:locals)) == :never
          node.with(predicate: predicate, consequent: consequent, alternative: alternative, result_type: type)
        end
      end

      module Inheritance
        private

        def implicit_method?(node)
          node.receiver.nil? && @receiver_type && lookup_method(@receiver_type.class_name, node.name)
        end
      end

      module MethodResults
        private

        def method_environment
          [@receiver_type, @active_methods, @method_context, @loop_context,
           @yield_context, @block_exit_context, @block_next_context, @retry_context, @constructor_type,
           @constant_scopes, @definition_owner]
        end

        def restore_method_environment(values)
          @receiver_type, @active_methods, @method_context, @loop_context,
            @yield_context, @block_exit_context, @block_next_context, @retry_context, @constructor_type,
            @constant_scopes, @definition_owner = values
        end

        def receiving_block_exits
          return [] unless @yield_context && @yield_context[:receiving] != false

          @yield_context.fetch(:exits)
        end

        def method_completion_type(type)
          @constructor_type || type
        end

        def method_result(body, locals, origin)
          exits = @return_context.fetch(:exits)
          types = exits.map { |type, _| method_completion_type(type) }
          states = exits.map(&:last)
          block_exits = receiving_block_exits
          types.concat(block_exits.map(&:first))
          states.concat(block_exits.map(&:last))
          unless body.result_type == :never
            types << method_completion_type(body.result_type)
            states << snapshot(locals)
          end
          merge_states(states, nil, origin)
          result = join_types(types, origin)
          unsupported(origin) if block_type?(result)
          body.with(result_type: result)
        end
      end

      module InstanceState
        private

        def validate_variable(node, locals)
          case node
          when IR::Setter, IR::ConstantRead, IR::ConstantPath, IR::SourceLoad, IR::GlobalRead
            validate_namespace_reference(node, locals)
          when IR::SelfRead
            unsupported(node) unless @receiver_type
            node.with(result_type: @receiver_type)
          when IR::InstanceRead
            unsupported(node) unless @receiver_type
            node.with(result_type: @receiver_type.fields[node.name])
          when IR::InstanceWrite
            validate_instance_write(node, locals)
          else validate_local(node, locals)
          end
        end

        def validate_instance_write(node, locals)
          unsupported(node) unless @receiver_type
          value = validate_expression(node.value, locals)
          unsupported(node) if block_type?(type_of(value, locals))
          @receiver_type.fields[node.name] = type_of(value, locals)
          node.with(value: value)
        end

        def checked_method_body(method, parameters, receiver, origin = method, **context)
          owner = context.fetch(:owner, receiver.class_name)
          saved_context = method_environment
          key = [receiver.class_name, owner, method.name]
          unsupported(origin) if @active_methods.include?(key)
          @active_methods += [key]
          @yield_context = context[:block]
          @constructor_type = context[:construction]
          @receiver_type = receiver
          @method_context = [owner, method]
          @constant_scopes = @method_scopes.fetch(method, [])
          @definition_owner = nil
          @loop_context = nil
          @block_exit_context = nil
          @block_next_context = nil
          @retry_context = nil
          locals = method.locals.to_h { |name| [name, :nil] }.merge(parameters)
          with_return_context(locals) do
            body = checked_entry_body(method, context, locals)
            method_result(body, locals, origin)
          end
        ensure
          restore_method_environment(saved_context)
        end

        def validate_method_call(node, locals)
          receiver = validate_expression(node.receiver || IR::SelfRead.new(result_type: nil, span: node.span), locals)
          type = type_of(receiver, locals)
          return defer_call(node, receiver, locals) if type == :unknown
          return dead_receiver_call(node, receiver, locals) if type == :never
          return validate_special_receiver(node, receiver, type, locals) unless user_block_receiver?(type)

          validate_user_receiver(node, receiver, type, locals)
        end

        def validate_user_receiver(node, receiver, type, locals)
          unsupported(node) if node.name == :initialize
          target = lookup_method(type.class_name, node.name)
          return defer_call(node, receiver, locals) if !target && unbound_module_owner?(type.class_name)

          node, target = resolve_user_dispatch(node, type)
          return validate_new(node, locals, receiver) if constructor_call?(node, type, target)
          return validate_user_builtin(node, receiver, type, locals) unless target

          validate_object_call(node, receiver, type, target, locals)
        end

        def validate_special_receiver(node, receiver, type, locals)
          return validate_nil_predicate(node, receiver, type) if node.name == :nil?

          if io_type?(type)
            return validate_operation(node, receiver, type, locals) if %i[== != !].include?(node.name)

            return validate_io_call(node, receiver, type, locals)
          end
          return validate_block_receiver(node, receiver, type, locals) if block_receiver_call?(node, type)
          return validate_exception_call(node, receiver, type, locals) if type.is_a?(IR::ExceptionType)
          return validate_collection_call(node, receiver, type, locals) if collection_call?(node, type)

          validate_operation(node, receiver, type, locals)
        end

        def validate_object_call(node, receiver, type, target, locals)
          check_method_visibility(node, type, target)
          resolved_method_call(node, receiver, type, target, locals)
        end

        def object_type(name, default)
          record_bounded_allocation
          type = IR::ObjectType.new(class_name: name, fields: Hash.new(default))
          @objects << type
          type
        end

        def defer_call(node, receiver, locals)
          # Unknown receivers exist only while checking unused method syntax; actual calls resolve lookup.
          arguments = call_payload(node, locals).fetch(:arguments).freeze
          node.with(receiver: receiver, arguments: arguments)
        end

        def validate_identity(node, receiver, type, locals)
          if node.name == :!= && (target = lookup_method(type.class_name, :==))
            equal = validate_object_call(node.with(name: :==), receiver, type, target, locals)
            result = type_of(equal, locals) == :never ? :never : :boolean
            return IR::Operation.new(name: :!, operands: [equal].freeze, result_type: result, span: node.span)
          end
          unsupported(node) unless %i[== != !].include?(node.name)
          validate_operation(node, receiver, type, locals)
        end
      end

      class Session < Validator
        include Types
        include Operations
        include State
        include ControlFlow
        include Namespaces
        include Inheritance
        include Modules
        include Visibility
        include StaticDispatch
        include NativeMethods
        include Reflection
        include RegistryOperations
        include InstanceState
        include MethodResults
        include LoopAnalysis
        include Collections
        include Hashes
        include Iterators
        include Blocks
        include BlockArguments
        include CallArguments
        include Arguments
        include Exceptions
        include TextIo

        def call(program)
          initialize_namespaces
          @source_symbols = program.symbols.dup
          @active_methods = []
          @objects = []
          @captured_scopes = []
          @block_exit_contexts = []
          @next_block_exit = 0
          @literal_blocks = {}
          @ensure_contexts = []
          locals = program.locals.to_h { |name| [name, :nil] }
          @exception_context = exception_context(locals)
          @block_exit_contexts << @exception_context
          statements = program.statements.filter_map { |node| validate_statement(node, locals) }
          IR::Program.new(statements: statements.freeze, locals: program.locals, warnings: program.warnings,
                          symbols: program.symbols)
        end

        private

        def validate_statement(node, locals)
          case node
          when IR::ClassDefinition then validate_class(node)
          when IR::ConstantWrite then validate_constant_write(node, locals)
          else validate_expression(node, locals)
          end
        end

        def validate_expression(node, locals)
          case node
          when IR::IntegerLiteral, IR::StringLiteral, IR::NilLiteral, IR::BooleanLiteral, IR::SymbolLiteral, IR::BlockValue,
               IR::IOReference
            validate_literal(node)
          when IR::Setter, IR::ConstantRead, IR::ConstantPath, IR::SourceLoad, IR::GlobalRead, IR::LocalRead, IR::LocalWrite,
               IR::InstanceRead, IR::InstanceWrite, IR::SelfRead
            validate_variable(node, locals)
          when IR::Sequence, IR::Conditional, IR::Return, IR::Loop, IR::LoopExit, IR::Protected, IR::Retry, IR::CallError
            validate_flow(node, locals)
          when IR::InterpolatedString
            parts = node.parts.map { |part| validate_output(part, locals) }
            IR::InterpolatedString.new(parts: parts.freeze, span: node.span)
          when IR::Call, IR::Super, IR::BlockCall, IR::BlockPass, IR::Yield then validate_dispatch(node, locals)
          when IR::ArrayLiteral, IR::HashLiteral, IR::ParameterArray, IR::ParameterHash, IR::IndexWrite
            validate_collection_expression(node, locals)
          else unsupported(node)
          end
        end

        def validate_call(node, locals)
          return validate_method_call(node, locals) if implicit_method?(node)

          builtin = validate_builtin_call(node, locals)
          return builtin if builtin
          return validate_safe_chomp(node, locals) if safe_chomp_call?(node)
          return validate_exception_new(node, locals) if builtin_exception_receiver?(node)
          return validate_method_call(node, locals) unless node.safe_navigation

          unsupported(node)
        end

        def validate_kernel_call(node, locals)
          return validate_p(node, locals) if node.name == :p

          return validate_io_kernel(node, locals) if %i[puts print warn gets].include?(node.name)

          validate_raise(node, locals)
        end

        def validate_new(node, locals, receiver = nil)
          receiver ||= validate_expression(node.receiver, locals)
          class_type = type_of(receiver, locals)
          check_method_visibility(node, class_type, nil)
          namespace = class_type.class_name.name
          unsupported(node) if loop_allocation? || @namespace_kinds[namespace] != :class
          type = object_type(namespace, :nil)
          owner, method = lookup_method(namespace, :initialize)
          invocation = validate_invocation(node, method, locals, type, owner: owner)
          IR::NewObject.new(class_name: owner || :BasicObject, receiver: receiver, **invocation,
                            result_type: continuing_type(invocation.fetch(:body), locals, type), span: node.span)
        end

        def validate_safe_chomp(node, locals)
          receiver = validate_expression(node.receiver, locals)
          return IR::SafeChomp.new(receiver: receiver, span: node.span) if string_like?(receiver, locals)

          unsupported(node)
        end
      end

      private

      def validate_source_load(node)
        @source_symbols |= node.program.symbols
        scope = node.program.locals.to_h { |name| [name, :nil] }
        statements = node.program.statements.map { |part| validate_statement(part, scope) }
        type = statements.any? { |part| type_of(part, scope) == :never } ? :never : :boolean
        node.with(program: node.program.with(statements: statements.freeze), result_type: type)
      end

      def validate_invocation(node, method, locals, receiver, owner:)
        method ||= default_initializer(node)
        arguments, parameters, bindings = prepare_arguments(node, method, locals, owner: owner || :BasicObject)
        return deferred_invocation(method, receiver, owner, [arguments, parameters], node) unless bindings

        body = validate_method_body(method, parameters, receiver, node,
                                    owner: owner || :BasicObject, bindings: bindings)
        body = body.with(result_type: :never) if parameters.value?(:never)
        { arguments: arguments, parameters: parameters.keys.freeze,
          locals: (method.locals + parameters.keys).uniq.freeze, body: body }
      end

      def validate_literal(node)
        case node
        when IR::IntegerLiteral then validate_integer(node)
        when IR::StringLiteral, IR::SymbolLiteral then validate_string(node)
        when IR::NilLiteral, IR::BooleanLiteral, IR::BlockValue then node
        end
      end

      def validate_local_write(node, locals)
        value = validate_expression(node.value, locals)
        locals[node.name] = type_of(value, locals)
        node.with(value: value)
      end

      def validate_local(node, locals)
        return validate_local_write(node, locals) if node.is_a?(IR::LocalWrite)

        locals.key?(node.name) ? node : unsupported(node)
      end

      def type_of(node, locals)
        case node
        when IR::NilLiteral, IR::IntegerLiteral, IR::BooleanLiteral, IR::StringLiteral, IR::SymbolLiteral
          literal_type(node)
        when IR::BlockValue then IR::BlockType.new(id: node.id)
        when IR::LoopExit, IR::BlockExit, IR::Retry then :never
        when IR::Return, IR::SafeChomp, IR::InterpolatedString then effect_type(node, locals)
        when IR::Call then continuing_type([node.receiver, *node.arguments], locals, :unknown)
        when IR::LocalRead, IR::LocalWrite, IR::InstanceWrite then local_type(node, locals)
        when IR::NewObject, IR::MethodCall, IR::Sequence, IR::InstanceRead, IR::SelfRead, IR::Operation, IR::Conditional,
             IR::Loop, IR::ArrayLiteral, IR::HashLiteral, IR::IndexWrite, IR::Builtin, IR::BlockCall, IR::Iterator,
             IR::Yield, IR::YieldInvoke, IR::BlockInvocation, IR::BlockBody, IR::Protected, IR::Raise,
             IR::ExceptionValue, IR::CallError, IR::ArgumentCopy, IR::ParameterArray, IR::ParameterHash,
             IR::ArgumentEvaluation, IR::BlockPass, IR::ConstantGet, IR::ConstantSet, IR::NamespaceBody,
             IR::ClassValue, IR::Setter, IR::Print, IR::NilCheck, IR::SourceLoad, IR::IOReference, IR::Reflection
          node.result_type
        end
      end

      def local_type(node, locals)
        node.is_a?(IR::LocalRead) ? locals.fetch(node.name) : type_of(node.value, locals)
      end

      def safe_chomp_call?(node)
        node.receiver && node.safe_navigation && node.name == :chomp && node.arguments.empty?
      end

      def string_like?(node, locals)
        members(type_of(node, locals)).all? { |type| %i[string frozen_string nil unknown never].include?(type) }
      end

      def validate_integer(node)
        return node if (MIN_INTEGER..MAX_INTEGER).cover?(node.value)

        raise CompilationError.new(
          code: "E_INTEGER_RANGE",
          message: "integer literal exceeds the current 64-bit range",
          span: node.span
        )
      end

      def validate_string(node)
        return node if node.value.encoding == Encoding::UTF_8 && node.value.valid_encoding?

        raise CompilationError.new(
          code: "E_ENCODING",
          message: "only UTF-8 string and symbol literals are supported",
          span: node.span
        )
      end

      def unsupported(node)
        raise CompilationError.new(
          code: "E_UNSUPPORTED",
          message: "unsupported Ruby expression: #{node.class.name.split('::').last}",
          span: node.span
        )
      end
    end
  end
end
