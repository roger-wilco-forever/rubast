# frozen_string_literal: true

require "rbconfig"
require_relative "../../features/support/program_execution"

RSpec.describe RubastProgramExecution do
  let(:runner) { Object.new.extend(described_class) }

  it "captures input, both streams, and a nonzero exit status" do
    stdout, stderr, status = runner.capture_program(
      RbConfig.ruby, "-e", 'puts STDIN.read; warn "error"; exit 3', stdin_data: "Ada"
    )
    expect([stdout, stderr, status.exitstatus]).to eq(["Ada\n", "error\n", 3])
  end

  it "kills the process group when an inherited output pipe keeps a program alive" do
    source = 'fork { sleep 10 }; puts "ready"; exit'
    expect { runner.capture_program(RbConfig.ruby, "-e", source, timeout: 0.2) }.to raise_error(Timeout::Error)
  end
end
