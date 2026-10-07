# frozen_string_literal: true

require "open3"
require "tmpdir"
require_relative "../../system/import"

module Rubast
  module Build
    class Cargo
      include Import["build.writer"]

      def call(project)
        Dir.mktmpdir("rubast-build-") do |directory|
          writer.call(project, directory)

          stdout, stderr, status = Open3.capture3("cargo", "build", "--quiet", chdir: directory)
          unless status.success?
            raise CompilationError.new(
              code: "E_BUILD",
              message: "#{stdout}#{stderr}".strip,
              span: Span.new(path: directory, line: 1, column: 1)
            )
          end

          executable = File.join(directory, "target", "debug", "rubast_program")
          pid = Process.spawn(executable, in: $stdin, out: $stdout, err: $stderr)
          _finished_pid, status = Process.waitpid2(pid)
          ExecutionResult.new(exitstatus: status.exitstatus || 1)
        end
      end
    end
  end
end
