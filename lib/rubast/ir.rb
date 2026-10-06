# frozen_string_literal: true

module Rubast
  module IR
    Program = Data.define(:statements)
    Call = Data.define(:name, :receiver, :arguments, :span)
    IntegerLiteral = Data.define(:value, :span)
    Puts = Data.define(:value, :span)
  end
end
