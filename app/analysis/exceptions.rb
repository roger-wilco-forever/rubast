# frozen_string_literal: true

module Rubast
  module Analysis
    module Exceptions
      PARENTS = { Exception: nil, StandardError: :Exception, RuntimeError: :StandardError,
                  ArgumentError: :StandardError, TypeError: :StandardError, IndexError: :StandardError,
                  ZeroDivisionError: :StandardError, FrozenError: :RuntimeError, RangeError: :StandardError,
                  IOError: :StandardError, NameError: :StandardError, NoMethodError: :NameError,
                  LocalJumpError: :StandardError, EOFError: :IOError, SystemCallError: :StandardError,
                  EncodingError: :StandardError, "Encoding::InvalidByteSequenceError": :EncodingError,
                  "Errno::ENOENT": :SystemCallError, "Errno::EACCES": :SystemCallError,
                  "Errno::EISDIR": :SystemCallError, "Errno::ENOTDIR": :SystemCallError,
                  "Errno::EEXIST": :SystemCallError, "Errno::ENOSPC": :SystemCallError,
                  "Errno::EROFS": :SystemCallError, "Errno::ELOOP": :SystemCallError,
                  "Errno::ENAMETOOLONG": :SystemCallError, "Errno::EIO": :SystemCallError,
                  "Errno::EBADF": :SystemCallError, "Errno::EPIPE": :SystemCallError }.freeze

      module Raising
        private

        def exception_class?(name)
          PARENTS.key?(name)
        end

        def exception_matches?(name, classes)
          return true if name == :unknown

          while name
            return true if classes.include?(name)

            name = PARENTS[name]
          end
          false
        end

        def exception_context(locals)
          { locals: locals, method: @method_context, block: @block_next_context,
            capture_depth: @captured_scopes.length, exits: [] }
        end

        def with_exception_context(context)
          saved = @exception_context
          @exception_context = context
          @block_exit_contexts << context
          yield
        ensure
          @block_exit_contexts.pop
          @exception_context = saved
        end

        def record_exception(name, locals, origin)
          check_exiting_traversals(origin)
          @exception_context.fetch(:exits) << [IR::ExceptionType.new(class_name: name),
                                               control_exit_state(@exception_context, locals)]
        end

        def validate_raise(node, locals)
          unsupported(node) unless node.arguments.length <= 2 && !node.receiver && !node.safe_navigation
          arguments, name = raise_arguments(node, locals)
          record_exception(name, locals, node) unless arguments.any? { |value| type_of(value, locals) == :never }
          IR::Raise.new(arguments: arguments.freeze, result_type: :never, span: node.span)
        end

        def raise_arguments(node, locals)
          class_node = node.arguments.first
          if class_node.is_a?(IR::ConstantRead)
            unsupported(class_node) unless exception_class?(class_node.name)
            message = node.arguments[1] || IR::StringLiteral.new(value: class_node.name.to_s, frozen: false,
                                                                 span: node.span)
            return [[validate_exception_value(class_node.name, message, locals, node)], class_node.name]
          end
          arguments, types = validate_arguments(node.arguments, (0...node.arguments.length).to_a, locals)
          unsupported(node) if arguments.length > 1
          [arguments, raised_class(types.fetch(0, nil), node)]
        end

        def raised_class(type, origin)
          return @rescued_type&.class_name || :RuntimeError unless type
          return type.class_name if type.is_a?(IR::ExceptionType)
          return :unknown if %i[unknown never].include?(type)
          return :RuntimeError if string_type?(type)

          unsupported(origin)
        end

        def validate_exception_value(name, message, locals, origin)
          unsupported(origin) if name == :SystemCallError
          value = validate_expression(message, locals)
          type = type_of(value, locals)
          unsupported(origin) unless type == :unknown || type == :never || string_type?(type)
          result = type == :never ? :never : IR::ExceptionType.new(class_name: name)
          IR::ExceptionValue.new(class_name: name, message: value, result_type: result, span: origin.span)
        end

        def validate_exception_new(node, locals)
          unsupported(node) unless node.name == :new && node.arguments.length <= 1 && !node.safe_navigation
          message = node.arguments.first || IR::StringLiteral.new(value: node.receiver.name.to_s, frozen: false,
                                                                  span: node.span)
          validate_exception_value(node.receiver.name, message, locals, node)
        end

        def validate_exception_call(node, receiver, type, locals)
          return validate_operation(node, receiver, type, locals) if %i[== != !].include?(node.name)

          unsupported(node) unless %i[message to_s].include?(node.name) && node.arguments.empty?
          IR::Builtin.new(family: :exception, name: node.name, receiver: receiver, arguments: [].freeze,
                          result_type: IR::UnionType.new(types: %i[string frozen_string].freeze), span: node.span)
        end
      end

      module Bodies
        private

        def protected_once(node, locals)
          context = exception_context(locals)
          @ensure_contexts << context if node.ensure_body
          protected_pass(node, locals, context, exception_context(locals))
        end

        def protected_pass(node, locals, context, retries)
          context.fetch(:exits).clear
          counts = flow_exit_counts
          body = with_exception_context(context) { validate_expression(node.body, locals) }
          normal = [[body.result_type, snapshot(locals)]] unless body.result_type == :never
          handlers, handled = protected_handlers(node, locals, context, retries)
          normal, otherwise = protected_else(node, normal || [], locals)
          paths = normal + handled
          ensure_body = if node.ensure_body
                          protected_ensure(node, paths, counts, locals, context)
                        else
                          merge_states(paths.map(&:last), locals, node)
                          nil
                        end
          IR::Protected.new(body: body, handlers: handlers, otherwise: otherwise,
                            ensure_body: ensure_body,
                            result_type: join_types(paths.map(&:first), node), span: node.span)
        end

        def protected_handlers(node, locals, context, retries)
          remaining = context.fetch(:exits).dup
          paths = []
          handlers = node.handlers.map do |handler|
            classes = rescue_classes(handler)
            matching, remaining = remaining.partition { |type, _| exception_matches?(type.class_name, classes) }
            remaining += matching.select { |type, _| type.class_name == :unknown } unless classes.include?(:Exception)
            body = rescue_body(handler, classes, matching, locals, retries)
            paths << [body.result_type, snapshot(locals)] unless matching.empty? || body.result_type == :never
            handler.with(classes: classes.freeze, body: body)
          end
          propagate_exceptions(remaining, locals, node)
          [handlers.freeze, paths]
        end

        def propagate_exceptions(remaining, locals, node)
          remaining.each do |type, state|
            restore(state, locals)
            record_exception(type.class_name, locals, node)
          end
        end

        def rescue_classes(handler)
          return [:StandardError] if handler.classes.empty?

          handler.classes.map do |value|
            name = rescue_class_name(value)
            unsupported(value) unless exception_class?(name)
            name
          end
        end

        def rescue_class_name(value)
          unsupported(value) unless value.is_a?(IR::ConstantRead) || value.is_a?(IR::ConstantPath)
          parts, absolute = constant_parts(value)
          key = absolute ? @constants[parts.first] : lexical_constant(parts.first)
          unsupported(value) if key
          parts.join("::").to_sym
        end

        def rescued_type(classes, matching)
          names = matching.map { |type, _| type.class_name }.uniq
          names = classes if names.empty?
          IR::ExceptionType.new(class_name: names.one? ? names.first : :unknown)
        end

        def rescue_body(handler, classes, matching, locals, retries)
          before = snapshot(locals)
          counts = flow_exit_counts
          merge_states(matching.map(&:last), locals, handler)
          saved = [@rescued_type, @retry_context]
          @rescued_type = rescued_type(classes, matching)
          @retry_context = retries
          locals[handler.reference] = @rescued_type if handler.reference
          @block_exit_contexts << retries
          value = validate_expression(handler.body, locals)
          restore_flow_exits(counts) if matching.empty?
          restore(before, locals) if matching.empty?
          value
        ensure
          @block_exit_contexts.pop
          @rescued_type, @retry_context = saved
        end

        def protected_else(node, paths, locals)
          return [paths, nil] unless node.otherwise

          before = snapshot(locals)
          counts = flow_exit_counts
          merge_states(paths.map(&:last), locals, node)
          value = validate_expression(node.otherwise, locals)
          if paths.empty?
            restore_flow_exits(counts)
            restore(before, locals)
            return [[], value]
          end
          [value.result_type == :never ? [] : [[value.result_type, snapshot(locals)]], value]
        end
      end

      module Ensuring
        private

        def protected_ensure(node, paths, counts, locals, context)
          pending = counts.flat_map { |list, count| list.drop(count).map { |type, state| [list, type, state] } }
          restore_flow_exits(counts)
          states = paths.map(&:last) + pending.map { |_, _, state| state.fetch(:unwind).fetch(context) }
          value = validate_ensure_body(node, states, pending, locals)
          paths.clear if value.result_type == :never
          unless value.result_type == :never
            paths.map! { |type, _| [type, snapshot(locals)] }
            resume_pending(pending, locals)
          end
          value
        end

        def validate_ensure_body(node, states, pending, locals)
          before = snapshot(locals)
          counts = flow_exit_counts
          merge_states(states, locals, node)
          saved_type = @rescued_type
          errors = pending.map { |_, type, _| type }.grep(IR::ExceptionType).map(&:class_name).uniq
          @rescued_type = IR::ExceptionType.new(class_name: errors.one? ? errors.first : :unknown) unless errors.empty?
          value = validate_expression(node.ensure_body, locals)
          if states.empty?
            restore_flow_exits(counts)
            restore(before, locals)
          end
          value
        ensure
          @rescued_type = saved_type
        end

        def resume_pending(pending, locals)
          pending.each do |list, type, state|
            target = @block_exit_contexts.find { |item| item.fetch(:exits).equal?(list) }
            updated = target ? control_exit_state(target, locals) : exit_snapshot(locals)
            updated[:locals] = updated.fetch(:locals).slice(*state.fetch(:locals).keys)
            updated[:captures] = updated.fetch(:captures).take(state.fetch(:captures).length)
            list << [type, updated]
          end
        end

        def exit_snapshot(locals)
          state = snapshot(locals)
          state[:unwind] = {}.compare_by_identity
          @ensure_contexts.each do |context|
            values = if context[:method] == @method_context
                       locals.slice(*context.fetch(:locals).keys)
                     else
                       context.fetch(:locals).dup
                     end
            state[:unwind][context] = state.merge(locals: values,
                                                  captures: state.fetch(:captures).take(context.fetch(:capture_depth)))
          end
          state
        end
      end

      module Retries
        private

        def validate_retry(node, locals)
          unsupported(node) unless @retry_context &&
                                   @retry_context.fetch(:block).equal?(@block_next_context)
          @retry_context.fetch(:exits) << [:nil, control_exit_state(@retry_context, locals)]
          node
        end

        def validate_protected(node, locals)
          saved_narrowing = @retry_narrowing
          return protected_once(node, locals) unless contains_retry?(node)

          @retry_narrowing = true
          entry = snapshot(locals)
          context = exception_context(locals)
          context[:entry] = entry
          @ensure_contexts << context if node.ensure_body
          retries = exception_context(locals)
          counts = flow_exit_counts
          head = solve_retry(node, locals, counts, context, retries)
          restore_flow_exits(counts)
          retries.fetch(:exits).clear
          restore(head, locals)
          protected_pass(node, locals, context, retries)
        ensure
          @ensure_contexts.pop if node.ensure_body
          @retry_narrowing = saved_narrowing
        end

        def solve_retry(node, locals, counts, context, retries)
          entry = context.fetch(:entry)
          head = entry
          # ponytail: reject after 16 retry passes; add a richer invariant domain if real workloads need it.
          16.times do
            restore_flow_exits(counts)
            retries.fetch(:exits).clear
            restore(head, locals)
            protected_pass(node, locals, context, retries)
            merge_states([entry, *retries.fetch(:exits).map(&:last)], locals, node)
            current = snapshot(locals)
            return head if same_loop_state?(head, current)

            head = current
          end
          unsupported(node)
        end

        def contains_retry?(node)
          return true if node.is_a?(IR::Retry)
          return node.any? { |value| contains_retry?(value) } if node.is_a?(Array)
          return false unless node.respond_to?(:span)

          node.to_h.except(:span, :result_type).values.any? { |value| contains_retry?(value) }
        end

        def validate_retry_conditional(node, locals)
          predicate = validate_scalar(node.predicate, locals)
          before = snapshot(locals)
          consequent, first = retry_branch(node.consequent, predicate, true, locals)
          restore(before, locals)
          alternative, second = retry_branch(node.alternative, predicate, false, locals)
          restore(before, locals)
          merge_states([first, second].compact, locals, node)
          types = []
          types << consequent.result_type if first
          types << alternative.result_type if second
          type = type_of(predicate, locals) == :never ? :never : join_types(types, node)
          node.with(predicate: predicate, consequent: consequent, alternative: alternative, result_type: type)
        end

        def retry_branch(node, predicate, truth, locals)
          before = snapshot(locals)
          counts = flow_exit_counts
          reachable = loop_truth(predicate) != !truth && constrain_loop_guard?(predicate, truth, locals)
          value = validate_expression(node, locals)
          state = snapshot(locals) if reachable && type_of(value, locals) != :never
          unless reachable
            restore_flow_exits(counts)
            restore(before, locals)
          end
          [value, state]
        end
      end

      include Raising
      include Bodies
      include Ensuring
      include Retries
    end
  end
end
