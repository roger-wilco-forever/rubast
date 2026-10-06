# frozen_string_literal: true

Given("the Ruby source is:") do |source|
  @source_path = File.join(@workdir, "example.rb")
  File.write(@source_path, source)
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
