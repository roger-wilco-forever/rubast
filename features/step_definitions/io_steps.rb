# frozen_string_literal: true

Given("standard input without a final newline is:") do |input|
  @stdin_data = input
end

Then("I see the unterminated prompt {string}") do |prompt|
  Timeout.timeout(30) do
    expect(@interactive_stdout.read(prompt.bytesize)).to eq(prompt)
  end
end
