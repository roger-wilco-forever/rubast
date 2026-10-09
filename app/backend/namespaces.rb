# frozen_string_literal: true

module Rubast
  module Backend
    module Namespaces
      private

      def emit_source_load(node, lines)
        frames = [location(node.span), *node.frames.map { |span, label| location(span, label) }]
        saved = block_environment
        @frame_name = "<top (required)>"
        @block_depth = 0
        traced_result(frames, lines) do |parts|
          node.program.warnings.each { |warning| parts << "    eprintln!(\"{}\", #{Rust.rust_string(warning)});" }
          inline_locals(node.program.locals, {}, parts)
          node.program.statements.each { |statement| emit_statement(statement, parts) }
          "Value::Bool(true)"
        end
      ensure
        restore_block_environment(saved)
      end

      def method_label(node)
        name = node.is_a?(IR::NewObject) ? :initialize : node.name
        owner = node.class_name
        owner = owner.key if owner.is_a?(IR::MethodOwner)
        owner.is_a?(IR::SingletonClass) ? "#{owner.name}.#{name}" : "#{owner}##{name}"
      end

      def emit_namespace(node, lines)
        return emit_source_load(node, lines) if node.is_a?(IR::SourceLoad)

        return emit_object(node.call, lines, assignment: true) if node.is_a?(IR::Setter)
        return emit_value("runtime.new_object()", lines) if node.is_a?(IR::ClassValue)
        return emit_value("runtime.constant(#{Rust.rust_string(node.name.to_s)})", lines) if node.is_a?(IR::ConstantGet)

        if node.is_a?(IR::ConstantSet)
          value = emit_expression(node.value, lines)
          return emit_value("runtime.set_constant(#{Rust.rust_string(node.name.to_s)}, #{value})", lines)
        end
        emit_namespace_body(node, lines)
      end

      def emit_namespace_body(node, lines)
        caller = location(node.span)
        saved = block_environment
        @receiver = nil
        @frame_name = "<#{node.kind}:#{node.label || node.name.to_s.split('::').last}>"
        @block_depth = 0
        traced_result([caller], lines) do |parts|
          inline_locals(node.locals, {}, parts)
          # The first expression allocates a new namespace or reads the reopened class/module object.
          first, *rest = node.body.expressions
          @receiver = emit_value(emit_expression(first, parts), parts)
          body = node.body.with(expressions: rest.freeze)
          emit_expression(body, parts)
        end
      ensure
        restore_block_environment(saved)
      end
    end
  end
end
