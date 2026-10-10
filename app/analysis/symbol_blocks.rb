# frozen_string_literal: true

module Rubast
  module Analysis
    module SymbolBlocks
      private

      def symbol_block(value)
        validate_literal(value)
        name = [:symbol_receiver].freeze
        body = IR::SymbolCall.new(name: value.value.to_sym, receiver: IR::LocalRead.new(name: name, span: value.span),
                                  span: value.span)
        IR::Block.new(parameters: [name].freeze, locals: [name].freeze, body: body, span: value.span)
      end

      def validate_symbol_pass(node, locals)
        literal = IR::BlockCall.new(call: node.call, block: symbol_block(node.value),
                                    result_type: nil, span: node.span)
        validate_block_call(literal, locals)
      end

      def validate_symbol_call(node, locals)
        call = IR::Call.new(name: node.name, receiver: node.receiver, arguments: [].freeze,
                            safe_navigation: false, visibility: :public, span: node.span)
        body = validate_method_call(call, locals)
        IR::SymbolInvoke.new(body: body, result_type: type_of(body, locals), span: node.span)
      end

      def symbol_context?(context)
        context && context.fetch(:block).body.is_a?(IR::SymbolCall)
      end

      def check_symbol_arguments(context, pack, node)
        unsupported(node) if symbol_context?(context) && (pack[:positional].length != 1 || !pack[:keywords].empty?)
      end

      def validate_block_argument(node, locals)
        node.value.is_a?(IR::SymbolLiteral) ? validate_symbol_pass(node, locals) : validate_block_pass(node, locals)
      end
    end
  end
end
