# frozen_string_literal: true

require "json"

module Rubast
  module Backend
    class SourceMap
      module Emission
        private

        def emit_statement(node, lines)
          lines << SourceMap.marker(node.span)
          lines << "    let _ = #{emit_expression(node, lines)};"
          lines << "    // rubast:end"
        end

        def emit_expression(node, lines)
          lines << SourceMap.marker(node.span)
          value = emit_mapped_expression(node, lines)
          lines << "    // rubast:end"
          value
        end
      end

      def self.call(source)
        stack = []
        locations = {}
        source.each_line.with_index(1) do |line, number|
          if (marker = line.match(%r{^\s*// rubast:begin (.+)$}))
            stack << JSON.parse(marker[1])
          elsif line.match?(%r{^\s*// rubast:end\s*$})
            stack.pop
          elsif stack.any?
            locations[number.to_s] = stack.last
          end
        end
        JSON.pretty_generate(version: 1, files: { "src/main.rs" => locations })
      end

      def self.marker(span)
        "    // rubast:begin #{JSON.generate(path: span.path, line: span.line, column: span.column)}"
      end
    end
  end
end
