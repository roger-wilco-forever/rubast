# frozen_string_literal: true

module Rubast
  module Backend
    module Iterators
      private

      # ponytail: emit a body per known step; group identical dispatch into loops if generated size matters.
      def emit_iterator(node, lines)
        receiver = emit_value(emit_expression(node.receiver, lines), lines)
        caller = location(node.span)
        builtin = if node.name == :times
                    'Location::new("<internal:numeric>", 257, "Integer#times")'
                  else
                    location(node.span, "Array##{node.name}")
                  end
        traced_result([caller, builtin], lines) do |_statements|
          with_target("block_exit_#{node.exit_id}") do
            body = []
            result = emit_iterator_steps(node, receiver, body)
            body << "    #{result}"
            "'block_exit_#{node.exit_id}: {\n#{body.join("\n")}\n    }"
          end
        end
      end

      def emit_iterator_steps(node, receiver, lines)
        results = "map_values_#{@next_temp}"
        @next_temp += 1
        lines << "    let mut #{results}: Vec<Value> = Vec::new();" if node.name == :map
        node.steps.each do |step|
          statements = []
          value = emit_iterator_step(node, step, receiver, statements)
          statements << "    #{results}.push(#{value});" if node.name == :map
          if step.guarded
            condition = iterator_guard(node, step, receiver)
            lines << "    if Runtime::truthy(&#{condition}) {\n#{statements.join("\n")}\n    }"
          else
            lines.concat(statements)
          end
        end
        node.name == :map ? emit_value("runtime.new_array(#{results})", lines) : "#{receiver}.clone()"
      end

      def iterator_guard(node, step, receiver)
        count = if node.family == :integer
                  "#{receiver}.clone()"
                else
                  "runtime.array_operation(\"length\", #{receiver}.clone(), vec![])"
                end
        "Runtime::binary(\"<\", Value::Integer(#{step.index}), #{count})"
      end

      def emit_iterator_step(node, step, receiver, lines)
        previous = [@locals, @block_depth]
        @block_depth += 1
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
        @locals, @block_depth = previous
      end

      def iterator_argument(node, step, receiver)
        value = "Value::Integer(#{step.index})"
        return value if node.family == :integer

        "runtime.array_operation(\"[]\", #{receiver}.clone(), vec![#{value}])"
      end
    end
  end
end
