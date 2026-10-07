# frozen_string_literal: true

require_relative "../system/import"

module Rubast
  class Compiler
    include Import["source.reader", "frontend.parser", "frontend.normalizer",
                   "analysis.validator", "backend.rust", "build.cargo", "build.writer"]

    def call(path)
      cargo.call(generate(path))
    end

    def emit(path, directory)
      writer.call(generate(path), directory)
    end

    private

    def generate(path)
      source = reader.call(path)
      ast = parser.call(source)
      syntax = normalizer.call(ast, source)
      semantic = validator.call(syntax)
      rust.call(semantic)
    end
  end
end
