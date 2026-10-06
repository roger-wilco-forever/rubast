# frozen_string_literal: true

require "fileutils"
require "open3"
require "tmpdir"

module Rubast
  module Build
    class Cargo
      RUNTIME_PATH = File.expand_path("../../runtime/rubast_runtime", __dir__)

      def call(project)
        Dir.mktmpdir("rubast-build-") do |directory|
          project.files.each do |name, content|
            path = File.join(directory, name)
            FileUtils.mkdir_p(File.dirname(path))
            File.write(path, content)
          end
          FileUtils.cp_r(RUNTIME_PATH, File.join(directory, "rubast_runtime"))

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
