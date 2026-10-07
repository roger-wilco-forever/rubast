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

      ESCAPES = {
        0 => "\\0", 9 => "\\t", 10 => "\\n", 13 => "\\r",
        34 => "\\\"", 92 => "\\\\"
      }.freeze

      def self.literal(node)
        case node
        when IR::NilLiteral then "Value::Nil"
        when IR::IntegerLiteral then "Value::Integer(#{node.value})"
        when IR::StringLiteral then "Value::String(#{rust_string(node.value)}.to_owned())"
        end
      end

      def self.rust_string(value)
        escaped = value.codepoints.map { |point| escape_codepoint(point) }.join
        "\"#{escaped}\""
      end

      def self.escape_codepoint(point)
        return ESCAPES.fetch(point) if ESCAPES.key?(point)
        return "\\u{#{point.to_s(16)}}" if point < 32 || (127..159).cover?(point)

        point.chr(Encoding::UTF_8)
      end

      class Emitter
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
          when IR::IntegerLiteral, IR::StringLiteral, IR::NilLiteral then Rust.literal(node)
          when IR::LocalRead, IR::LocalWrite, IR::InstanceRead, IR::InstanceWrite then emit_variable(node, lines)
          when IR::GetLine then emit_value("runtime.gets()", lines)
          when IR::SafeChomp then "Runtime::safe_chomp(#{emit_expression(node.receiver, lines)})"
          when IR::InterpolatedString then emit_interpolation(node, lines)
          when IR::NewObject, IR::MethodCall then emit_object(node, lines)
          when IR::Puts, IR::Sequence then emit_body(node, lines)
          else raise ArgumentError, "unsupported semantic expression: #{node.class}"
          end
        end

        def emit_variable(node, lines)
          case node
          when IR::InstanceRead
            emit_value("runtime.get_ivar(&#{@receiver}, #{Rust.rust_string(node.name.to_s)})", lines)
          when IR::InstanceWrite
            value = emit_expression(node.value, lines)
            emit_value("runtime.set_ivar(&#{@receiver}, #{Rust.rust_string(node.name.to_s)}, #{value})", lines)
          when IR::LocalWrite then emit_local_write(node, lines)
          else "#{@locals.fetch(node.name)}.clone()"
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
          receiver = emit_value(emit_expression(node.receiver, lines), lines) if node.is_a?(IR::MethodCall)
          arguments = node.arguments.map { |argument| emit_value(emit_expression(argument, lines), lines) }
          receiver ||= emit_value("runtime.new_object()", lines)
          result = emit_invocation(node, receiver, arguments, lines)
          node.is_a?(IR::NewObject) ? "#{receiver}.clone()" : result
        end

        def emit_invocation(node, receiver, arguments, lines)
          saved_locals = @locals
          saved_receiver = @receiver
          @receiver = receiver
          @locals = node.locals.to_h { |name| [name, "Value::Nil"] }.merge(node.parameters.zip(arguments).to_h)
          emit_value(emit_expression(node.body, lines), lines)
        ensure
          @locals = saved_locals
          @receiver = saved_receiver
        end

        def emit_interpolation(node, lines)
          parts = node.parts.map { |part| emit_expression(part, lines) }
          "Runtime::interpolate(vec![#{parts.join(', ')}])"
        end
      end
    end
  end
end
