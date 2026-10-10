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
        source = ["use rubast_runtime::{Runtime, Value, Flow, Outcome, Location};", "", *functions.values.map(&:last),
                  main].join("\n")
        GeneratedProject.new(files: { "Cargo.toml" => MANIFEST, "src/main.rs" => source,
                                      "source-map.json" => SourceMap.call(source) }.freeze)
      end

      def self.function(node, functions)
        key = [node.class_name, node.is_a?(IR::NewObject) ? :initialize : node.name,
               node.body.span, node.parameters, dispatches(node.body)]
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
        dispatch_signature(node, nested)
      end

      def self.dispatch_signature(node, nested)
        case node
        when IR::MethodCall then [[node.class_name, node.name, node.body.span, nested]]
        when IR::NewObject then [[node.class_name, :initialize, node.body.span, nested]]
        when IR::Builtin then [[node.family, node.name, nested]]
        when IR::Reflection then [[node.name, node.signature, nested]]
        when IR::CallError then [[node.class_name, node.message, node.label, node.span]]
        when IR::BlockInvocation then [[node.invocation.class_name, invocation_name(node.invocation),
                                        block_signature(node.invocation.body)]]
        when IR::Iterator then [iterator_signature(node, nested)]
        else nested
        end
      end

      def self.iterator_signature(node, nested)
        [node.family, node.name, node.steps.map(&:guarded), nested]
      end

      def self.invocation_name(node)
        node.is_a?(IR::NewObject) ? :initialize : node.name
      end

      def self.block_signature(node)
        return node.map { |child| block_signature(child) } if node.is_a?(Array)
        return node unless node.respond_to?(:span)

        [node.class.name, node.to_h.except(:span, :result_type).transform_values { |child| block_signature(child) }]
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
        when IR::StringLiteral
          text = "#{rust_string(node.value)}.to_owned()"
          node.frozen ? "Value::frozen(#{text}, #{rust_string(node.value.inspect)})" : "Value::from(#{text})"
        when IR::SymbolLiteral, IR::BlockValue, IR::IOReference then named_literal(node)
        end
      end

      def self.named_literal(node)
        return "Value::Block(#{node.id})" if node.is_a?(IR::BlockValue)
        return "Value::Stream(#{rust_string(node.result_type.to_s)})" if node.is_a?(IR::IOReference)

        "Value::Symbol(#{rust_string(node.value)}, #{rust_string(node.value.to_sym.inspect)})"
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
          when IR::Print, IR::Sequence then emit_body(node, lines)
          when IR::Conditional then emit_conditional(node, lines)
          when IR::Loop, IR::LoopExit, IR::BlockExit, IR::BlockBody then emit_loop_flow(node, lines)
          when IR::Return then emit_return(node, lines)
          when IR::Operation, IR::NilCheck then emit_operation(node, lines)
          else emit_exception(node, lines)
          end
        end

        def emit_operation(node, lines)
          if node.is_a?(IR::NilCheck)
            value = emit_value(emit_expression(node.receiver, lines), lines)
            return emit_value("Value::Bool(matches!(#{value}, Value::Nil))", lines)
          end
          operands = node.operands.map { |operand| emit_value(emit_expression(operand, lines), lines) }
          name = Rust.rust_string(node.name.to_s)
          function = operands.one? ? "unary" : "binary"
          expression = if operands.one?
                         "Runtime::#{function}(#{name}, #{operands.join(', ')})"
                       else
                         "runtime.checked_binary(#{name}, #{operands.join(', ')}, #{location(node.span)})?"
                       end
          emit_value(expression, lines)
        end

        def emit_return(node, lines)
          emit_jump(@return_label || "return", emit_expression(node.value, lines))
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
          return emit_block_body(node, lines) if node.is_a?(IR::BlockBody)

          return emit_loop(node, lines) if node.is_a?(IR::Loop)
          return emit_jump("block_exit_#{node.target}", emit_expression(node.value, lines)) if node.is_a?(IR::BlockExit)

          value = emit_expression(node.value, lines)
          if node.kind == :break
            emit_jump(@loop_labels.first, value)
          else
            emit_jump(@loop_labels.last, value)
          end
        end

        def emit_loop(node, lines)
          previous = @loop_labels
          @loop_labels = ["loop_#{@next_temp}", "iteration_#{@next_temp}"]
          @next_temp += 1
          @targets[@loop_labels.first] = [@closure_depth, :value]
          predicate = []
          condition = emit_expression(node.predicate, predicate)
          test = "Runtime::truthy(&#{condition})"
          test = "!#{test}" unless node.until_loop
          predicate << "    if #{test} { break '#{@loop_labels.first} Value::Nil; }"
          @targets[@loop_labels.last] = [@closure_depth, :next]
          body = []
          body << "    let _ = #{emit_expression(node.body, body)};"
          @targets.delete(@loop_labels.last)
          iteration = "    '#{@loop_labels.last}: {\n#{body.join("\n")}\n    };"
          parts = node.post_test ? [iteration, *predicate] : [*predicate, iteration]
          expression = "'#{@loop_labels.first}: loop {\n#{parts.join("\n")}\n    }"
          emit_value(expression, lines)
        ensure
          @loop_labels&.each { |label| @targets.delete(label) }
          @loop_labels = previous
        end
      end

      module Collections
        private

        def emit_allocation_or_call(node, lines)
          return emit_argument_copy(node, lines) if node.is_a?(IR::ArgumentCopy)
          return emit_iterator(node, lines) if node.is_a?(IR::Iterator)
          return emit_block_invocation(node, lines) if node.is_a?(IR::BlockInvocation)
          return emit_yield(node, lines) if node.is_a?(IR::YieldInvoke)

          if collection_node?(node) || node.is_a?(IR::Builtin)
            emit_collection(node, lines)
          else
            emit_object(node, lines)
          end
        end

        def collection_node?(node)
          [IR::ArrayLiteral, IR::HashLiteral, IR::ParameterArray, IR::ParameterHash].any? { |type| node.is_a?(type) }
        end

        def emit_argument_copy(node, lines)
          value = emit_expression(node.value, lines)
          emit_value("runtime.copy_argument(#{Rust.rust_string(node.kind.to_s)}, #{value})", lines)
        end

        def emit_collection(node, lines)
          return emit_container(node, lines) if collection_node?(node)
          return emit_value("{ runtime.collect_garbage(); Value::Nil }", lines) if node.family == :memory

          receiver = emit_value(emit_expression(node.receiver, lines), lines)
          arguments = node.arguments.map { |argument| emit_value(emit_expression(argument, lines), lines) }
          inputs = "#{Rust.rust_string(node.name.to_s)}, #{receiver}, vec![#{arguments.join(', ')}]"
          return emit_value("Runtime::exception_message(#{receiver})", lines) if node.family == :exception

          expression = if %i[array string io].include?(node.family)
                         "runtime.checked_#{node.family}(#{inputs}, #{location(node.span)})?"
                       else
                         "runtime.#{node.family}_operation(#{inputs})"
                       end
          emit_value(expression, lines)
        end

        def emit_container(node, lines)
          elements = node.elements.map { |element| emit_value(emit_expression(element, lines), lines) }
          hash = node.is_a?(IR::HashLiteral) || node.is_a?(IR::ParameterHash)
          target = hash ? "new_hash" : "new_array"
          elements = elements.each_slice(2).map { |key, value| "(#{key}, #{value})" } if hash
          emit_value("runtime.#{target}(vec![#{elements.join(', ')}])", lines)
        end
      end

      module Objects
        private

        def emit_object(node, lines, assignment: false)
          receiver = emit_object_receiver(node, lines)
          arguments = node.arguments.map { |argument| emit_value(emit_expression(argument, lines), lines) }
          return emit_native_argument_error(node, lines) if native_argument_error?(node)

          receiver ||= emit_value("runtime.new_object()", lines)
          return "#{receiver}.clone()" if empty_constructor?(node)

          result = emit_object_dispatch(node, receiver, arguments, lines, assignment: assignment)
          return arguments.last if assignment

          node.is_a?(IR::NewObject) ? "#{receiver}.clone()" : result
        end

        def emit_object_receiver(node, lines)
          value = emit_value(emit_expression(node.receiver, lines), lines) if node.receiver
          value if node.is_a?(IR::MethodCall)
        end

        def emit_object_dispatch(node, receiver, arguments, lines, assignment:)
          function = Rust.function(node, @functions)
          arguments = arguments.map { |value| "#{value}.clone()" } if assignment
          inputs = ["runtime", "#{receiver}.clone()", *arguments]
          frames = [location(node.span)]
          frames << location(node.span, "Class#new") if node.is_a?(IR::NewObject)
          traced_result(frames, lines) { "#{function}(#{inputs.join(', ')})?" }
        end

        def emit_native_argument_error(node, lines)
          return emit_expression(node.body.with(label: nil), lines) unless node.is_a?(IR::NewObject)

          traced_result([location(node.span)], lines) do |parts|
            emit_expression(node.body.with(label: "Class#new"), parts)
          end
        end

        def native_argument_error?(node)
          node.body.is_a?(IR::CallError) && node.body.label == :caller
        end

        def empty_constructor?(node)
          node.is_a?(IR::NewObject) && node.body.is_a?(IR::Sequence) && node.body.expressions.empty?
        end

        def emit_assembled_value(node, lines)
          node.is_a?(IR::ArgumentEvaluation) ? emit_argument_evaluation(node, lines) : emit_interpolation(node, lines)
        end

        def emit_interpolation(node, lines)
          parts = node.parts.map { |part| emit_expression(part, lines) }
          "Runtime::interpolate(vec![#{parts.join(', ')}])"
        end
      end

      class Emitter
        include ControlFlow
        include Loops
        include Collections
        include Iterators
        include Blocks
        include Exceptions
        include Objects
        include Namespaces
        include Reflection
        include SourceMap::Emission

        def initialize(functions)
          @functions = functions
          @locals = {}
          @next_temp = 0
          @closure_depth = 0
          @targets = {}
          @frame_name = "<main>"
          @block_depth = 0
          @block_environments = {}
        end

        def call(program)
          lines = ["fn program(runtime: &mut Runtime) -> Outcome {"]
          program.warnings.each { |warning| lines << "    eprintln!(\"{}\", #{Rust.rust_string(warning)});" }
          initialize_locals(program.locals, {}, lines)
          program.statements.each { |statement| emit_statement(statement, lines) }
          lines.push("    Ok(Value::Nil)", "}", "fn main() { Runtime::finish(program(&mut Runtime::new())); }",
                     "").join("\n")
        end

        def method(node, name)
          parameters = node.parameters.each_with_index.to_h { |parameter, index| [parameter, "arg_#{index}"] }
          @receiver = "receiver"
          @frame_name = method_label(node)
          @targets["return"] = [0, :return]
          signature = ["runtime: &mut Runtime", "receiver: Value", *parameters.values.map { |arg| "#{arg}: Value" }]
          lines = [SourceMap.marker(node.body.span), "fn #{name}(#{signature.join(', ')}) -> Outcome {"]
          initialize_locals(node.locals, parameters, lines)
          value = emit_expression(node.body, lines)
          lines << "    Ok(#{value})"
          lines.push("}", "    // rubast:end", "").join("\n")
        end

        private

        def emit_local_write(node, lines)
          value = emit_expression(node.value, lines)
          lines << "    #{@locals.fetch(node.name)} = #{value};"
          emit_value("#{@locals.fetch(node.name)}.clone()", lines)
        end

        def emit_mapped_expression(node, lines)
          case node
          when IR::Reflection then emit_reflection(node, lines)
          when IR::IntegerLiteral, IR::StringLiteral, IR::NilLiteral, IR::BooleanLiteral, IR::SymbolLiteral, IR::BlockValue,
               IR::IOReference
            Rust.literal(node)
          when IR::LocalRead, IR::LocalWrite, IR::InstanceRead, IR::InstanceWrite, IR::SelfRead,
               IR::Setter, IR::ConstantGet, IR::ConstantSet, IR::ClassValue, IR::NamespaceBody, IR::SourceLoad
            emit_variable(node, lines)
          when IR::SafeChomp then "Runtime::safe_chomp(#{emit_expression(node.receiver, lines)})"
          when IR::InterpolatedString, IR::ArgumentEvaluation then emit_assembled_value(node, lines)
          when IR::NewObject, IR::MethodCall, IR::ArrayLiteral, IR::HashLiteral, IR::ParameterArray, IR::ParameterHash,
               IR::Builtin, IR::Iterator, IR::BlockInvocation, IR::YieldInvoke, IR::ArgumentCopy
            emit_allocation_or_call(node, lines)
          when IR::Print, IR::Sequence, IR::Conditional, IR::Return, IR::Operation, IR::NilCheck,
               IR::Loop, IR::LoopExit, IR::BlockExit,
               IR::BlockBody, IR::Protected, IR::Raise, IR::Retry, IR::ExceptionValue, IR::CallError
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
          when IR::LocalRead then emit_value("#{@locals.fetch(node.name)}.clone()", lines)
          else emit_namespace(node, lines)
          end
        end

        def emit_value(value, lines)
          temp = "temp_#{@next_temp}"
          @next_temp += 1
          lines << "    let #{temp}: Value = #{value};"
          temp
        end

        def emit_body(node, lines)
          if node.is_a?(IR::Print)
            value = emit_value(emit_expression(node.value, lines), lines)
            lines << "    runtime.checked_io(\"kernel_p\", Value::Stream(\"stdout\"), " \
                     "vec![#{value}.clone()], #{location(node.span)})?;"
            value
          else
            node.expressions[0...-1].each { |expression| emit_statement(expression, lines) }
            node.expressions.empty? ? "Value::Nil" : emit_expression(node.expressions.last, lines)
          end
        end
      end
    end
  end
end
