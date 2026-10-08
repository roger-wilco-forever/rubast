# frozen_string_literal: true

module Rubast
  module Frontend
    module BlockScopes
      private

      def local_name(node)
        @scopes.fetch(-1 - node.depth).fetch(:names).fetch(node.name)
      end

      def in_scope(names, block: false)
        previous = @scopes
        @scope_serial += 1
        map = names.to_h { |name| [name, block ? [@scope_serial, name].freeze : name] }
        scope = { names: map }
        @scopes = block ? [*previous, scope] : [scope]
        yield map.values.freeze
      ensure
        @scopes = previous
      end

      def normalize_yield(node, source)
        IR::Yield.new(arguments: (node.arguments&.arguments || []).map do |arg|
          normalize_call_argument(arg, source)
        end.freeze,
                      result_type: nil, span: span(node, source))
      end

      def normalize_block_call(node, source)
        if node.block.is_a?(Prism::BlockArgumentNode)
          unsupported(node.block, source) unless node.block.expression
          return IR::BlockPass.new(call: normalize_plain_call(node, source),
                                   value: normalize(node.block.expression, source),
                                   result_type: nil, span: span(node, source))
        end
        IR::BlockCall.new(call: normalize_plain_call(node, source), block: normalize_literal_block(node.block, source),
                          result_type: nil, span: span(node, source))
      end

      def normalize_literal_block(block, source)
        unsupported(block, source) unless block.is_a?(Prism::BlockNode)
        parameters = block.parameters
        unsupported(parameters, source) if parameters && !parameters.is_a?(Prism::BlockParametersNode)
        required = normalize_parameters(parameters&.parameters, source)
        unsupported(block, source) if required.length > 1
        in_scope(block.locals, block: true) do |locals|
          IR::Block.new(parameters: required.map do |parameter|
            @scopes.last.fetch(:names).fetch(parameter.name)
          end.freeze,
                        locals: locals, body: normalize_block_body(block, source), span: span(block, source))
        end
      end

      def normalize_block_body(node, source)
        return normalize_begin(node.body, source) if node.body.is_a?(Prism::BeginNode)

        unsupported(node.body, source) if node.body && !node.body.is_a?(Prism::StatementsNode)
        normalize_sequence(node.body, node, source)
      end
    end
  end
end
