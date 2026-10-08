# frozen_string_literal: true

module Rubast
  module Analysis
    module Blocks
      module Exits
        private

        def new_block_context(block, locals)
          @next_block_exit += 1
          { id: @next_block_exit, block: block, locals: locals, method: @method_context,
            exits: [], capture_depth: @captured_scopes.length }
        end

        def with_block_exit_context(context)
          saved = @block_exit_context
          @block_exit_contexts << context
          @block_exit_context = context
          yield
        ensure
          @block_exit_contexts.pop
          @block_exit_context = saved
        end

        def with_block_next_context(context)
          saved = @block_next_context
          @block_exit_contexts << context
          @block_next_context = context
          yield
        ensure
          @block_exit_contexts.pop
          @block_next_context = saved
        end

        def with_return_context(locals)
          saved = @return_context
          @return_context = { locals: locals, method: @method_context,
                              exits: [], capture_depth: @captured_scopes.length }
          @block_exit_contexts << @return_context
          yield
        ensure
          @block_exit_contexts.pop
          @return_context = saved
        end

        def block_exit_lists
          @block_exit_contexts.map { |context| context.fetch(:exits) }
        end

        def flow_exit_counts
          loop_exit_lists.map { |list| [list, list.length] }
        end

        def restore_flow_exits(counts)
          counts.each { |list, count| list.slice!(count..) }
        end

        def validate_block_exit(node, locals)
          return validate_block_next(node, locals) if node.kind == :next

          unsupported(node) unless node.kind == :break && @block_exit_context
          value = validate_expression(node.value, locals)
          type = type_of(value, locals)
          check_exiting_traversals(node)
          unless type == :never
            @block_exit_context.fetch(:exits) << [type, control_exit_state(@block_exit_context, locals)]
          end
          IR::BlockExit.new(target: @block_exit_context.fetch(:id), value: value, span: node.span)
        end

        def validate_block_next(node, locals)
          unsupported(node) unless @block_next_context
          @block_next_context[:used] = true
          value = validate_expression(node.value, locals)
          type = type_of(value, locals)
          check_exiting_traversals(node)
          @block_next_context.fetch(:exits) << [type, exit_snapshot(locals)] unless type == :never
          IR::BlockExit.new(target: @block_next_context.fetch(:id), value: value, span: node.span)
        end

        def check_exiting_traversals(node)
          @block_exit_contexts.each do |context|
            traversal = context[:traversal]
            check_iterator_length(*traversal, node) if traversal
          end
        end

        def control_exit_state(context, locals)
          root = context.fetch(:locals)
          state = exit_snapshot(locals)
          state[:locals] = context[:method] == @method_context ? locals.slice(*root.keys) : root.dup
          state[:captures] = state.fetch(:captures).take(context.fetch(:capture_depth))
          state.fetch(:captures).each do |scope, values|
            values.replace(state.fetch(:locals)) if scope.equal?(root)
          end
          state
        end
      end

      module Captures
        private

        def capture_snapshot
          @captured_scopes.map { |scope| [scope, scope.dup] }
        end

        def merge_captures(states, origin)
          states.first.fetch(:captures).each_with_index do |(scope, _), index|
            maps = states.map { |state| { locals: state.fetch(:captures).fetch(index).last } }
            merge_locals(maps, scope, origin)
          end
        end
      end

      module Yielding
        private

        def validate_yield(node, locals)
          return deferred_yield(node, locals) if !@yield_context && @checking_unused

          validate_block_execution(node, @yield_context, locals)
        end

        def deferred_yield(node, locals)
          pack = call_payload(node, locals)
          node.with(arguments: pack[:arguments].freeze, result_type: :unknown)
        end

        def validate_block_execution(node, context, locals)
          pack = call_payload(node, locals)
          unsupported(node) if pack[:unknown]
          scope = locals.merge(pack[:types])
          arguments = pack[:positional].dup
          arguments << parameter_hash(pack[:keywords], node.span) unless pack[:keywords].empty?
          values, types = validate_arguments(arguments, (0...arguments.length).to_a, scope)
          body = if context
                   resolved_yield(node, context, values, types, scope)
                 else
                   missing_block_error(node, locals, :LocalJumpError, "no block given (yield)")
                 end
          evaluated_arguments(node, pack, body, locals, scope)
        end

        def evaluated_arguments(node, pack, body, locals, scope)
          result = continuing_type(pack[:arguments], locals, type_of(body, scope))
          IR::ArgumentEvaluation.new(arguments: pack[:arguments].freeze, names: pack[:types].keys.freeze,
                                     body: body, result_type: result, span: node.span)
        end

        def resolved_yield(node, context, arguments, types, locals)
          context[:used] = true
          @literal_blocks.fetch(context.fetch(:id))[:used] = true
          body = yielding_body(context, types.fetch(0, :nil))
          IR::YieldInvoke.new(arguments: arguments, parameters: context.fetch(:block).parameters,
                              locals: context.fetch(:block).locals, body: body, block_id: context.fetch(:id),
                              result_type: continuing_type(arguments, locals, body.result_type), span: node.span)
        end

        def missing_block_error(node, locals, name, message)
          error = IR::CallError.new(class_name: name, message: message, label: nil, result_type: :never,
                                    span: node.span)
          validate_call_error(error, locals)
        end

        def yielding_body(context, type)
          saved = [@receiver_type, @method_context, @yield_context, @return_context, @retry_context, @constant_scopes]
          @receiver_type, @method_context, @yield_context, @return_context,
            @retry_context, @constant_scopes = context.fetch(:lexical)
          iterator_body(context.fetch(:block), type, context.fetch(:locals), exit_context: context)
        ensure
          @receiver_type, @method_context, @yield_context, @return_context, @retry_context, @constant_scopes = saved
        end

        def check_ignored_block(context)
          before = snapshot(context.fetch(:locals))
          exit_counts = flow_exit_counts
          yielding_body(context, :unknown)
        ensure
          restore(before, context.fetch(:locals))
          restore_flow_exits(exit_counts)
        end
      end

      include Exits
      include Captures
      include Yielding

      private

      def validate_block_call(node, locals)
        call = node.call
        unsupported(node) if call.safe_navigation
        receiver = validate_expression(call.receiver || IR::SelfRead.new(result_type: nil, span: node.span), locals)
        type = type_of(receiver, locals)
        return defer_block_call(node, receiver, locals) if type == :unknown

        unless user_block_receiver?(type)
          check_iterator_call(node)
          return validate_iterator_receiver(node, receiver, type, locals)
        end
        target = lookup_method(type.class_name, call.name)
        return validate_constructor_block(node, locals, receiver) if constructor_call?(call, type, target)

        unsupported(node) unless target && call.name != :initialize
        validate_user_block(node, receiver, type, target, locals)
      end

      def user_block_receiver?(type)
        type.is_a?(IR::ObjectType) && !array_type?(type) && !hash_type?(type)
      end

      def defer_block_call(node, receiver, locals)
        call = defer_call(node.call, receiver, locals)
        check_detached_block(node.block, locals, summarize: true)
        node.with(call: call, result_type: :unknown)
      end

      def validate_user_block(node, receiver, type, target, locals)
        check_method_visibility(node.call, type, target)
        prepared = prepare_arguments(node.call, target.last, locals, owner: target.first)
        return defer_block_call(node, receiver, locals) unless prepared.last

        context = new_literal_context(node.block, locals)
        @captured_scopes << locals
        context[:capture_depth] = @captured_scopes.length
        build_block_invocation(node, receiver, [type, target], prepared, context)
      ensure
        @captured_scopes.pop if context
      end

      def new_literal_context(block, locals)
        context = new_block_context(block, locals)
        context[:lexical] =
          [@receiver_type, @method_context, @yield_context, @return_context, @retry_context, @constant_scopes]
        @literal_blocks[context.fetch(:id)] = context
        context
      end

      def build_block_invocation(node, receiver, resolution, prepared, context)
        type, target = resolution
        body = user_block_body(node, type, target, prepared, context)
        invocation = resolved_block_method(node, receiver, target, prepared, body)
        @next_block_exit += 1
        exit_id = context[:receiving] == false ? @next_block_exit : context.fetch(:id)
        IR::BlockInvocation.new(exit_id: exit_id, block_id: context.fetch(:id), invocation: invocation,
                                result_type: body.result_type, span: node.span)
      end

      def user_block_body(node, type, target, prepared, context)
        owner, method = target
        _, parameters, bindings = prepared
        body = with_block_exit_context(context) do
          result = validate_method_body(method, parameters, type, node,
                                        owner: owner, block: context, bindings: bindings,
                                        construction: context[:construction])
          check_ignored_block(context) unless context[:used]
          result
        end
        parameters.value?(:never) ? body.with(result_type: :never) : body
      end

      def resolved_block_method(node, receiver, target, prepared, body)
        owner, method = target
        arguments, parameters, = prepared
        names = parameters.keys.freeze
        IR::MethodCall.new(class_name: owner, name: method.name, receiver: receiver, arguments: arguments,
                           parameters: names, locals: (method.locals + names).uniq.freeze, body: body,
                           result_type: body.result_type, span: node.span)
      end
    end
  end
end
