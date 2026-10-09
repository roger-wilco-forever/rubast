# frozen_string_literal: true

module Rubast
  module IR
    Program = Data.define(:statements, :locals, :warnings, :symbols) do
      def initialize(symbols: [], **attributes) = super
    end
    Call = Data.define(:name, :receiver, :arguments, :safe_navigation, :span, :visibility) do
      def initialize(visibility: nil, **attributes) = super
    end
    SymbolLiteral = Data.define(:value, :span)
    Reflection = Data.define(:name, :body, :signature, :result_type, :span)
  end
end
