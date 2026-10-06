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
          @assignment_counts = program.statements.grep(IR::LocalWrite).map(&:name).tally
        end

        def call
          lines = ["use rubast_runtime::{Runtime, Value};", "", "fn main() {",
                   "    let mut runtime = Runtime::new();"]
          @program.statements.each { |statement| emit_statement(statement, lines) }
          lines.push("}", "").join("\n")
        end

        private

        def emit_statement(node, lines)
          case node
          when IR::LocalWrite then emit_local_write(node, lines)
          when IR::Puts then lines << "    runtime.puts(#{emit_expression(node.value, lines)});"
          else raise ArgumentError, "unsupported semantic statement: #{node.class}"
          end
        end

        def emit_local_write(node, lines)
          value = emit_expression(node.value, lines)
          if @locals.key?(node.name)
            lines << "    #{@locals.fetch(node.name)} = #{value};"
          else
            local = "local_#{@locals.length}"
            @locals[node.name] = local
            mutability = @assignment_counts.fetch(node.name) > 1 ? "mut " : ""
            lines << "    let #{mutability}#{local} = #{value};"
          end
        end

        def emit_expression(node, lines)
          case node
          when IR::IntegerLiteral then "Value::Integer(#{node.value})"
          when IR::StringLiteral then "Value::String(#{rust_string(node.value)}.to_owned())"
          when IR::LocalRead then "#{@locals.fetch(node.name)}.clone()"
          when IR::GetLine then emit_gets(lines)
          when IR::SafeChomp then "Runtime::safe_chomp(#{emit_expression(node.receiver, lines)})"
          when IR::InterpolatedString then emit_interpolation(node, lines)
          else raise ArgumentError, "unsupported semantic expression: #{node.class}"
          end
        end

        def emit_gets(lines)
          temp = "temp_#{@next_temp}"
          @next_temp += 1
          lines << "    let #{temp} = runtime.gets();"
          temp
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
