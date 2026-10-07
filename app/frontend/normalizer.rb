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
        when Prism::ClassNode then normalize_class(node, source)
        when Prism::ConstantReadNode, Prism::IntegerNode, Prism::StringNode, Prism::NilNode
          normalize_literal(node, source)
        when Prism::LocalVariableWriteNode, Prism::LocalVariableReadNode,
             Prism::InstanceVariableWriteNode, Prism::InstanceVariableReadNode
          normalize_variable(node, source)
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
        when Prism::NilNode then IR::NilLiteral.new(span: span(node, source))
        when Prism::ConstantReadNode then IR::ConstantRead.new(name: node.name, span: span(node, source))
        when Prism::IntegerNode then IR::IntegerLiteral.new(value: node.value, span: span(node, source))
        when Prism::StringNode then IR::StringLiteral.new(value: node.unescaped, span: span(node, source))
        end
      end

      def normalize_class(node, source)
        unsupported(node, source) if node.superclass || !node.constant_path.is_a?(Prism::ConstantReadNode)
        methods = node.body&.body || []
        unsupported(node, source) if methods.empty?

        IR::ClassDefinition.new(name: node.name,
                                definitions: methods.map { |method| normalize_method(method, source) }.freeze,
                                span: span(node, source))
      end

      def normalize_method(node, source)
        unsupported(node, source) unless node.is_a?(Prism::DefNode) && node.receiver.nil?
        requireds = normalize_parameters(node.parameters, source)
        IR::MethodDefinition.new(name: node.name, parameters: requireds.map(&:name).freeze,
                                 locals: node.locals.freeze, body: normalize_method_body(node, source),
                                 span: span(node, source))
      end

      def normalize_method_body(node, source)
        unsupported(node.body, source) if node.body && !node.body.is_a?(Prism::StatementsNode)
        body = node.body&.body || []
        IR::Sequence.new(expressions: body.map { |expression| normalize(expression, source) }.freeze,
                         result_type: nil, span: span(node, source))
      end

      def normalize_parameters(parameters, source)
        return [] unless parameters

        extras = [parameters.optionals, parameters.rest, parameters.posts, parameters.keywords,
                  parameters.keyword_rest, parameters.block].flatten.compact
        unsupported(parameters, source) unless extras.empty?
        parameters.requireds.each do |parameter|
          unsupported(parameter, source) unless parameter.is_a?(Prism::RequiredParameterNode)
        end
      end

      def normalize_variable(node, source)
        case node
        when Prism::InstanceVariableWriteNode
          IR::InstanceWrite.new(name: node.name, value: normalize(node.value, source), span: span(node, source))
        when Prism::InstanceVariableReadNode
          IR::InstanceRead.new(name: node.name, result_type: nil, span: span(node, source))
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
