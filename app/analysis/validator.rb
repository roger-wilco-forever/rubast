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

          objects = values.grep(IR::ObjectType)
          return join_scalars(values) if objects.empty?

          unsupported(origin) unless values.all? { |type| type.equal?(objects.first) }
          objects.first
        end

        def join_scalars(values)
          return :scalar if values.include?(:scalar)

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
          when IR::StringLiteral then :string
          end
        end

        def effect_type(node, locals)
          case node
          when IR::Return then :never
          when IR::GetLine then :string_or_nil
          when IR::SafeChomp then continuing_type(node.receiver, locals, :string_or_nil)
          when IR::Puts then continuing_type(node.value, locals, :nil)
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
          types.all? { |type| type.is_a?(IR::IntegerType) || type == :scalar || type == :never }
        end
      end

      module Operations
        ARITHMETIC = %i[+ - * / % +@ -@].freeze
        COMPARISONS = %i[< <= > >=].freeze

        private

        def validate_operation(node, receiver, receiver_type, locals)
          arity = %i[! +@ -@].include?(node.name) ? 0 : 1
          unsupported(node) unless node.arguments.length == arity
          arguments, types = validate_arguments(node.arguments, (0...arity).to_a, locals)
          operands = [receiver, *arguments]
          operand_types = [receiver_type, *types.values]
          result_type = operation_type(node, operand_types)
          IR::Operation.new(name: node.name, operands: operands.freeze, result_type: result_type, span: node.span)
        end

        def operation_type(node, types)
          return arithmetic_operation_type(node, types) if ARITHMETIC.include?(node.name)

          unsupported(node) unless %i[== != !].include?(node.name) || COMPARISONS.include?(node.name)
          unsupported(node) if COMPARISONS.include?(node.name) && !integer_operands?(types)
          types.include?(:never) ? :never : :boolean
        end

        def arithmetic_operation_type(node, types)
          unsupported(node) unless integer_operands?(types)
          return :never if types.include?(:never)
          return :scalar if types.include?(:scalar)

          arithmetic_type(node, types)
        end

        def arithmetic_type(node, types)
          left = [types.first.minimum, types.first.maximum]
          if types.one?
            bounds = node.name == :-@ ? [-left.last, -left.first] : left
          else
            right = [types.last.minimum, types.last.maximum]
            unsupported(node) if %i[/ %].include?(node.name) && (right.first..right.last).cover?(0)
            bounds = arithmetic_bounds(node.name, left, right)
          end
          integer_type(bounds.min, bounds.max, node)
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
          objects = [@receiver_type, *locals.values].grep(IR::ObjectType).uniq(&:object_id)
          fields = objects.to_h { |object| [object.object_id, [object, object.fields.dup]] }
          { locals: locals.dup, fields: fields }
        end

        def restore(state, locals)
          locals.replace(state.fetch(:locals))
          state.fetch(:fields).each_value { |object, fields| object.fields.replace(fields) }
        end

        def merge_states(states, locals, origin)
          return if states.empty?

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
            [name, join_types(maps.map { |map| map[name] }, origin)]
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
          when IR::Return
            unsupported(node) unless @return_exits
            value = validate_scalar(node.value, locals)
            type = type_of(value, locals)
            @return_exits << [type, snapshot(locals)] unless type == :never
            node.with(value: value)
          end
        end

        def validate_sequence(node, locals)
          result_type = :nil
          dead_state = nil
          exit_count = nil
          expressions = node.expressions.map do |expression|
            value = validate_expression(expression, locals)
            if dead_state
              @return_exits&.slice!(exit_count..)
            else
              result_type = type_of(value, locals)
              if result_type == :never
                dead_state = snapshot(locals)
                exit_count = @return_exits&.length
              end
            end
            value
          end
          restore(dead_state, locals) if dead_state
          node.with(expressions: expressions.freeze, result_type: result_type)
        end

        def validate_conditional(node, locals)
          # ponytail: join both branches; add predicate narrowing when safe programs need it.
          predicate = validate_scalar(node.predicate, locals)
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

      module InstanceState
        private

        def implicit_method?(node)
          node.receiver.nil? && @receiver_type && @classes.fetch(@receiver_type.class_name).key?(node.name)
        end

        def validate_variable(node, locals)
          case node
          when IR::SelfRead
            unsupported(node) unless @receiver_type
            node.with(result_type: @receiver_type)
          when IR::InstanceRead
            unsupported(node) unless @receiver_type
            node.with(result_type: @receiver_type.fields[node.name])
          when IR::InstanceWrite
            unsupported(node) unless @receiver_type
            value = validate_scalar(node.value, locals)
            @receiver_type.fields[node.name] = type_of(value, locals)
            node.with(value: value)
          else validate_local(node, locals)
          end
        end

        def validate_method_body(method, parameters, receiver, origin = method)
          saved_receiver = @receiver_type
          saved_methods = @active_methods
          saved_exits = @return_exits
          key = [receiver.class_name, method.name]
          unsupported(origin) if saved_methods.include?(key)
          @active_methods = saved_methods + [key]
          @receiver_type = receiver
          @return_exits = []
          locals = method.locals.to_h { |name| [name, :nil] }.merge(parameters)
          body = validate_scalar(method.body, locals)
          types = @return_exits.map(&:first)
          states = @return_exits.map(&:last)
          unless body.result_type == :never
            types << body.result_type
            states << snapshot(locals)
          end
          merge_states(states, nil, origin)
          body.with(result_type: join_types(types, origin))
        ensure
          @receiver_type = saved_receiver
          @active_methods = saved_methods
          @return_exits = saved_exits
        end
      end

      class Session < Validator
        include Types
        include Operations
        include State
        include ControlFlow
        include InstanceState

        def call(program)
          @classes = {}
          @active_methods = []
          locals = program.locals.to_h { |name| [name, :nil] }
          statements = program.statements.filter_map { |node| validate_statement(node, locals) }
          IR::Program.new(statements: statements.freeze, locals: program.locals, warnings: program.warnings)
        end

        private

        def validate_statement(node, locals)
          case node
          when IR::ClassDefinition then validate_class(node)
          else validate_expression(node, locals)
          end
        end

        def validate_puts(node, locals)
          unless node.receiver.nil? && !node.safe_navigation && node.name == :puts && node.arguments.one?
            unsupported(node)
          end

          IR::Puts.new(value: validate_scalar(node.arguments.first, locals), span: node.span)
        end

        def validate_class(node)
          unsupported(node) if @classes.key?(node.name) || Object.const_defined?(node.name, false)
          methods = {}
          node.definitions.each do |method|
            unsupported(method) if methods.key?(method.name)
            methods[method.name] = method
          end
          @classes[node.name] = methods.freeze
          methods.each_value do |method|
            parameters = method.parameters.to_h { |name| [name, :scalar] }
            receiver = IR::ObjectType.new(class_name: node.name, fields: Hash.new(:scalar))
            validate_method_body(method, parameters, receiver)
          end
          nil
        end

        def validate_scalar(node, locals)
          value = validate_expression(node, locals)
          unsupported(node) if type_of(value, locals).is_a?(IR::ObjectType)
          value
        end

        def validate_expression(node, locals)
          case node
          when IR::IntegerLiteral, IR::StringLiteral, IR::NilLiteral, IR::BooleanLiteral then validate_literal(node)
          when IR::LocalRead, IR::LocalWrite, IR::InstanceRead, IR::InstanceWrite, IR::SelfRead
            validate_variable(node, locals)
          when IR::Sequence, IR::Conditional, IR::Return then validate_flow(node, locals)
          when IR::InterpolatedString
            parts = node.parts.map { |part| validate_scalar(part, locals) }
            IR::InterpolatedString.new(parts: parts.freeze, span: node.span)
          when IR::Call then validate_call(node, locals)
          else unsupported(node)
          end
        end

        def validate_call(node, locals)
          return validate_method_call(node, locals) if implicit_method?(node)
          return validate_puts(node, locals) if node.receiver.nil? && node.name == :puts
          return IR::GetLine.new(span: node.span) if gets_call?(node)
          return validate_safe_chomp(node, locals) if safe_chomp_call?(node)
          return validate_new(node, locals) if node.receiver.is_a?(IR::ConstantRead)
          return validate_method_call(node, locals) unless node.safe_navigation

          unsupported(node)
        end

        def validate_new(node, locals)
          name = node.receiver.name
          unsupported(node) unless @classes.key?(name) && node.name == :new && !node.safe_navigation
          type = IR::ObjectType.new(class_name: name, fields: Hash.new(:nil))
          invocation = validate_invocation(node, @classes.fetch(name)[:initialize], locals, type)
          IR::NewObject.new(class_name: name, **invocation,
                            result_type: invocation.fetch(:body).result_type == :never ? :never : type, span: node.span)
        end

        def validate_method_call(node, locals)
          receiver = validate_expression(node.receiver || IR::SelfRead.new(result_type: nil, span: node.span), locals)
          type = type_of(receiver, locals)
          return validate_operation(node, receiver, type, locals) unless type.is_a?(IR::ObjectType)

          unsupported(node) if node.name == :initialize
          method = @classes.fetch(type.class_name)[node.name]
          unsupported(node) unless method
          invocation = validate_invocation(node, method, locals, type)
          IR::MethodCall.new(class_name: type.class_name, name: node.name, receiver: receiver, **invocation,
                             result_type: invocation.fetch(:body).result_type, span: node.span)
        end

        def validate_safe_chomp(node, locals)
          receiver = validate_expression(node.receiver, locals)
          return IR::SafeChomp.new(receiver: receiver, span: node.span) if string_like?(receiver, locals)

          unsupported(node)
        end
      end

      private

      def validate_invocation(node, method, locals, receiver)
        names = method&.parameters || []
        unsupported(node) unless node.arguments.length == names.length
        arguments, parameters = validate_arguments(node.arguments, names, locals)
        body = if method
                 validate_method_body(method, parameters, receiver, node)
               else
                 IR::Sequence.new(expressions: [].freeze, result_type: :nil, span: node.span)
               end
        body = body.with(result_type: :never) if parameters.value?(:never)
        { arguments: arguments, parameters: names, locals: method&.locals || [], body: body }
      end

      def validate_literal(node)
        case node
        when IR::IntegerLiteral then validate_integer(node)
        when IR::StringLiteral then validate_string(node)
        when IR::NilLiteral, IR::BooleanLiteral then node
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
        when IR::NilLiteral, IR::IntegerLiteral, IR::BooleanLiteral, IR::StringLiteral then literal_type(node)
        when IR::Return, IR::GetLine, IR::SafeChomp, IR::Puts, IR::InterpolatedString then effect_type(node, locals)
        when IR::LocalRead, IR::LocalWrite, IR::InstanceWrite then local_type(node, locals)
        when IR::NewObject, IR::MethodCall, IR::Sequence, IR::InstanceRead, IR::SelfRead, IR::Operation, IR::Conditional
          node.result_type
        end
      end

      def local_type(node, locals)
        node.is_a?(IR::LocalRead) ? locals.fetch(node.name) : type_of(node.value, locals)
      end

      def gets_call?(node)
        node.receiver.nil? && !node.safe_navigation && node.name == :gets && node.arguments.empty?
      end

      def safe_chomp_call?(node)
        node.receiver && node.safe_navigation && node.name == :chomp && node.arguments.empty?
      end

      def string_like?(node, locals)
        members(type_of(node, locals)).all? { |type| %i[string nil scalar never].include?(type) }
      end

      def validate_arguments(nodes, names, locals)
        types = {}
        arguments = nodes.zip(names).map do |node, name|
          value = validate_scalar(node, locals)
          types[name] = type_of(value, locals)
          value
        end
        [arguments.freeze, types]
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
          message: "only UTF-8 string literals are supported",
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
