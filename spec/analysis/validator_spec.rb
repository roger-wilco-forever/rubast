# frozen_string_literal: true

require_relative "../../lib/rubast"
require_relative "../../system/container"

RSpec.describe Rubast::Analysis::Validator do
  it "keeps class definitions isolated between compilations through the same service" do
    validator = Rubast::Container["analysis.validator"]
    span = Rubast::Span.new(path: "example.rb", line: 1, column: 1)
    method = Rubast::IR::MethodDefinition.new(
      name: :value, parameters: [], locals: [],
      body: Rubast::IR::Sequence.new(expressions: [Rubast::IR::IntegerLiteral.new(value: 1, span: span)],
                                     result_type: nil, span: span), span: span
    )
    definition = Rubast::IR::ClassDefinition.new(name: :Example, superclass: nil, definitions: [method], span: span)
    program = Rubast::IR::Program.new(statements: [definition], locals: [], warnings: [])
    first = validator.call(program).statements.fetch(0)
    second = validator.call(program).statements.fetch(0)
    expect(first).to be_a(Rubast::IR::NamespaceBody)
    expect(second).to eq(first)
    expect(second.receiver.result_type).not_to equal(first.receiver.result_type)

    construction = Rubast::IR::Call.new(
      name: :new, receiver: Rubast::IR::ConstantRead.new(name: :Example, span: span),
      arguments: [], safe_navigation: false, span: span
    )
    expect { validator.call(Rubast::IR::Program.new(statements: [construction], locals: [], warnings: [])) }
      .to raise_error(Rubast::CompilationError, /unsupported/)
  end
end
