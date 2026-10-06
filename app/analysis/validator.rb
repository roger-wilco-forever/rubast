# frozen_string_literal: true

module Rubast
  module Analysis
    class Validator
      MIN_INTEGER = -(2**63)
      MAX_INTEGER = (2**63) - 1

      def call(program)
        locals = {}
        statements = program.statements.map { |node| validate_statement(node, locals) }
        IR::Program.new(statements: statements.freeze)
      end

      private

      def validate_statement(node, locals)
        case node
        when IR::LocalWrite
          value = validate_expression(node.value, locals)
          locals[node.name] = type_of(value, locals)
          IR::LocalWrite.new(name: node.name, value: value, span: node.span)
        when IR::Call
          validate_puts(node, locals)
        else
          unsupported(node)
        end
      end

      def validate_puts(node, locals)
        unless node.receiver.nil? && !node.safe_navigation && node.name == :puts && node.arguments.one?
          unsupported(node)
        end

        IR::Puts.new(value: validate_expression(node.arguments.first, locals), span: node.span)
      end

      def validate_expression(node, locals)
        case node
        when IR::IntegerLiteral then validate_integer(node)
        when IR::StringLiteral then validate_string(node)
        when IR::LocalRead then locals.key?(node.name) ? node : unsupported(node)
        when IR::InterpolatedString
          parts = node.parts.map { |part| validate_expression(part, locals) }
          IR::InterpolatedString.new(parts: parts.freeze, span: node.span)
        when IR::Call then validate_call(node, locals)
        else unsupported(node)
        end
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

      def validate_call(node, locals)
        return IR::GetLine.new(span: node.span) if gets_call?(node)
        return validate_safe_chomp(node, locals) if safe_chomp_call?(node)

        unsupported(node)
      end

      def gets_call?(node)
        node.receiver.nil? && !node.safe_navigation && node.name == :gets && node.arguments.empty?
      end

      def safe_chomp_call?(node)
        node.receiver && node.safe_navigation && node.name == :chomp && node.arguments.empty?
      end

      def validate_safe_chomp(node, locals)
        receiver = validate_expression(node.receiver, locals)
        return IR::SafeChomp.new(receiver: receiver, span: node.span) if string_like?(receiver, locals)

        unsupported(node)
      end

      def string_like?(node, locals)
        case type_of(node, locals)
        when :string, :string_or_nil then true
        else false
        end
      end

      def type_of(node, locals)
        case node
        when IR::IntegerLiteral then :integer
        when IR::StringLiteral, IR::InterpolatedString then :string
        when IR::GetLine, IR::SafeChomp then :string_or_nil
        when IR::LocalRead then locals.fetch(node.name)
        end
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
