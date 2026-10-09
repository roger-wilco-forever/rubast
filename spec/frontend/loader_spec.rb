# frozen_string_literal: true

require "tmpdir"
require_relative "../../lib/rubast"
require_relative "../../system/container"

RSpec.describe Rubast::Frontend::Loader do
  it "keeps loaded-file state per compilation through the same service" do
    Dir.mktmpdir("rubast-loader-") do |directory|
      dependency = File.join(directory, "settings.rb")
      entry = File.join(directory, "main.rb")
      File.write(dependency, "LIMIT = 1\n")
      File.write(entry, "require_relative 'settings'\nrequire_relative 'settings.rb'\n")
      loader = Rubast::Container["frontend.loader"]
      first = loader.call(entry)
      File.write(dependency, "LIMIT = 2\n")
      second = loader.call(entry)
      expect(first.statements.first).to be_a(Rubast::IR::SourceLoad)
      expect(second.statements.first).to be_a(Rubast::IR::SourceLoad)
      expect(first.statements.last.value).to be(false)
      expect(second.statements.last.value).to be(false)
      expect(second.statements.first.program.statements.first.value.value).to eq(2)
    end
  end
end
