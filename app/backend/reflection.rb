# frozen_string_literal: true

module Rubast
  module Backend
    module Reflection
      private

      def emit_reflection(node, lines)
        if node.name == :identifier_known
          return emit_value("Value::Bool(runtime.identifier_known(#{Rust.rust_string(node.signature)}))", lines)
        end
        return emit_reflective_field(node, lines) unless node.name == :respond_to?

        caller = location(node.span)
        saved = @frame_name
        @frame_name = "Kernel#respond_to?"
        traced_result([caller], lines) { |parts| emit_expression(node.body, parts) }
      ensure
        @frame_name = saved if node.name == :respond_to?
      end

      def emit_reflective_field(node, lines)
        receiver = emit_value(emit_expression(node.body.receiver, lines), lines)
        name = Rust.rust_string(node.signature)
        if node.name == :instance_variable_get
          emit_value("runtime.get_ivar(&#{receiver}, #{name})", lines)
        else
          value = emit_expression(node.body.arguments.last, lines)
          emit_value("runtime.set_reflected_ivar(&#{receiver}, #{name}, #{value})", lines)
        end
      end
    end
  end
end
