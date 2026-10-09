# frozen_string_literal: true

require "tmpdir"
require_relative "../../lib/rubast"
require_relative "../../system/container"

module BuildDiagnosticsFixture
  def broken_project(directory)
    entry = File.join(directory, "entry.rb")
    dependency = File.join(directory, "dependency.rb")
    File.write(entry, "require_relative 'dependency'\nCalculator.new.label\n")
    File.write(dependency, "class Calculator\n  def label\n    value = 'marker'\n    puts value\n  end\nend\n")
    syntax = Rubast::Container["frontend.loader"].call(entry)
    semantic = Rubast::Container["analysis.validator"].call(syntax)
    project = Rubast::Container["backend.rust"].call(semantic)
    source = project.files.fetch("src/main.rs").sub("runtime.checked_io", "runtime.invalid_method")
    [dependency, project.with(files: project.files.merge("src/main.rs" => source))]
  end
end

RSpec.describe Rubast::Build::Cargo do
  include BuildDiagnosticsFixture

  it "maps a real Rust compiler error to a dependency and retains its failing project" do
    Dir.mktmpdir("rubast-diagnostics-") do |directory|
      dependency, project = broken_project(directory)
      destination = File.join(directory, "failing project")
      binary = File.join(directory, "binary")
      expect do
        described_class.new.build(project, binary, directory: destination)
      end.to raise_error(Rubast::CompilationError) { |error|
        expect(error.code).to eq("E_BUILD")
        expect(error.span.path).to eq(dependency)
        expect(error.span.line).to eq(4)
        expect(error.span.column).to eq(5)
        expect(error.detail).to include("invalid_method", "Generated project retained at #{destination}")
      }
      expect(File.exist?(binary)).to be(false)
      expect(File.read(File.join(destination, "src/main.rs"))).to include("runtime.invalid_method")
      stdout, stderr, status = Open3.capture3("cargo", "build", "--quiet", chdir: destination)
      expect(status.success?).to be(false)
      expect("#{stdout}#{stderr}").to include("invalid_method")
    end
  end
end
