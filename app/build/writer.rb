# frozen_string_literal: true

require "fileutils"

module Rubast
  module Build
    class Writer
      RUNTIME_PATH = File.expand_path("../../runtime/rubast_runtime", __dir__)

      def call(project, directory)
        if File.exist?(directory) && (!File.directory?(directory) || !Dir.empty?(directory))
          output_error(directory, "output directory must be new or empty")
        end

        FileUtils.mkdir_p(directory)
        project.files.each do |name, content|
          path = File.join(directory, name)
          FileUtils.mkdir_p(File.dirname(path))
          File.write(path, content)
        end
        runtime = File.join(directory, "rubast_runtime")
        FileUtils.mkdir_p(runtime)
        %w[Cargo.toml src].each { |name| FileUtils.cp_r(File.join(RUNTIME_PATH, name), runtime) }
        directory
      rescue SystemCallError => error
        output_error(directory, error.message)
      end

      private

      def output_error(directory, message)
        raise CompilationError.new(code: "E_OUTPUT", message: message,
                                   span: Span.new(path: directory, line: 1, column: 1))
      end
    end
  end
end
