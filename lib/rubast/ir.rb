# frozen_string_literal: true

module Rubast
  module IR
    Program = Data.define(:statements)
    Call = Data.define(:name, :receiver, :arguments, :safe_navigation, :span)
    IntegerLiteral = Data.define(:value, :span)
    StringLiteral = Data.define(:value, :span)
    InterpolatedString = Data.define(:parts, :span)
    LocalWrite = Data.define(:name, :value, :span)
    LocalRead = Data.define(:name, :span)
    GetLine = Data.define(:span)
    SafeChomp = Data.define(:receiver, :span)
    Puts = Data.define(:value, :span)
  end
end
