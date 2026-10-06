# frozen_string_literal: true

require_relative "../../lib/rubast"
require_relative "../../system/container"

RSpec.describe Rubast::Container do
  it "resolves every compiler stage through dry-system" do
    expect(described_class["compiler"]).to be_a(Rubast::Compiler)
    expect(described_class["source.reader"]).to be_a(Rubast::Source::Reader)
    expect(described_class["frontend.parser"]).to be_a(Rubast::Frontend::Parser)
    expect(described_class["frontend.normalizer"]).to be_a(Rubast::Frontend::Normalizer)
    expect(described_class["analysis.validator"]).to be_a(Rubast::Analysis::Validator)
    expect(described_class["backend.rust"]).to be_a(Rubast::Backend::Rust)
    expect(described_class["build.cargo"]).to be_a(Rubast::Build::Cargo)
  end
end
