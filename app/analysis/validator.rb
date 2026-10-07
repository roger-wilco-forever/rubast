# frozen_string_literal: true

module Rubast
  module Analysis
    class Validator
      MIN_INTEGER = -(2**63)
      MAX_INTEGER = (2**63) - 1

      def call(program)
        Session.new.call(program)
      end

      class Session < Validator
        def call(program)
          @classes = {}
          locals = {}
          statements = program.statements.filter_map { |node| validate_statement(node, locals) }
          IR::Program.new(statements: statements.freeze)
        end

        private

        def validate_statement(node, locals)
          case node
          when IR::ClassDefinition then validate_class(node)
          when IR::LocalWrite
            value = validate_expression(node.value, locals)
            locals[node.name] = type_of(value, locals)
            IR::LocalWrite.new(name: node.name, value: value, span: node.span)
          when IR::Call
            return validate_puts(node, locals) if node.name == :puts && node.receiver.nil?

            value = validate_call(node, locals)
            unsupported(node) unless value.is_a?(IR::MethodCall) || value.is_a?(IR::NewObject)
            value
          else
            unsupported(node)
          end
        end

        def validate_puts(node, locals)
          unless node.receiver.nil? && !node.safe_navigation && node.name == :puts && node.arguments.one?
            unsupported(node)
          end

          IR::Puts.new(value: validate_scalar(node.arguments.first, locals), span: node.span)
        end

        def validate_class(node)
          unsupported(node) if @classes.key?(node.name) || Object.const_defined?(node.name, false)
          methods = {}
          node.definitions.each do |method|
            unsupported(method) if methods.key?(method.name) || method.name == :initialize
            parameters = method.parameters.to_h { |name| [name, :scalar] }
            body = validate_scalar(method.body, parameters)
            methods[method.name] = method.with(body: body)
          end
          @classes[node.name] = methods.freeze
          nil
        end

        def validate_scalar(node, locals)
          value = validate_expression(node, locals)
          unsupported(node) if type_of(value, locals).is_a?(Array)
          value
        end

        def validate_expression(node, locals)
          case node
          when IR::IntegerLiteral then validate_integer(node)
          when IR::StringLiteral then validate_string(node)
          when IR::LocalRead then locals.key?(node.name) ? node : unsupported(node)
          when IR::InterpolatedString
            parts = node.parts.map { |part| validate_scalar(part, locals) }
            IR::InterpolatedString.new(parts: parts.freeze, span: node.span)
          when IR::Call then validate_call(node, locals)
          else unsupported(node)
          end
        end

        def validate_call(node, locals)
          return IR::GetLine.new(span: node.span) if gets_call?(node)
          return validate_safe_chomp(node, locals) if safe_chomp_call?(node)
          return validate_new(node) if node.receiver.is_a?(IR::ConstantRead)
          return validate_method_call(node, locals) if node.receiver && !node.safe_navigation

          unsupported(node)
        end

        def validate_new(node)
          name = node.receiver.name
          unless @classes.key?(name) && node.name == :new && node.arguments.empty? && !node.safe_navigation
            unsupported(node)
          end
          IR::NewObject.new(class_name: name, span: node.span)
        end

        def validate_method_call(node, locals)
          receiver = validate_expression(node.receiver, locals)
          type = type_of(receiver, locals)
          unsupported(node) unless type.is_a?(Array)
          method = @classes.fetch(type.last)[node.name]
          unsupported(node) unless method && node.arguments.length == method.parameters.length
          arguments = node.arguments.map { |argument| validate_scalar(argument, locals) }
          parameters = argument_types(method, arguments, locals)
          IR::MethodCall.new(receiver: receiver, arguments: arguments.freeze, parameters: method.parameters,
                             body: method.body, result_type: type_of(method.body, parameters), span: node.span)
        end

        def validate_safe_chomp(node, locals)
          receiver = validate_expression(node.receiver, locals)
          return IR::SafeChomp.new(receiver: receiver, span: node.span) if string_like?(receiver, locals)

          unsupported(node)
        end
      end

      private

      def type_of(node, locals)
        case node
        when IR::IntegerLiteral then :integer
        when IR::StringLiteral, IR::InterpolatedString then :string
        when IR::GetLine, IR::SafeChomp then :string_or_nil
        when IR::LocalRead then locals.fetch(node.name)
        when IR::NewObject then [:object, node.class_name]
        when IR::MethodCall then node.result_type
        end
      end

      def gets_call?(node)
        node.receiver.nil? && !node.safe_navigation && node.name == :gets && node.arguments.empty?
      end

      def safe_chomp_call?(node)
        node.receiver && node.safe_navigation && node.name == :chomp && node.arguments.empty?
      end

      def string_like?(node, locals)
        case type_of(node, locals)
        when :string, :string_or_nil then true
        else false
        end
      end

      def argument_types(method, arguments, locals)
        method.parameters.zip(arguments.map { |argument| type_of(argument, locals) }).to_h
      end

      def validate_integer(node)
        return node if (MIN_INTEGER..MAX_INTEGER).cover?(node.value)

        raise CompilationError.new(
          code: "E_INTEGER_RANGE",
          message: "integer literal exceeds the current 64-bit range",
          span: node.span
        )
      end

      def validate_string(node)
        return node if node.value.encoding == Encoding::UTF_8 && node.value.valid_encoding?

        raise CompilationError.new(
          code: "E_ENCODING",
          message: "only UTF-8 string literals are supported",
          span: node.span
        )
      end

      def unsupported(node)
        raise CompilationError.new(
          code: "E_UNSUPPORTED",
          message: "unsupported Ruby expression: #{node.class.name.split('::').last}",
          span: node.span
        )
      end
    end
  end
end
