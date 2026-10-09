# frozen_string_literal: true

require_relative "../system/import"

module Rubast
  class Compiler
    include Import["frontend.loader",
                   "analysis.validator", "backend.rust", "build.cargo", "build.writer", "debug.ir"]

    def call(path, release: false, directory: nil)
      cargo.call(generate(path), release: release, directory: directory)
    end

    def emit(path, directory)
      writer.call(generate(path), directory)
    end

    def build(path, output, release: false, directory: nil)
      cargo.build(generate(path), output, release: release, directory: directory)
    end

    def dump(path, stage:)
      program = loader.call(path)
      program = validator.call(program) if stage == "semantic"
      ir.call(program, stage: stage)
    end

    private

    def generate(path)
      syntax = loader.call(path)
      semantic = validator.call(syntax)
      rust.call(semantic)
    end
  end
end
