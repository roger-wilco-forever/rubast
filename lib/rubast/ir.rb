# frozen_string_literal: true

module Rubast
  module IR
    Program = Data.define(:statements)
    ClassDefinition = Data.define(:name, :definitions, :span)
    MethodDefinition = Data.define(:name, :parameters, :locals, :body, :span)
    Sequence = Data.define(:expressions, :result_type, :span)
    NilLiteral = Data.define(:span)
    ConstantRead = Data.define(:name, :span)
    ObjectType = Data.define(:class_name, :fields)
    NewObject = Data.define(:class_name, :arguments, :parameters, :locals, :body, :result_type, :span)
    InstanceRead = Data.define(:name, :result_type, :span)
    InstanceWrite = Data.define(:name, :value, :span)
    MethodCall = Data.define(:receiver, :arguments, :parameters, :locals, :body, :result_type, :span)
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
