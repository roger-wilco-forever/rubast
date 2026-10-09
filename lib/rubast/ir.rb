# frozen_string_literal: true

module Rubast
  module IR
    Program = Data.define(:statements, :locals, :warnings)
    SourceLoad = Data.define(:program, :name, :frames, :result_type, :span)
    ClassDefinition = Data.define(:name, :superclass, :definitions, :span, :kind, :locals) do
      def initialize(name:, superclass:, definitions:, span:, kind: :class, locals: [])
        super
      end
    end
    MethodOwner = Data.define(:key, :index)
    SingletonClass = Data.define(:name)
    SingletonBody = Data.define(:definitions, :span)
    ConstantPath = Data.define(:parts, :absolute, :span)
    ConstantWrite = Data.define(:target, :value, :span)
    ConstantGet = Data.define(:name, :result_type, :span)
    ConstantSet = Data.define(:name, :value, :result_type, :span)
    ClassValue = Data.define(:result_type, :span)
    NamespaceBody = Data.define(:name, :kind, :receiver, :locals, :body, :result_type, :span)
    ArgumentSplat = Data.define(:kind, :value, :span)
    Keywords = Data.define(:parts, :span)
    ArgumentCopy = Data.define(:kind, :value, :result_type, :span)
    ParameterArray = Data.define(:elements, :result_type, :span)
    ParameterHash = Data.define(:elements, :result_type, :span)
    Parameter = Data.define(:name, :kind, :default, :span)
    MethodDefinition = Data.define(:name, :parameters, :signature, :locals, :body, :span, :singleton, :native) do
      def initialize(name:, parameters:, locals:, body:, span:, signature: nil, singleton: false, native: false)
        signature ||= parameters.map do |parameter|
          Parameter.new(name: parameter, kind: :required, default: nil, span: span)
        end.freeze
        super
      end
    end
    Sequence = Data.define(:expressions, :result_type, :span)
    BooleanLiteral = Data.define(:value, :span)
    IntegerType = Data.define(:minimum, :maximum)
    SymbolType = Data.define(:name)
    HashShape = Data.define(:keys)
    UnionType = Data.define(:types)
    Operation = Data.define(:name, :operands, :result_type, :span)
    Conditional = Data.define(:predicate, :consequent, :alternative, :result_type, :span)
    Return = Data.define(:value, :span)
    Protected = Data.define(:body, :handlers, :otherwise, :ensure_body, :result_type, :span)
    Rescue = Data.define(:classes, :reference, :body, :span)
    CallError = Data.define(:class_name, :message, :label, :result_type, :span)
    Raise = Data.define(:arguments, :result_type, :span)
    Retry = Data.define(:span)
    ExceptionType = Data.define(:class_name)
    ExceptionValue = Data.define(:class_name, :message, :result_type, :span)
    Loop = Data.define(:predicate, :body, :until_loop, :post_test, :result_type, :span)
    BlockBody = Data.define(:exit_id, :body, :result_type, :span)
    BlockExit = Data.define(:target, :value, :span)
    LoopExit = Data.define(:kind, :value, :span)
    NilLiteral = Data.define(:span)
    ConstantRead = Data.define(:name, :span)
    ObjectType = Data.define(:class_name, :fields)
    # class_name is the resolved initializer owner; result_type retains the allocated class.
    NewObject = Data.define(:class_name, :arguments, :parameters, :locals, :body, :result_type, :span, :receiver) do
      def initialize(class_name:, arguments:, parameters:, locals:, body:, result_type:, span:, receiver: nil)
        super
      end
    end
    SelfRead = Data.define(:result_type, :span)
    InstanceRead = Data.define(:name, :result_type, :span)
    InstanceWrite = Data.define(:name, :value, :span)
    MethodCall = Data.define(:class_name, :name, :receiver, :arguments, :parameters, :locals, :body, :result_type,
                             :span)
    Yield = Data.define(:arguments, :result_type, :span)
    YieldInvoke = Data.define(:arguments, :parameters, :locals, :body, :result_type, :block_id, :span)
    BlockInvocation = Data.define(:exit_id, :block_id, :invocation, :result_type, :span)
    BlockType = Data.define(:id)
    BlockValue = Data.define(:id, :span)
    BlockPass = Data.define(:call, :value, :result_type, :span)
    ArgumentEvaluation = Data.define(:arguments, :names, :body, :result_type, :span)
    Block = Data.define(:parameters, :locals, :body, :span)
    BlockCall = Data.define(:call, :block, :result_type, :span)
    Iterator = Data.define(:exit_id, :name, :family, :receiver, :parameters, :locals, :steps, :result_type, :span)
    BlockStep = Data.define(:index, :body, :span)
    Call = Data.define(:name, :receiver, :arguments, :safe_navigation, :span)
    Super = Data.define(:arguments, :forward_arguments, :block, :span) do
      def initialize(arguments:, forward_arguments:, span:, block: nil)
        super
      end
    end
    IntegerLiteral = Data.define(:value, :span)
    StringLiteral = Data.define(:value, :frozen, :span)
    SymbolLiteral = Data.define(:value, :span)
    HashLiteral = Data.define(:elements, :result_type, :span)
    ArrayLiteral = Data.define(:elements, :result_type, :span)
    Setter = Data.define(:call, :result_type, :span)
    IndexWrite = Data.define(:receiver, :index, :value, :result_type, :span)
    Builtin = Data.define(:family, :name, :receiver, :arguments, :result_type, :span)
    InterpolatedString = Data.define(:parts, :span)
    LocalWrite = Data.define(:name, :value, :span)
    LocalRead = Data.define(:name, :span)
    GlobalRead = Data.define(:name, :span)
    IOReference = Data.define(:result_type, :span)
    SafeChomp = Data.define(:receiver, :span)
    NilCheck = Data.define(:receiver, :known, :result_type, :span)
    Print = Data.define(:value, :result_type, :span)
  end
end
