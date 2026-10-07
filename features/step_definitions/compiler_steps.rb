# frozen_string_literal: true

Given("the Ruby source is:") do |source|
  @source_path = File.join(@workdir, "example.rb")
  File.write(@source_path, source)
end

When("I emit a Rust project") do
  @output_path ||= File.join(@workdir, "output project")
  executable = File.expand_path("../../bin/rubast", __dir__)
  @rubast_stdout, @rubast_stderr, @rubast_status =
    Open3.capture3(@emit_environment || {}, RbConfig.ruby, executable, "emit-rust", @source_path, "-o", @output_path)
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
    Open3.capture3([executable, executable], stdin_data: @stdin_data.to_s)
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
    Open3.capture3(RbConfig.ruby, executable, "run", @source_path, stdin_data: @stdin_data.to_s)
end

Then("stdout, stderr, and exit status match CRuby") do
  ruby_stdout, ruby_stderr, ruby_status = Open3.capture3(RbConfig.ruby, @source_path, stdin_data: @stdin_data.to_s)
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
