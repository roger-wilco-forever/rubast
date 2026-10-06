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
        when Prism::IntegerNode, Prism::StringNode
          normalize_literal(node, source)
        when Prism::LocalVariableWriteNode, Prism::LocalVariableReadNode
          normalize_local(node, source)
        when Prism::InterpolatedStringNode
          IR::InterpolatedString.new(
            parts: node.parts.map { |part| normalize(part, source) }.freeze,
            span: span(node, source)
          )
        when Prism::EmbeddedStatementsNode then normalize_embedded(node, source)
        when Prism::CallNode then normalize_call(node, source)
        else unsupported(node, source)
        end
      end

      def normalize_literal(node, source)
        case node
        when Prism::IntegerNode then IR::IntegerLiteral.new(value: node.value, span: span(node, source))
        when Prism::StringNode then IR::StringLiteral.new(value: node.unescaped, span: span(node, source))
        end
      end

      def normalize_local(node, source)
        case node
        when Prism::LocalVariableWriteNode
          IR::LocalWrite.new(name: node.name, value: normalize(node.value, source), span: span(node, source))
        when Prism::LocalVariableReadNode
          IR::LocalRead.new(name: node.name, span: span(node, source))
        end
      end

      def normalize_embedded(node, source)
        statements = node.statements&.body || []
        unsupported(node, source) unless statements.one?

        normalize(statements.first, source)
      end

      def normalize_call(node, source)
        unsupported(node.block, source) if node.block

        IR::Call.new(
          name: node.name,
          receiver: node.receiver && normalize(node.receiver, source),
          arguments: (node.arguments&.arguments || []).map { |arg| normalize(arg, source) }.freeze,
          safe_navigation: node.call_operator_loc&.slice == "&.",
          span: span(node, source)
        )
      end

      def unsupported(node, source)
        raise CompilationError.new(
          code: "E_UNSUPPORTED",
          message: "unsupported Ruby construct: #{node.class.name.split('::').last}",
          span: span(node, source)
        )
      end

      def span(node, source)
        Span.new(path: source.path, line: node.location.start_line,
                 column: node.location.start_column + 1)
      end
    end
  end
end
