# frozen_string_literal: true

require "open3"
require "tmpdir"
require_relative "../../system/import"

module Rubast
  module Build
    class Cargo
      include Import["build.writer", "build.diagnostics"]

      def call(project, release: false, directory: nil)
        with_project(project, directory) do |path|
          executable = compile(path, release: release, retained: !directory.nil?)
          pid = Process.spawn([executable, executable], in: $stdin, out: $stdout, err: $stderr)
          _finished_pid, status = Process.waitpid2(pid)
          ExecutionResult.new(exitstatus: status.exitstatus || 1)
        end
      end

      def build(project, output, release: false, directory: nil)
        writer.check_binary(output, directory)
        with_project(project, directory) do |path|
          executable = compile(path, release: release, retained: !directory.nil?)
          writer.binary(executable, output)
        end
      end

      private

      def with_project(project, directory, &block)
        if directory
          writer.call(project, directory)
          block.call(File.expand_path(directory))
        else
          Dir.mktmpdir("rubast-build-") do |path|
            writer.call(project, path)
            block.call(path)
          end
        end
      end

      def compile(directory, release:, retained:)
        arguments = ["cargo", "build", "--quiet", "--message-format=json"]
        arguments << "--release" if release
        stdout, stderr, status = Open3.capture3(*arguments, chdir: directory)
        unless status.success?
          message, span = diagnostics.call(stdout, stderr, directory)
          build_error(message, span, directory, retained: retained)
        end
        File.join(directory, "target", release ? "release" : "debug", "rubast_program")
      rescue SystemCallError => error
        build_error(error.message, Span.new(path: directory, line: 1, column: 1), directory, retained: retained)
      end

      def build_error(message, span, directory, retained:)
        message = "#{message}\nGenerated project retained at #{directory}" if retained
        raise CompilationError.new(code: "E_BUILD", message: message, span: span)
      end
    end
  end
end
