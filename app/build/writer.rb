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

      def check_binary(destination, directory)
        if File.exist?(destination) || File.symlink?(destination)
          output_error(destination, "binary destination must not exist")
        end
        return unless directory

        binary = canonical_destination(destination)
        project = canonical_destination(directory)
        if binary == project || binary.start_with?("#{project}/") || project.start_with?("#{binary}/")
          output_error(destination, "binary destination and retained project must be separate")
        end
      rescue SystemCallError => error
        output_error(destination, error.message)
      end

      def binary(executable, destination)
        created = false
        FileUtils.mkdir_p(File.dirname(destination))
        File.open(destination, File::WRONLY | File::CREAT | File::EXCL, 0o755) do |output|
          created = true
          IO.copy_stream(executable, output)
          output.chmod(File.stat(executable).mode & 0o777)
        end
        destination
      rescue SystemCallError => error
        File.unlink(destination) if created
        output_error(destination, error.message)
      end

      private

      def canonical_destination(path)
        expanded = File.expand_path(path)
        return File.realpath(expanded) if File.exist?(expanded) || File.symlink?(expanded)

        File.join(canonical_destination(File.dirname(expanded)), File.basename(expanded))
      end

      def output_error(directory, message)
        raise CompilationError.new(code: "E_OUTPUT", message: message,
                                   span: Span.new(path: directory, line: 1, column: 1))
      end
    end
  end
end
