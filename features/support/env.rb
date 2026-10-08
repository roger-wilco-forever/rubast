# frozen_string_literal: true

require "fileutils"
require "open3"
require "rbconfig"
require "tmpdir"
require "timeout"
require "rspec/expectations"
require_relative "program_execution"

expected_ruby = File.read(File.expand_path("../../.ruby-version", __dir__)).strip
unless RUBY_ENGINE == "ruby" && expected_ruby == RUBY_VERSION
  abort "Rubast features require CRuby #{expected_ruby}, got #{RUBY_VERSION}"
end

World(RSpec::Matchers)
World(RubastProgramExecution)

Before do
  @workdir = Dir.mktmpdir("rubast-feature-")
end

After do
  if @interactive_wait&.alive?
    begin
      Process.kill("TERM", @interactive_wait.pid)
    rescue Errno::ESRCH
      nil
    end
    @interactive_wait.join(2)
  end
  [@interactive_stdin, @interactive_stdout, @interactive_stderr].compact.each do |io|
    io.close unless io.closed?
  end
  FileUtils.remove_entry(@workdir) if @workdir && Dir.exist?(@workdir)
end
