# frozen_string_literal: true

require "json"

module Rubast
  module Debug
    class Ir
      def call(program, stage:)
        nodes = {}
        references = {}.compare_by_identity
        root = encode(program, nodes, references)
        JSON.pretty_generate(version: 1, stage: stage, root: root, nodes: nodes)
      end

      private

      def encode(value, nodes, references)
        return { symbol: value.to_s } if value.is_a?(Symbol)
        return value unless value.is_a?(Data) || value.is_a?(Array) || value.is_a?(Hash)
        return { "$ref" => references.fetch(value) } if references.key?(value)

        id = nodes.length.to_s
        references[value] = id
        nodes[id] = { type: value.class.name }
        nodes[id].merge!(contents(value, nodes, references))
        { "$ref" => id }
      end

      def contents(value, nodes, references)
        case value
        when Data
          { members: value.to_h.transform_values { |member| encode(member, nodes, references) } }
        when Array
          { items: value.map { |member| encode(member, nodes, references) } }
        when Hash
          { entries: value.map { |key, member| [encode(key, nodes, references), encode(member, nodes, references)] },
            default: encode(value.default, nodes, references) }
        end
      end
    end
  end
end
