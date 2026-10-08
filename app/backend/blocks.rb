# frozen_string_literal: true

module Rubast
  module Backend
    module Blocks
      private

      # ponytail: inline yielding calls; add a closure ABI when generated size makes duplication costly.
      def emit_block_invocation(node, lines)
        method = node.invocation
        value = emit_value(emit_expression(method.receiver, lines), lines) if method.receiver
        receiver = value unless method.is_a?(IR::NewObject)
        arguments = method.arguments.map { |argument| emit_value(emit_expression(argument, lines), lines) }
        return emit_native_argument_error(method, lines) if native_argument_error?(method)

        receiver ||= emit_value("runtime.new_object()", lines)
        caller = location(node.span)
        saved = block_environment
        enter_block_method(node, receiver, saved)
        return emit_block_constructor(node, arguments, caller, lines) if method.is_a?(IR::NewObject)

        emit_inline_method(method, arguments, caller, lines)
      ensure
        restore_block_environment(saved) if saved
      end

      def enter_block_method(node, receiver, saved)
        method = node.invocation
        @block_environments[node.block_id] ||= saved
        @block_context = @block_environments.fetch(node.block_id)
        @receiver = receiver
        @return_label = "block_exit_#{node.exit_id}"
        @loop_labels = nil
        @retry_label = nil
        @frame_name = method_label(method)
        @block_depth = 0
      end

      def emit_argument_evaluation(node, lines)
        arguments = node.arguments.map { |argument| emit_value(emit_expression(argument, lines), lines) }
        saved = @locals
        @locals = @locals.merge(node.names.zip(arguments).to_h)
        emit_expression(node.body, lines)
      ensure
        @locals = saved if saved
      end

      def emit_block_constructor(node, arguments, caller, lines)
        label = @return_label
        with_target(label) do
          statements = []
          @return_label = "initializer_#{node.exit_id}"
          emit_inline_method(node.invocation, arguments, caller, statements)
          statements << "    #{@receiver}.clone()"
          emit_value("'#{label}: {\n#{statements.join("\n")}\n    }", lines)
        end
      end

      def emit_inline_method(method, arguments, caller, lines)
        frames = [caller]
        frames << location(method.span, "Class#new") if method.is_a?(IR::NewObject)
        traced_result(frames, lines) do |statements|
          with_target(@return_label) do
            inline_locals(method.locals, method.parameters.zip(arguments).to_h, statements)
            body = []
            body << "    #{emit_expression(method.body, body)}"
            "'#{@return_label}: {\n#{body.join("\n")}\n    }"
          end
        end
      end

      def emit_yield(node, lines)
        arguments = node.arguments.map { |argument| emit_value(emit_expression(argument, lines), lines) }
        caller = location(node.span)
        saved = block_environment
        restore_block_environment(@block_environments.fetch(node.block_id))
        @locals = @locals.dup
        @block_depth += 1
        traced_result([caller], lines) do |statements|
          inline_locals(node.locals, node.parameters.to_h do |name|
            [name, arguments.fetch(0, "Value::Nil")]
          end, statements,
                        capture: true)
          emit_expression(node.body, statements)
        end
      ensure
        restore_block_environment(saved) if saved
      end

      def block_environment
        [@locals, @receiver, @return_label, @loop_labels, @block_context, @frame_name, @block_depth, @retry_label]
      end

      def restore_block_environment(values)
        @locals, @receiver, @return_label, @loop_labels, @block_context, @frame_name,
          @block_depth, @retry_label = values
      end

      def emit_block_body(node, lines)
        with_target("block_exit_#{node.exit_id}") do
          statements = []
          statements << "    #{emit_expression(node.body, statements)}"
          emit_value("'block_exit_#{node.exit_id}: {\n#{statements.join("\n")}\n    }", lines)
        end
      end

      def inline_locals(names, parameters, lines, capture: false)
        @locals = {} unless capture
        prefix = "inline_#{@next_temp}"
        @next_temp += 1
        names.each_with_index do |name, index|
          binding = "#{prefix}_local_#{index}"
          @locals[name] = binding
          lines << "    let mut #{binding}: Value = #{parameters.fetch(name, 'Value::Nil')};"
        end
      end
    end
  end
end
