# frozen_string_literal: true

module Rubast
  module Frontend
    module Exceptions
      private

      def normalize_exception(node, source)
        case node
        when Prism::BeginNode then normalize_begin(node, source)
        when Prism::RetryNode then IR::Retry.new(span: span(node, source))
        else normalize_rescue_modifier(node, source)
        end
      end

      def normalize_rescue_modifier(node, source)
        body = IR::Sequence.new(expressions: [normalize(node.expression, source)].freeze,
                                result_type: nil, span: span(node, source))
        recovery = IR::Sequence.new(expressions: [normalize(node.rescue_expression, source)].freeze,
                                    result_type: nil, span: span(node, source))
        handler = IR::Rescue.new(classes: [].freeze, reference: nil, body: recovery, span: span(node, source))
        IR::Protected.new(body: body, handlers: [handler].freeze, otherwise: nil, ensure_body: nil,
                          result_type: nil, span: span(node, source))
      end

      def normalize_begin(node, source)
        body = normalize_sequence(node.statements, node, source)
        return body unless node.rescue_clause || node.else_clause || node.ensure_clause

        IR::Protected.new(body: body, handlers: normalize_rescues(node.rescue_clause, source),
                          otherwise: normalize_clause(node.else_clause, source),
                          ensure_body: normalize_clause(node.ensure_clause, source),
                          result_type: nil, span: span(node, source))
      end

      def normalize_clause(node, source)
        node && normalize_sequence(node.statements, node, source)
      end

      def normalize_rescues(node, source)
        handlers = []
        while node
          reference = node.reference
          unsupported(reference, source) if reference && !reference.is_a?(Prism::LocalVariableTargetNode)
          handlers << IR::Rescue.new(classes: node.exceptions.map { |value| normalize(value, source) }.freeze,
                                     reference: reference && local_name(reference),
                                     body: normalize_clause(node, source),
                                     span: span(node, source))
          node = node.subsequent
        end
        handlers.freeze
      end
    end
  end
end
