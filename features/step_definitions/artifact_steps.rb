# frozen_string_literal: true

require "json"

When("I build a persistent binary in {string} mode") do |profile|
  build_persistent_binary(profile)
end

When("I build a persistent binary in {string} mode retaining its project") do |profile|
  @output_path ||= File.join(@workdir, "retained project")
  build_persistent_binary(profile, keep: @output_path)
end

When("I run Rubast in release mode retaining its project") do
  @output_path = File.join(@workdir, "retained project")
  executable = File.expand_path("../../bin/rubast", __dir__)
  @rubast_stdout, @rubast_stderr, @rubast_status =
    capture_ruby_source(executable, "run", @source_path, "--release", "--keep-project", @output_path)
end

Then("the binary was built without running it") do
  expect(@rubast_status.exitstatus).to eq(0), @rubast_stderr
  expect(@rubast_stdout).to eq("")
  expect(@rubast_stderr).to eq("")
  expect(File.executable?(@binary_path)).to be(true)
end

When("I run the persistent binary") do
  @rubast_stdout, @rubast_stderr, @rubast_status =
    capture_program([@binary_path, @binary_path], stdin_data: @stdin_data.to_s)
end

Then("the retained project uses the {string} profile") do |profile|
  expect(File.executable?(File.join(@output_path, "target", profile, "rubast_program"))).to be(true)
end

Then("the retained project contains compiler artifacts") do
  %w[Cargo.toml src/main.rs source-map.json].each do |name|
    expect(File.file?(File.join(@output_path, name))).to be(true)
  end
end

Then("the emitted source map refers to Ruby source") do
  map = JSON.parse(File.read(File.join(@output_path, "source-map.json")))
  expect(map.fetch("version")).to eq(1)
  locations = map.fetch("files").fetch("src/main.rs").values
  expect(locations).to include(include("path" => @source_path))
end

Given("the binary destination is an existing {string}") do |kind|
  @binary_path = File.join(@workdir, "output binary")
  @binary_kind = kind
  case kind
  when "file" then File.write(@binary_path, "preserve binary")
  when "directory" then Dir.mkdir(@binary_path)
  when "dangling link" then File.symlink("missing", @binary_path)
  end
end

Then("the binary destination is unchanged") do
  case @binary_kind
  when "file" then expect(File.read(@binary_path)).to eq("preserve binary")
  when "directory" then expect(Dir.empty?(@binary_path)).to be(true)
  when "dangling link" then expect(File.readlink(@binary_path)).to eq("missing")
  end
end

Given("the binary destination is inside the retained project") do
  @output_path = File.join(@workdir, "retained project")
  @binary_path = File.join(@output_path, "program")
end

Then("no binary was created") do
  expect(File.exist?(@binary_path)).to be(false)
end

When("I dump {string} IR") do |stage|
  executable = File.expand_path("../../bin/rubast", __dir__)
  @rubast_stdout, @rubast_stderr, @rubast_status =
    Open3.capture3(@emit_environment || {}, RbConfig.ruby, executable, "dump-ir", @source_path, "--stage", stage)
end

Then("the IR dump has stage {string} and node {string}") do |stage, node|
  expect(@rubast_status.exitstatus).to eq(0), @rubast_stderr
  expect(@rubast_stderr).to eq("")
  @dump = JSON.parse(@rubast_stdout)
  expect(@dump.fetch("stage")).to eq(stage)
  expect(@dump.fetch("nodes").values).to include(include("type" => "Rubast::IR::#{node}"))
end

Then("the IR dump identifies Ruby line {int}") do |line|
  expect(@dump.fetch("nodes").values).to include(
    include("type" => "Rubast::Span", "members" => include("path" => @source_path, "line" => line))
  )
end

Then("the IR dump contains valid shared references") do
  nodes = @dump.fetch("nodes")
  references = @rubast_stdout.scan(/"\$ref":\s*"(\d+)"/).flatten
  expect(references.tally.values.max).to be > 1
  expect(references.all? { |id| nodes.key?(id) }).to be(true)
end

Given("the binary destination overlaps the retained project through a directory alias") do
  @real_output_path = File.join(@workdir, "real project")
  Dir.mkdir(@real_output_path)
  @output_path = File.join(@workdir, "project alias")
  File.symlink(@real_output_path, @output_path)
  @binary_path = File.join(@real_output_path, "binary")
end

Then("the aliased output directory is unchanged") do
  expect(File.readlink(@output_path)).to eq(@real_output_path)
  expect(Dir.empty?(@real_output_path)).to be(true)
end

Given("the binary destination has a file as its parent") do
  @binary_parent = File.join(@workdir, "occupied parent")
  File.write(@binary_parent, "keep this file")
  @binary_path = File.join(@binary_parent, "binary")
end

Then("the binary parent file is unchanged") do
  expect(File.read(@binary_parent)).to eq("keep this file")
end

Then("the IR dump retains an object cycle") do
  nodes = @dump.fetch("nodes")
  objects = nodes.select { |_id, node| node["type"] == "Rubast::IR::ObjectType" }
  cyclic = objects.any? do |id, node|
    fields = nodes.fetch(node.fetch("members").fetch("fields").fetch("$ref"))
    fields.fetch("entries").any? { |_key, value| value == { "$ref" => id } }
  end
  expect(cyclic).to be(true)
end

module ArtifactExecution
  def build_persistent_binary(profile, keep: nil)
    @binary_path ||= File.join(@workdir, "output binary")
    executable = File.expand_path("../../bin/rubast", __dir__)
    arguments = ["build", @source_path, "-o", @binary_path]
    arguments << "--release" if profile == "release"
    arguments.push("--keep-project", keep) if keep
    @rubast_stdout, @rubast_stderr, @rubast_status =
      Open3.capture3(@emit_environment || {}, RbConfig.ruby, executable, *arguments)
  end
end

World(ArtifactExecution)

Given("I use the benchmark {string}") do |name|
  @source_path = File.expand_path("../../benchmarks/workloads/#{name}.rb", __dir__)
end
