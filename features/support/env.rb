# frozen_string_literal: true

require "fileutils"
require "open3"
require "rbconfig"
require "tmpdir"
require "rspec/expectations"

expected_ruby = File.read(File.expand_path("../../.ruby-version", __dir__)).strip
unless RUBY_ENGINE == "ruby" && expected_ruby == RUBY_VERSION
  abort "Rubast features require CRuby #{expected_ruby}, got #{RUBY_VERSION}"
end

World(RSpec::Matchers)

Before do
  @workdir = Dir.mktmpdir("rubast-feature-")
end

After do
  FileUtils.remove_entry(@workdir) if @workdir && Dir.exist?(@workdir)
end
