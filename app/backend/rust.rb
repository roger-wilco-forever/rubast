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
        functions = {}
        main = Emitter.new(functions).call(program)
        source = ["use rubast_runtime::{Runtime, Value};", "", *functions.values.map(&:last), main].join("\n")
        GeneratedProject.new(files: { "Cargo.toml" => MANIFEST, "src/main.rs" => source }.freeze)
      end

      def self.function(node, functions)
        key = [node.class_name, node.is_a?(IR::NewObject) ? :initialize : node.name, dispatches(node.body)]
        return functions.fetch(key).first if functions.key?(key)

        name = "method_#{functions.length}"
        functions[key] = [name, nil]
        functions[key][1] = Emitter.new(functions).method(node, name)
        name
      end

      def self.dispatches(node)
        return [] unless node.respond_to?(:span)

        # Types can contain cycles; only resolved calls affect emitted dispatch.
        children = node.to_h.except(:span, :result_type).values
        nested = children.flat_map { |value| Array(value).flat_map { |child| dispatches(child) } }
        case node
        when IR::MethodCall then [[node.class_name, node.name, nested]]
        when IR::NewObject then [[node.class_name, :initialize, nested]]
        when IR::Builtin then [[node.family, node.name, nested]]
        else nested
        end
      end

      ESCAPES = {
        0 => "\\0", 9 => "\\t", 10 => "\\n", 13 => "\\r",
        34 => "\\\"", 92 => "\\\\"
      }.freeze

      def self.literal(node)
        case node
        when IR::BooleanLiteral then "Value::Bool(#{node.value})"
        when IR::NilLiteral then "Value::Nil"
        when IR::IntegerLiteral then "Value::Integer(#{node.value})"
        when IR::StringLiteral then "Value::from(#{rust_string(node.value)}.to_owned())"
        when IR::SymbolLiteral then "Value::Symbol(#{rust_string(node.value)})"
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

      module ControlFlow
        private

        def emit_flow(node, lines)
          case node
          when IR::Puts, IR::Sequence then emit_body(node, lines)
          when IR::Conditional then emit_conditional(node, lines)
          when IR::Loop, IR::LoopExit then emit_loop_flow(node, lines)
          when IR::Return then "{ return #{emit_expression(node.value, lines)}; }"
          when IR::Operation
            operands = node.operands.map { |operand| emit_value(emit_expression(operand, lines), lines) }
            name = Rust.rust_string(node.name.to_s)
            function = operands.one? ? "unary" : "binary"
            emit_value("Runtime::#{function}(#{name}, #{operands.join(', ')})", lines)
          end
        end

        def emit_conditional(node, lines)
          predicate = emit_value(emit_expression(node.predicate, lines), lines)
          branches = [node.consequent, node.alternative].map do |branch|
            statements = []
            statements << "    #{emit_expression(branch, statements)}"
            statements.map { |statement| "    #{statement}" }.join("\n")
          end
          expression = "if Runtime::truthy(&#{predicate}) {\n#{branches.first}\n    } else {\n#{branches.last}\n    }"
          emit_value(expression, lines)
        end

        def initialize_locals(names, parameters, lines)
          @locals = names.each_with_index.to_h { |name, index| [name, "local_#{index}"] }
          @locals.each do |name, binding|
            lines << "    let mut #{binding} = #{parameters.fetch(name, 'Value::Nil')};"
          end
        end
      end

      module Loops
        private

        def emit_loop_flow(node, lines)
          return emit_loop(node, lines) if node.is_a?(IR::Loop)

          value = emit_expression(node.value, lines)
          if node.kind == :break
            "{ break '#{@loop_labels.first} #{value}; }"
          else
            "{ let _ = #{value}; break '#{@loop_labels.last}; }"
          end
        end

        def emit_loop(node, lines)
          previous = @loop_labels
          @loop_labels = ["loop_#{@next_temp}", "iteration_#{@next_temp}"]
          @next_temp += 1
          predicate = []
          condition = emit_expression(node.predicate, predicate)
          test = "Runtime::truthy(&#{condition})"
          test = "!#{test}" unless node.until_loop
          predicate << "    if #{test} { break '#{@loop_labels.first} Value::Nil; }"
          body = []
          body << "    let _ = #{emit_expression(node.body, body)};"
          iteration = "    '#{@loop_labels.last}: {\n#{body.join("\n")}\n    };"
          parts = node.post_test ? [iteration, *predicate] : [*predicate, iteration]
          expression = "'#{@loop_labels.first}: loop {\n#{parts.join("\n")}\n    }"
          emit_value(expression, lines)
        ensure
          @loop_labels = previous
        end
      end

      module Collections
        private

        def emit_allocation_or_call(node, lines)
          if node.is_a?(IR::ArrayLiteral) || node.is_a?(IR::HashLiteral) || node.is_a?(IR::Builtin)
            emit_collection(node, lines)
          else
            emit_object(node, lines)
          end
        end

        def emit_collection(node, lines)
          return emit_container(node, lines) if node.is_a?(IR::ArrayLiteral) || node.is_a?(IR::HashLiteral)

          receiver = emit_value(emit_expression(node.receiver, lines), lines)
          arguments = node.arguments.map { |argument| emit_value(emit_expression(argument, lines), lines) }
          inputs = "#{Rust.rust_string(node.name.to_s)}, #{receiver}, vec![#{arguments.join(', ')}]"
          target = node.family == :string ? "Runtime::string_operation" : "runtime.#{node.family}_operation"
          emit_value("#{target}(#{inputs})", lines)
        end

        def emit_container(node, lines)
          elements = node.elements.map { |element| emit_value(emit_expression(element, lines), lines) }
          hash = node.is_a?(IR::HashLiteral)
          target = hash ? "new_hash" : "new_array"
          elements = elements.each_slice(2).map { |key, value| "(#{key}, #{value})" } if hash
          emit_value("runtime.#{target}(vec![#{elements.join(', ')}])", lines)
        end
      end

      class Emitter
        include ControlFlow
        include Loops
        include Collections

        def initialize(functions)
          @functions = functions
          @locals = {}
          @next_temp = 0
        end

        def call(program)
          lines = ["fn main() {", "    let runtime = &mut Runtime::new();"]
          program.warnings.each { |warning| lines << "    eprintln!(\"{}\", #{Rust.rust_string(warning)});" }
          initialize_locals(program.locals, {}, lines)
          program.statements.each { |statement| emit_statement(statement, lines) }
          lines.push("}", "").join("\n")
        end

        def method(node, name)
          parameters = node.parameters.each_with_index.to_h { |parameter, index| [parameter, "arg_#{index}"] }
          @receiver = "receiver"
          signature = ["runtime: &mut Runtime", "receiver: Value", *parameters.values.map { |arg| "#{arg}: Value" }]
          lines = ["fn #{name}(#{signature.join(', ')}) -> Value {"]
          initialize_locals(node.locals, parameters, lines)
          lines << "    #{emit_expression(node.body, lines)}"
          lines.push("}", "").join("\n")
        end

        private

        def emit_statement(node, lines)
          lines << "    let _ = #{emit_expression(node, lines)};"
        end

        def emit_local_write(node, lines)
          value = emit_expression(node.value, lines)
          lines << "    #{@locals.fetch(node.name)} = #{value};"
          emit_value("#{@locals.fetch(node.name)}.clone()", lines)
        end

        def emit_expression(node, lines)
          case node
          when IR::IntegerLiteral, IR::StringLiteral, IR::NilLiteral, IR::BooleanLiteral, IR::SymbolLiteral
            Rust.literal(node)
          when IR::LocalRead, IR::LocalWrite, IR::InstanceRead, IR::InstanceWrite, IR::SelfRead
            emit_variable(node, lines)
          when IR::GetLine then emit_value("runtime.gets()", lines)
          when IR::SafeChomp then "Runtime::safe_chomp(#{emit_expression(node.receiver, lines)})"
          when IR::InterpolatedString then emit_interpolation(node, lines)
          when IR::NewObject, IR::MethodCall, IR::ArrayLiteral, IR::HashLiteral, IR::Builtin
            emit_allocation_or_call(node, lines)
          when IR::Puts, IR::Sequence, IR::Conditional, IR::Return, IR::Operation, IR::Loop, IR::LoopExit
            emit_flow(node, lines)
          else raise ArgumentError, "unsupported semantic expression: #{node.class}"
          end
        end

        def emit_variable(node, lines)
          case node
          when IR::SelfRead then "#{@receiver}.clone()"
          when IR::InstanceRead
            emit_value("runtime.get_ivar(&#{@receiver}, #{Rust.rust_string(node.name.to_s)})", lines)
          when IR::InstanceWrite
            value = emit_expression(node.value, lines)
            emit_value("runtime.set_ivar(&#{@receiver}, #{Rust.rust_string(node.name.to_s)}, #{value})", lines)
          when IR::LocalWrite then emit_local_write(node, lines)
          else emit_value("#{@locals.fetch(node.name)}.clone()", lines)
          end
        end

        def emit_value(value, lines)
          temp = "temp_#{@next_temp}"
          @next_temp += 1
          lines << "    let #{temp}: Value = #{value};"
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
          return "#{receiver}.clone()" if node.is_a?(IR::NewObject) && node.body.expressions.empty?

          function = Rust.function(node, @functions)
          inputs = ["runtime", "#{receiver}.clone()", *arguments]
          result = emit_value("#{function}(#{inputs.join(', ')})", lines)
          node.is_a?(IR::NewObject) ? "#{receiver}.clone()" : result
        end

        def emit_interpolation(node, lines)
          parts = node.parts.map { |part| emit_expression(part, lines) }
          "Runtime::interpolate(vec![#{parts.join(', ')}])"
        end
      end
    end
  end
end
