# frozen_string_literal: true

require_relative "../system/import"

module Rubast
  class Compiler
    include Import["source.reader", "frontend.parser", "frontend.normalizer",
                   "analysis.validator", "backend.rust", "build.cargo"]

    def call(path)
      source = reader.call(path)
      ast = parser.call(source)
      syntax = normalizer.call(ast, source)
      semantic = validator.call(syntax)
      project = rust.call(semantic)
      cargo.call(project)
    end
  end
end
