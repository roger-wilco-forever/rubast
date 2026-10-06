# frozen_string_literal: true

Given("исходный Ruby-код:") do |source|
  @source_path = File.join(@workdir, "example.rb")
  File.write(@source_path, source)
end

When("я запускаю Rubast") do
  executable = File.expand_path("../../bin/rubast", __dir__)
  @rubast_stdout, @rubast_stderr, @rubast_status =
    Open3.capture3(RbConfig.ruby, executable, "run", @source_path)
end

Then("вывод и код завершения совпадают с CRuby") do
  ruby_stdout, ruby_stderr, ruby_status = Open3.capture3(RbConfig.ruby, @source_path)
  expect(@rubast_stdout).to eq(ruby_stdout)
  expect(@rubast_stderr).to eq(ruby_stderr)
  expect(@rubast_status.exitstatus).to eq(ruby_status.exitstatus)
end

Then("ошибка содержит код {string} и строку {int}") do |code, line|
  expect(@rubast_status.exitstatus).to eq(2)
  expect(@rubast_stdout).to eq("")
  expect(@rubast_stderr).to include(code)
  expect(@rubast_stderr).to match(/:#{line}:\d+/)
end
