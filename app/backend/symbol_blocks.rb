# frozen_string_literal: true

module Rubast
  module Backend
    module SymbolBlocks
      private

      def emit_callback_or_reflection(node, lines)
        node.is_a?(IR::SymbolInvoke) ? emit_symbol_invoke(node, lines) : emit_reflection(node, lines)
      end

      def emit_symbol_invoke(node, lines)
        saved = @symbol_call_site
        site = "symbol_site_#{@next_temp}"
        @next_temp += 1
        lines << "    let #{site}: Location = runtime.take_call_site();"
        @symbol_call_site = [node.span, site]
        expression = capture_result { |parts| emit_expression(node.body, parts) }
        result = "symbol_result_#{@next_temp}"
        @next_temp += 1
        lines << "    let #{result}: Outcome = #{expression};"
        lines << "    runtime.enter(#{site});"
        emit_outcome(result, lines)
      ensure
        @symbol_call_site = saved
      end
    end
  end
end
