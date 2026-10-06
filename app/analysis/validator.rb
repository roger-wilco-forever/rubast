# frozen_string_literal: true

module Rubast
  module Analysis
    class Validator
      MIN_INTEGER = -(2**63)
      MAX_INTEGER = (2**63) - 1

      def call(program)
        IR::Program.new(statements: program.statements.map { |node| validate(node) }.freeze)
      end

      private

      def validate(node)
        if node.is_a?(IR::Call) && node.receiver.nil? && node.name == :puts &&
           node.arguments.one? && node.arguments.first.is_a?(IR::IntegerLiteral)
          integer = node.arguments.first.value
          unless (MIN_INTEGER..MAX_INTEGER).cover?(integer)
            raise CompilationError.new(
              code: "E_INTEGER_RANGE",
              message: "integer literal exceeds the current 64-bit range",
              span: node.arguments.first.span
            )
          end
          return IR::Puts.new(value: integer, span: node.span)
        end

        raise CompilationError.new(
          code: "E_UNSUPPORTED",
          message: "only puts with one integer literal is supported",
          span: node.span
        )
      end
    end
  end
end
