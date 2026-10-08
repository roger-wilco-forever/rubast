# frozen_string_literal: true

module Rubast
  Span = Data.define(:path, :line, :column, :highlight) do
    def initialize(path:, line:, column:, highlight: "")
      super
    end
  end
end
