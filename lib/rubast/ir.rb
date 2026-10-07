# frozen_string_literal: true

module Rubast
  module IR
    Program = Data.define(:statements, :locals, :warnings)
    ClassDefinition = Data.define(:name, :superclass, :definitions, :span)
    MethodDefinition = Data.define(:name, :parameters, :locals, :body, :span)
    Sequence = Data.define(:expressions, :result_type, :span)
    BooleanLiteral = Data.define(:value, :span)
    IntegerType = Data.define(:minimum, :maximum)
    UnionType = Data.define(:types)
    Operation = Data.define(:name, :operands, :result_type, :span)
    Conditional = Data.define(:predicate, :consequent, :alternative, :result_type, :span)
    Return = Data.define(:value, :span)
    NilLiteral = Data.define(:span)
    ConstantRead = Data.define(:name, :span)
    ObjectType = Data.define(:class_name, :fields)
    NewObject = Data.define(:class_name, :arguments, :parameters, :locals, :body, :result_type, :span)
    SelfRead = Data.define(:result_type, :span)
    InstanceRead = Data.define(:name, :result_type, :span)
    InstanceWrite = Data.define(:name, :value, :span)
    MethodCall = Data.define(:class_name, :name, :receiver, :arguments, :parameters, :locals, :body, :result_type,
                             :span)
    Call = Data.define(:name, :receiver, :arguments, :safe_navigation, :span)
    Super = Data.define(:arguments, :forward_arguments, :span)
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
