# frozen_string_literal: true

require_relative "../system/import"

module Rubast
  class Compiler
    include Import["frontend.loader",
                   "analysis.validator", "backend.rust", "build.cargo", "build.writer"]

    def call(path)
      cargo.call(generate(path))
    end

    def emit(path, directory)
      writer.call(generate(path), directory)
    end

    private

    def generate(path)
      syntax = loader.call(path)
      semantic = validator.call(syntax)
      rust.call(semantic)
    end
  end
end
