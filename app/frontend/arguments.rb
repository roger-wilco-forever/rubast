# frozen_string_literal: true

module Rubast
  module Frontend
    module Arguments
      private

      def normalize_method_parameters(node, source)
        return [].freeze unless node

        unsupported(node, source) if node.keyword_rest.is_a?(Prism::NoKeywordsParameterNode)
        groups = { required: node.requireds, optional: node.optionals, rest: [node.rest].compact,
                   post: node.posts, keyword: node.keywords, keyword_rest: [node.keyword_rest].compact,
                   block: [node.block].compact }
        groups.flat_map do |kind, values|
          values.map { |value| normalize_parameter(value, kind, source) }
        end.freeze
      end

      def normalize_parameter(node, kind, source)
        allowed = [Prism::RequiredParameterNode, Prism::OptionalParameterNode, Prism::RestParameterNode,
                   Prism::RequiredKeywordParameterNode, Prism::OptionalKeywordParameterNode, Prism::KeywordRestParameterNode,
                   Prism::BlockParameterNode]
        unsupported(node, source) unless allowed.any? { |type| node.is_a?(type) } && node.name
        default = node.is_a?(Prism::OptionalParameterNode) || node.is_a?(Prism::OptionalKeywordParameterNode)
        IR::Parameter.new(name: node.name, kind: kind, default: default ? normalize(node.value, source) : nil,
                          span: span(node, source))
      end

      def normalize_call_argument(node, source)
        case node
        when Prism::SplatNode
          unsupported(node, source) unless node.expression
          IR::ArgumentSplat.new(kind: :array, value: normalize(node.expression, source), span: span(node, source))
        when Prism::KeywordHashNode
          IR::Keywords.new(parts: node.elements.map { |part| normalize_keyword_part(part, source) }.freeze,
                           span: span(node, source))
        else normalize(node, source)
        end
      end

      def normalize_keyword_part(node, source)
        if node.is_a?(Prism::AssocSplatNode)
          unsupported(node, source) unless node.value
          return IR::ArgumentSplat.new(kind: :hash, value: normalize(node.value, source), span: span(node, source))
        end
        IR::ParameterHash.new(elements: normalize_pair(node, source).map { |value| normalize(value, source) }.freeze,
                              result_type: nil, span: span(node, source))
      end
    end
  end
end
