# frozen_string_literal: true

module Rubast
  module Backend
    class Rust
      MANIFEST = <<~TOML
        [package]
        name = "rubast_program"
        version = "0.1.0"
        edition = "2021"

        [dependencies]
        rubast_runtime = { path = "rubast_runtime" }
      TOML

      def call(program)
        GeneratedProject.new(files: {
          "Cargo.toml" => MANIFEST,
          "src/main.rs" => Emitter.new(program).call
        }.freeze)
      end

      class Emitter
        ESCAPES = {
          0 => "\\0", 9 => "\\t", 10 => "\\n", 13 => "\\r",
          34 => "\\\"", 92 => "\\\\"
        }.freeze

        def initialize(program)
          @program = program
          @locals = {}
          @next_temp = 0
        end

        def call
          lines = ["use rubast_runtime::{Runtime, Value};", "", "fn main() {",
                   "    let mut runtime = Runtime::new();"]
          @program.statements.each { |statement| emit_statement(statement, lines) }
          lines.push("}", "").join("\n")
        end

        private

        def emit_statement(node, lines)
          lines << "    let _ = #{emit_expression(node, lines)};"
        end

        def emit_local_write(node, lines)
          value = emit_expression(node.value, lines)
          @locals[node.name] = emit_value(value, lines)
          "#{@locals.fetch(node.name)}.clone()"
        end

        def emit_expression(node, lines)
          case node
          when IR::IntegerLiteral, IR::StringLiteral, IR::NilLiteral then emit_literal(node)
          when IR::LocalRead, IR::LocalWrite then emit_local(node, lines)
          when IR::GetLine then emit_value("runtime.gets()", lines)
          when IR::SafeChomp then "Runtime::safe_chomp(#{emit_expression(node.receiver, lines)})"
          when IR::InterpolatedString then emit_interpolation(node, lines)
          when IR::NewObject, IR::MethodCall then emit_object(node, lines)
          when IR::Puts, IR::Sequence then emit_body(node, lines)
          else raise ArgumentError, "unsupported semantic expression: #{node.class}"
          end
        end

        def emit_local(node, lines)
          node.is_a?(IR::LocalWrite) ? emit_local_write(node, lines) : "#{@locals.fetch(node.name)}.clone()"
        end

        def emit_literal(node)
          case node
          when IR::NilLiteral then "Value::Nil"
          when IR::IntegerLiteral then "Value::Integer(#{node.value})"
          when IR::StringLiteral then "Value::String(#{rust_string(node.value)}.to_owned())"
          end
        end

        def emit_value(value, lines)
          temp = "temp_#{@next_temp}"
          @next_temp += 1
          lines << "    let #{temp} = #{value};"
          temp
        end

        def emit_body(node, lines)
          if node.is_a?(IR::Puts)
            lines << "    runtime.puts(#{emit_expression(node.value, lines)});"
            "Value::Nil"
          else
            node.expressions[0...-1].each { |expression| emit_statement(expression, lines) }
            node.expressions.empty? ? "Value::Nil" : emit_expression(node.expressions.last, lines)
          end
        end

        def emit_object(node, lines)
          node.is_a?(IR::NewObject) ? "Value::Object" : emit_method_call(node, lines)
        end

        def emit_method_call(node, lines)
          lines << "    let _ = #{emit_expression(node.receiver, lines)};"
          arguments = node.arguments.map { |argument| emit_value(emit_expression(argument, lines), lines) }
          saved_locals = @locals
          @locals = node.locals.to_h { |name| [name, "Value::Nil"] }.merge(node.parameters.zip(arguments).to_h)
          emit_expression(node.body, lines)
        ensure
          @locals = saved_locals if saved_locals
        end

        def emit_interpolation(node, lines)
          parts = node.parts.map { |part| emit_expression(part, lines) }
          "Runtime::interpolate(vec![#{parts.join(', ')}])"
        end

        def rust_string(value)
          escaped = value.codepoints.map { |point| escape_codepoint(point) }.join
          "\"#{escaped}\""
        end

        def escape_codepoint(point)
          return ESCAPES.fetch(point) if ESCAPES.key?(point)
          return "\\u{#{point.to_s(16)}}" if point < 32 || (127..159).cover?(point)

          point.chr(Encoding::UTF_8)
        end
      end
    end
  end
end
