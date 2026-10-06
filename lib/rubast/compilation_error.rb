# frozen_string_literal: true

module Rubast
  class CompilationError < StandardError
    attr_reader :code, :span, :detail

    def initialize(code:, message:, span:)
      @code = code
      @span = span
      @detail = message
      super(message)
    end

    def to_s
      "#{span.path}:#{span.line}:#{span.column}: #{code}: #{detail}"
    end
  end
end
