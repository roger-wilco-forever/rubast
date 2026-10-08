# frozen_string_literal: true

module Rubast
  module Backend
    module Iterators
      private

      # ponytail: emit a body per known step; group identical dispatch into loops if generated size matters.
      def emit_iterator(node, lines)
        receiver = emit_value(emit_expression(node.receiver, lines), lines)
        results = node.steps.map { |step| emit_iterator_step(node, step, receiver, lines) }
        return "#{receiver}.clone()" unless node.name == :map

        emit_value("runtime.new_array(vec![#{results.join(', ')}])", lines)
      end

      def emit_iterator_step(node, step, receiver, lines)
        previous = @locals
        @locals = @locals.dup
        prefix = "block_#{@next_temp}"
        @next_temp += 1
        statements = []
        node.locals.each_with_index do |name, index|
          binding = "#{prefix}_local_#{index}"
          @locals[name] = binding
          value = node.parameters.include?(name) ? iterator_argument(node, step, receiver) : "Value::Nil"
          statements << "    let mut #{binding}: Value = #{value};"
        end
        statements << "    #{emit_expression(step.body, statements)}"
        emit_value("{\n#{statements.join("\n")}\n    }", lines)
      ensure
        @locals = previous
      end

      def iterator_argument(node, step, receiver)
        value = "Value::Integer(#{step.index})"
        return value if node.family == :integer

        "runtime.array_operation(\"[]\", #{receiver}.clone(), vec![#{value}])"
      end
    end
  end
end
