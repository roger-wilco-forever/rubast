# frozen_string_literal: true

Given("the Ruby source is:") do |source|
  @source_path = File.join(@workdir, "example.rb")
  File.write(@source_path, source)
end

Given("the Ruby file {string} is:") do |name, source|
  path = File.join(@workdir, name)
  FileUtils.mkdir_p(File.dirname(path))
  File.write(path, source)
end

Given("the working directory is the source directory") do
  @program_directory = @workdir
end

Given("the program environment excludes Bundler startup") do
  @unbundled_startup = true
  paths = Gem.loaded_specs.values.map(&:base_dir).uniq.join(File::PATH_SEPARATOR)
  @program_environment = { "GEM_PATH" => paths }
end

Given("the Ruby source with absolute paths is:") do |source|
  @source_path = File.join(@workdir, "example.rb")
  File.write(@source_path, source.gsub("<source_directory>", @workdir))
end

Given("the file {string} links to {string}") do |name, target|
  File.symlink(target, File.join(@workdir, name))
end

When("I record CRuby execution") do
  @ruby_reference = capture_ruby_source(@source_path)
end

When("I remove the Ruby source files") do
  Dir.glob(File.join(@workdir, "**/*.rb")).each { |path| File.delete(path) }
end

When("I emit a Rust project") do
  @output_path ||= File.join(@workdir, "output project")
  executable = File.expand_path("../../bin/rubast", __dir__)
  @rubast_stdout, @rubast_stderr, @rubast_status =
    Open3.capture3(@emit_environment || {}, RbConfig.ruby, executable, "emit-rust", @source_path, "-o", @output_path,
                   chdir: @program_directory || Dir.pwd)
end

Then("the emitted project contains its source and runtime") do
  expect(@rubast_status.exitstatus).to eq(0)
  expect(@rubast_stdout).to eq("")
  expect(@rubast_stderr).to eq("")
  %w[Cargo.toml src/main.rs rubast_runtime/Cargo.toml rubast_runtime/src/lib.rs].each do |name|
    expect(File.file?(File.join(@output_path, name))).to be(true)
  end
  expect(File.exist?(File.join(@output_path, "rubast_runtime/target"))).to be(false)
end

When("I build and run the emitted project") do
  expect(@rubast_status.exitstatus).to eq(0)
  stdout, stderr, status = Open3.capture3("cargo", "build", "--quiet", chdir: @output_path)
  expect(status.success?).to be(true), "#{stdout}#{stderr}"
  executable = File.join(@output_path, "target/debug/rubast_program")
  @rubast_stdout, @rubast_stderr, @rubast_status =
    capture_program([executable, executable], stdin_data: @stdin_data.to_s)
end

Then("no Rust project was created") do
  expect(File.exist?(@output_path)).to be(false)
end

Given("the output directory contains an existing file") do
  @output_path = File.join(@workdir, "output project")
  FileUtils.mkdir_p(@output_path)
  File.write(File.join(@output_path, "Cargo.toml"), "keep this file")
end

Given("the output directory is empty") do
  @output_path = File.join(@workdir, "output project")
  FileUtils.mkdir_p(@output_path)
end

Given("Cargo is unavailable") do
  @emit_environment = { "PATH" => @workdir }
end

Given("the output path has a file as its parent") do
  parent = File.join(@workdir, "occupied")
  File.write(parent, "keep this file")
  @output_path = File.join(parent, "project")
end

Then("the output parent file is unchanged") do
  expect(File.read(File.dirname(@output_path))).to eq("keep this file")
end

Then("the existing output file is unchanged") do
  expect(Dir.children(@output_path)).to eq(["Cargo.toml"])
  expect(File.read(File.join(@output_path, "Cargo.toml"))).to eq("keep this file")
end

When("I invoke Rubast with {string}") do |arguments|
  executable = File.expand_path("../../bin/rubast", __dir__)
  @rubast_stdout, @rubast_stderr, @rubast_status =
    Open3.capture3(RbConfig.ruby, executable, *arguments.split, chdir: @workdir)
end

Then("Rubast reports a usage error") do
  expect(@rubast_status.exitstatus).to eq(64)
  expect(@rubast_stdout).to eq("")
  expect(@rubast_stderr).to include("Usage:")
end

When("I run Rubast") do
  executable = File.expand_path("../../bin/rubast", __dir__)
  @rubast_stdout, @rubast_stderr, @rubast_status =
    capture_ruby_source(executable, "run", @source_path)
end

Then("stdout, stderr, and exit status match CRuby") do
  ruby_stdout, ruby_stderr, ruby_status = @ruby_reference || capture_ruby_source(@source_path)
  expect(@rubast_stdout).to eq(ruby_stdout)
  expect(@rubast_stderr).to eq(ruby_stderr)
  expect(@rubast_status.exitstatus).to eq(ruby_status.exitstatus)
end

Then("the diagnostic has code {string} at line {int}") do |code, line|
  expect(@rubast_status.exitstatus).to eq(2)
  expect(@rubast_stdout).to eq("")
  expect(@rubast_stderr).to include(code)
  expect(@rubast_stderr).to match(/:#{line}:\d+/)
end

Then("the diagnostic names Ruby file {string}") do |name|
  expect(@rubast_stderr).to include("#{File.join(@workdir, name)}:")
end

Given("I use the example {string}") do |filename|
  @source_path = File.expand_path("../../examples/#{filename}", __dir__)
end

Given("standard input is:") do |input|
  @stdin_data = "#{input}\n"
end

When("I start Rubast interactively") do
  executable = File.expand_path("../../bin/rubast", __dir__)
  @interactive_stdin, @interactive_stdout, @interactive_stderr, @interactive_wait =
    Open3.popen3(RbConfig.ruby, executable, "run", @source_path)
end

Then("I see the prompt {string}") do |prompt|
  Timeout.timeout(30) do
    expect(@interactive_stdout.gets).to eq("#{prompt}\n")
  end
end

When("I enter {string}") do |name|
  @interactive_stdin.puts(name)
  @interactive_stdin.close
end

Then("I see the greeting {string}") do |greeting|
  Timeout.timeout(30) do
    expect(@interactive_stdout.gets).to eq("#{greeting}\n")
    expect(@interactive_stdout.read).to eq("")
    expect(@interactive_stderr.read).to eq("")
    expect(@interactive_wait.value.exitstatus).to eq(0)
  end
end

Then("the emitted Rust defines {int} receiver functions") do |count|
  source = File.read(File.join(@output_path, "src/main.rs"))
  expect(source.scan(/^fn method_\d+\(runtime: &mut Runtime, receiver: Value/).length).to eq(count)
end

Then("CRuby prints the reference output:") do |expected|
  stdout, stderr, status = capture_program(RbConfig.ruby, @source_path, stdin_data: @stdin_data.to_s)
  expect(status.exitstatus).to eq(0)
  expect(stderr).to eq("")
  expect(stdout).to eq("#{expected}\n")
end
