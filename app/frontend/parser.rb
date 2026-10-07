# frozen_string_literal: true

require "prism"

module Rubast
  module Frontend
    class Parser
      def call(source)
        result = Prism.parse(source.bytes, filepath: source.path)
        return result if result.errors.empty?

        error = result.errors.first
        raise CompilationError.new(
          code: "E_PARSE",
          message: error.message,
          span: Span.new(
            path: source.path,
            line: error.location.start_line,
            column: error.location.start_column + 1
          )
        )
      end
    end
  end
end
