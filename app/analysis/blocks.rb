# frozen_string_literal: true

module Rubast
  module Analysis
    module Blocks
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
          iterator_body(context.fetch(:block), type, context.fetch(:locals))
        ensure
          @receiver_type, @method_context, @yield_context = saved
        end

        def check_ignored_block(context)
          before = snapshot(context.fetch(:locals))
          yielding_body(context, :unknown)
        ensure
          restore(before, context.fetch(:locals))
        end
      end

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
        owner, method = target
        unsupported(node) unless node.call.arguments.length == method.parameters.length
        arguments, parameters = validate_arguments(node.call.arguments, method.parameters, locals)
        context = { block: node.block, locals: locals, lexical: [@receiver_type, @method_context, @yield_context] }
        @captured_scopes << locals
        body = validate_method_body(method, parameters, type, node, owner: owner, block: context)
        check_ignored_block(context) unless context[:used]
        body = body.with(result_type: :never) if parameters.value?(:never)
        resolved_block_invocation(node, receiver, target, arguments, body)
      ensure
        @captured_scopes.pop if context
      end

      def resolved_block_invocation(node, receiver, target, arguments, body)
        owner, method = target
        invocation = IR::MethodCall.new(class_name: owner, name: method.name, receiver: receiver, arguments: arguments,
                                        parameters: method.parameters, locals: method.locals, body: body,
                                        result_type: body.result_type, span: node.span)
        IR::BlockInvocation.new(invocation: invocation, result_type: body.result_type, span: node.span)
      end
    end
  end
end
