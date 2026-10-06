# frozen_string_literal: true

module Rubast
  module Frontend
    class Normalizer
      def call(ast, source)
        statements = ast.statements&.body || []
        IR::Program.new(statements: statements.map { |node| normalize(node, source) }.freeze)
      end

      private

      def normalize(node, source)
        case node
        when Prism::IntegerNode
          IR::IntegerLiteral.new(value: node.value, span: span(node, source))
        when Prism::CallNode
          if node.block
            raise CompilationError.new(
              code: "E_UNSUPPORTED",
              message: "blocks are not supported yet",
              span: span(node.block, source)
            )
          end
          IR::Call.new(
            name: node.name,
            receiver: node.receiver && normalize(node.receiver, source),
            arguments: (node.arguments&.arguments || []).map { |arg| normalize(arg, source) }.freeze,
            span: span(node, source)
          )
        else
          raise CompilationError.new(
            code: "E_UNSUPPORTED",
            message: "unsupported Ruby construct: #{node.class.name.split('::').last}",
            span: span(node, source)
          )
        end
      end

      def span(node, source)
        Span.new(path: source.path, line: node.location.start_line,
                 column: node.location.start_column + 1)
      end
    end
  end
end
