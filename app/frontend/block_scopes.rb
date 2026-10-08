# frozen_string_literal: true

module Rubast
  module Frontend
    module BlockScopes
      private

      def local_name(node)
        @scopes.fetch(-1 - node.depth).fetch(:names).fetch(node.name)
      end

      def block_scope?
        @scopes.last.fetch(:block)
      end

      def in_scope(names, block: false)
        previous = @scopes
        @scope_serial += 1
        map = names.to_h { |name| [name, block ? [@scope_serial, name].freeze : name] }
        scope = { names: map, block: block }
        @scopes = block ? [*previous, scope] : [scope]
        yield map.values.freeze
      ensure
        @scopes = previous
      end

      def normalize_block_call(node, source)
        block = node.block
        unsupported(block, source) unless block.is_a?(Prism::BlockNode)
        parameters = block.parameters
        unsupported(parameters, source) if parameters && !parameters.is_a?(Prism::BlockParametersNode)
        required = normalize_parameters(parameters&.parameters, source)
        unsupported(block, source) if required.length > 1
        invocation = normalize_plain_call(node, source)
        value = in_scope(block.locals, block: true) do |locals|
          IR::Block.new(parameters: required.map do |parameter|
            @scopes.last.fetch(:names).fetch(parameter.name)
          end.freeze,
                        locals: locals, body: normalize_block_body(block, source), span: span(block, source))
        end
        IR::BlockCall.new(call: invocation, block: value, result_type: nil, span: span(node, source))
      end

      def normalize_block_body(node, source)
        unsupported(node.body, source) if node.body && !node.body.is_a?(Prism::StatementsNode)
        normalize_sequence(node.body, node, source)
      end
    end
  end
end
