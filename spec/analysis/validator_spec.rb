# frozen_string_literal: true

require_relative "../../lib/rubast"
require_relative "../../system/container"

RSpec.describe Rubast::Analysis::Validator do
  it "keeps class definitions isolated between compilations through the same service" do
    validator = Rubast::Container["analysis.validator"]
    span = Rubast::Span.new(path: "example.rb", line: 1, column: 1)
    method = Rubast::IR::MethodDefinition.new(
      name: :value, parameters: [], body: Rubast::IR::IntegerLiteral.new(value: 1, span: span), span: span
    )
    definition = Rubast::IR::ClassDefinition.new(name: :Example, definitions: [method], span: span)
    program = Rubast::IR::Program.new(statements: [definition])
    expect(validator.call(program).statements).to eq([])
    expect(validator.call(program).statements).to eq([])

    construction = Rubast::IR::Call.new(
      name: :new, receiver: Rubast::IR::ConstantRead.new(name: :Example, span: span),
      arguments: [], safe_navigation: false, span: span
    )
    expect { validator.call(Rubast::IR::Program.new(statements: [construction])) }
      .to raise_error(Rubast::CompilationError, /unsupported/)
  end
end
