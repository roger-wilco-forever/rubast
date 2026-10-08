# frozen_string_literal: true

module Rubast
  module Backend
    module Blocks
      private

      # ponytail: inline yielding calls; add a closure ABI when generated size makes duplication costly.
      def emit_block_invocation(node, lines)
        method = node.invocation
        receiver = emit_value(emit_expression(method.receiver, lines), lines)
        arguments = method.arguments.map { |argument| emit_value(emit_expression(argument, lines), lines) }
        saved = [@locals, @receiver, @return_label, @loop_labels, @block_context]
        @block_context = saved
        @receiver = receiver
        @return_label = "block_exit_#{node.exit_id}"
        @loop_labels = nil
        statements = []
        inline_locals(method.locals, method.parameters.zip(arguments).to_h, statements)
        statements << "    #{emit_expression(method.body, statements)}"
        emit_value("'#{@return_label}: {\n#{statements.join("\n")}\n    }", lines)
      ensure
        @locals, @receiver, @return_label, @loop_labels, @block_context = saved if saved
      end

      def emit_yield(node, lines)
        arguments = node.arguments.map { |argument| emit_value(emit_expression(argument, lines), lines) }
        saved = [@locals, @receiver, @return_label, @loop_labels, @block_context]
        @locals, @receiver, @return_label, @loop_labels, @block_context = @block_context
        @locals = @locals.dup
        statements = []
        inline_locals(node.locals, node.parameters.to_h { |name| [name, arguments.fetch(0, "Value::Nil")] }, statements,
                      capture: true)
        statements << "    #{emit_expression(node.body, statements)}"
        emit_value("{\n#{statements.join("\n")}\n    }", lines)
      ensure
        @locals, @receiver, @return_label, @loop_labels, @block_context = saved if saved
      end

      def emit_block_body(node, lines)
        statements = []
        statements << "    #{emit_expression(node.body, statements)}"
        emit_value("'block_exit_#{node.exit_id}: {\n#{statements.join("\n")}\n    }", lines)
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
