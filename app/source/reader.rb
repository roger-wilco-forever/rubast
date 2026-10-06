# frozen_string_literal: true

module Rubast
  module Source
    class Reader
      def call(path)
        absolute_path = File.expand_path(path)
        Rubast::SourceFile.new(path: absolute_path, bytes: File.binread(absolute_path))
      rescue SystemCallError => error
        raise CompilationError.new(
          code: "E_SOURCE",
          message: error.message,
          span: Span.new(path: absolute_path, line: 1, column: 1)
        )
      end
    end
  end
end
