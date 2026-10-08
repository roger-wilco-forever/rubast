# frozen_string_literal: true

module Rubast
  module Analysis
    module BlockArguments
      module SuperCalls
        private

        def validate_super_invocation(node, call, receiver, target, locals)
          if node.block.is_a?(IR::Block)
            literal = IR::BlockCall.new(call: call, block: node.block, result_type: nil, span: node.span)
            return validate_user_block(literal, receiver, @receiver_type, target, locals)
          end
          unless @yield_context || node.block
            return validate_object_call(call, receiver, @receiver_type, target, locals)
          end

          if node.block
            passed = IR::BlockPass.new(call: call, value: node.block, result_type: nil, span: node.span)
            return validate_passed_block(passed, receiver, [@receiver_type, target], locals)
          end
          prepared = prepare_arguments(call, target.last, locals, owner: target.first)
          type = IR::BlockType.new(id: @yield_context.fetch(:id))
          forwarded_block_invocation(node, receiver, [@receiver_type, target], prepared, type)
        end
      end

      module Conversions
        private

        def checked_block_conversion(node, receiver, prepared, value, locals)
          type = type_of(value, locals)
          return if type == :nil || type == :unknown || type.is_a?(IR::BlockType)

          expressions = [receiver, *prepared.first].compact
          unless type == :never
            name = block_conversion_name(type, node)
            error = IR::CallError.new(class_name: :TypeError, message: "wrong argument type #{name} (expected Proc)",
                                      label: nil, result_type: :never, span: node.span)
            expressions << validate_call_error(error, locals)
          end
          IR::Sequence.new(expressions: expressions.freeze, result_type: :never, span: node.span)
        end

        def block_conversion_name(type, origin)
          case type
          when IR::IntegerType then "Integer"
          when :boolean
            unsupported(origin) unless origin.value.is_a?(IR::BooleanLiteral)
            origin.value.value ? "TrueClass" : "FalseClass"
          when :string, :frozen_string then "String"
          when IR::ObjectType
            unsupported(origin) if lookup_method(type.class_name, :to_proc)
            type.class_name.to_s
          else unsupported(origin)
          end
        end
      end

      module Constructors
        private

        def validate_constructor_block(node, locals)
          type, target = constructor_block_target(node)
          prepared = prepare_arguments(node.call, target.last, locals, owner: target.first)
          unsupported(node) unless prepared.last
          context = new_literal_context(node.block, locals)
          context[:construction] = type
          @captured_scopes << locals
          context[:capture_depth] = @captured_scopes.length
          result = build_block_invocation(node, nil, [type, target], prepared, context)
          result.with(invocation: constructor_invocation(result.invocation, result.result_type))
        ensure
          @captured_scopes.pop if context
        end

        def constructor_block_target(node)
          call = node.call
          name = call.receiver.name
          unsupported(node) if @loop_depth&.positive?
          unsupported(node) unless call.name == :new && @classes.key?(name)
          type = object_type(name, :nil)
          owner, method = lookup_method(name, :initialize)
          [type, [owner || :BasicObject, method || default_initializer(call)]]
        end

        def constructor_invocation(method, type)
          IR::NewObject.new(**method.to_h.except(:name, :receiver), result_type: type)
        end
      end

      include SuperCalls
      include Constructors
      include Conversions

      private

      # ponytail: named blocks remain tied to literal call sites; escaped Proc values need a closure ABI.
      def validate_block_pass(node, locals)
        call = node.call
        unsupported(node) if call.safe_navigation
        if call.receiver.is_a?(IR::ConstantRead)
          type, target = constructor_block_target(node)
          receiver = nil
        else
          receiver = validate_expression(call.receiver || IR::SelfRead.new(result_type: nil, span: call.span), locals)
          type = type_of(receiver, locals)
          return defer_block_pass(node, receiver, locals) if type == :unknown

          target = block_method_target(call, type)
        end
        validate_passed_block(node, receiver, [type, target], locals)
      end

      def validate_passed_block(node, receiver, resolution, locals)
        _, target = resolution
        prepared = prepare_arguments(node.call, target.last, locals, owner: target.first)
        value = validate_expression(node.value, locals)
        prepared = append_block_argument(prepared, value, locals)
        error = checked_block_conversion(node, receiver, prepared, value, locals)
        return error if error

        unless prepared.last
          unsupported(node) unless @checking_unused
          return node.with(call: node.call.with(receiver: receiver, arguments: prepared.first),
                           value: value, result_type: :unknown)
        end

        forwarded_block_invocation(node, receiver, resolution, prepared, type_of(value, locals))
      end

      def block_method_target(call, type)
        unsupported(call) unless user_block_receiver?(type) && call.name != :initialize
        target = lookup_method(type.class_name, call.name)
        unsupported(call) unless target
        target
      end

      def append_block_argument(prepared, value, locals)
        arguments, types, bindings = prepared
        name = [:argument, arguments.length, :block].freeze
        [[*arguments, value].freeze, types.merge(name => type_of(value, locals)), bindings]
      end

      def defer_block_pass(node, receiver, locals)
        call = defer_call(node.call, receiver, locals)
        node.with(call: call, value: validate_expression(node.value, locals), result_type: :unknown)
      end

      def forwarded_block_invocation(node, receiver, resolution, prepared, block_type)
        type, target = resolution
        unsupported(node) unless prepared.last
        if block_type == :unknown && @checking_unused
          body = IR::Sequence.new(expressions: [].freeze, result_type: :unknown, span: node.span)
          return resolved_block_method(node, receiver, target, prepared, body)
        end
        return no_block_invocation(node, receiver, resolution, prepared) if block_type == :nil

        unsupported(node) unless block_type.is_a?(IR::BlockType)
        context = @literal_blocks.fetch(block_type.id).except(:construction).merge(receiving: false)
        context[:construction] = type unless receiver
        result = build_block_invocation(node, receiver, resolution, prepared, context)
        receiver ? result : result.with(invocation: constructor_invocation(result.invocation, result.result_type))
      end

      def no_block_invocation(node, receiver, resolution, prepared)
        type, target = resolution
        body = validate_method_body(target.last, prepared[1], type, node,
                                    owner: target.first, bindings: prepared.last)
        result = resolved_block_method(node, receiver, target, prepared, body)
        receiver ? result : constructor_invocation(result, continuing_type(body, {}, type))
      end

      def validate_block_receiver(node, receiver, type, locals)
        return validate_operation(node, receiver, type, locals) if %i[== != !].include?(node.name)

        unsupported(node) unless node.name == :call
        if type == :nil
          pack = call_payload(node, locals)
          error = missing_block_error(node, locals, :NoMethodError, "undefined method 'call' for nil")
          return IR::Sequence.new(expressions: [receiver, *pack[:arguments], error].freeze,
                                  result_type: :never, span: node.span)
        end
        invocation = validate_block_execution(node, @literal_blocks.fetch(type.id), locals)
        IR::Sequence.new(expressions: [receiver, invocation].freeze,
                         result_type: invocation.result_type, span: node.span)
      end

      def block_receiver_call?(node, type)
        type.is_a?(IR::BlockType) || (type == :nil && node.name == :call)
      end

      def dead_receiver_call(node, receiver, locals)
        before = snapshot(locals)
        counts = flow_exit_counts
        arguments = call_payload(node, locals).fetch(:arguments)
        IR::Sequence.new(expressions: [receiver, *arguments].freeze, result_type: :never, span: node.span)
      ensure
        restore(before, locals)
        restore_flow_exits(counts)
      end

      def block_type?(type)
        members(type).any?(IR::BlockType)
      end
    end
  end
end
