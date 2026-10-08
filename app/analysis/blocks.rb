# frozen_string_literal: true

module Rubast
  module Analysis
    module Blocks
      module Exits
        private

        def new_block_context(block, locals)
          @next_block_exit += 1
          { id: @next_block_exit, block: block, locals: locals, exits: [], capture_depth: @captured_scopes.length }
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
          unsupported(node) unless node.kind == :break && @block_exit_context
          value = validate_expression(node.value, locals)
          type = type_of(value, locals)
          check_exiting_traversals(node)
          @block_exit_context.fetch(:exits) << [type, block_exit_state(locals)] unless type == :never
          IR::BlockExit.new(target: @block_exit_context.fetch(:id), value: value, span: node.span)
        end

        def check_exiting_traversals(node)
          @block_exit_contexts.each do |context|
            traversal = context[:traversal]
            check_iterator_length(*traversal, node) if traversal
          end
        end

        def block_exit_state(locals)
          root = @block_exit_context.fetch(:locals)
          state = snapshot(locals)
          state[:locals] = locals.slice(*root.keys)
          state[:captures] = state.fetch(:captures).take(@block_exit_context.fetch(:capture_depth))
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
          arguments, types = validate_arguments(node.arguments, (0...node.arguments.length).to_a, locals)
          unless @yield_context
            unsupported(node) unless @checking_unused && @method_context
            return node.with(arguments: arguments, result_type: :unknown)
          end
          context = @yield_context
          context[:used] = true
          body = yielding_body(context, types.fetch(0, :nil))
          IR::YieldInvoke.new(arguments: arguments, parameters: context.fetch(:block).parameters,
                              locals: context.fetch(:block).locals, body: body,
                              result_type: continuing_type(arguments, locals, body.result_type), span: node.span)
        end

        def yielding_body(context, type)
          saved = [@receiver_type, @method_context, @yield_context]
          @receiver_type, @method_context, @yield_context = context.fetch(:lexical)
          iterator_body(context.fetch(:block), type, context.fetch(:locals), exit_context: context)
        ensure
          @receiver_type, @method_context, @yield_context = saved
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
        unsupported(node) if call.safe_navigation || call.receiver.is_a?(IR::ConstantRead)
        receiver = validate_expression(call.receiver || IR::SelfRead.new(result_type: nil, span: node.span), locals)
        type = type_of(receiver, locals)
        return defer_block_call(node, receiver, locals) if type == :unknown

        unless user_block_receiver?(type)
          check_iterator_call(node)
          return validate_iterator_receiver(node, receiver, type, locals)
        end
        target = lookup_method(type.class_name, call.name)
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
        method = target.last
        unsupported(node) unless node.call.arguments.length == method.parameters.length
        arguments, parameters = validate_arguments(node.call.arguments, method.parameters, locals)
        context = new_block_context(node.block, locals)
        context[:lexical] = [@receiver_type, @method_context, @yield_context]
        @captured_scopes << locals
        context[:capture_depth] = @captured_scopes.length
        body = user_block_body(node, type, target, parameters, context)
        invocation = resolved_block_method(node, receiver, target, arguments, body)
        IR::BlockInvocation.new(exit_id: context.fetch(:id), invocation: invocation,
                                result_type: body.result_type, span: node.span)
      ensure
        @captured_scopes.pop if context
      end

      def user_block_body(node, type, target, parameters, context)
        owner, method = target
        body = with_block_exit_context(context) do
          result = validate_method_body(method, parameters, type, node, owner: owner, block: context)
          check_ignored_block(context) unless context[:used]
          result
        end
        parameters.value?(:never) ? body.with(result_type: :never) : body
      end

      def resolved_block_method(node, receiver, target, arguments, body)
        owner, method = target
        IR::MethodCall.new(class_name: owner, name: method.name, receiver: receiver, arguments: arguments,
                           parameters: method.parameters, locals: method.locals, body: body,
                           result_type: body.result_type, span: node.span)
      end
    end
  end
end
