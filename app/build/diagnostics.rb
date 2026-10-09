# frozen_string_literal: true

require "json"

module Rubast
  module Build
    class Diagnostics
      def call(stdout, stderr, directory)
        errors = compiler_errors(stdout)
        text = errors.map { |message| message.dig("message", "rendered") || message.dig("message", "message") }
        text = [stdout] if text.empty?
        span = errors.lazy.filter_map { |message| error_span(message, directory) }.first
        [[*text, stderr].reject(&:empty?).join("\n").strip,
         span || Span.new(path: directory, line: 1, column: 1)]
      end

      private

      def compiler_errors(stdout)
        stdout.lines.filter_map { |line| parse(line) }.select do |message|
          message["reason"] == "compiler-message" && message.dig("message", "level") == "error"
        end
      end

      def parse(line)
        message = JSON.parse(line)
        message if message.is_a?(Hash)
      rescue JSON::ParserError
        nil
      end

      def error_span(message, directory)
        spans = message.dig("message", "spans") || []
        span = spans.find { |item| item["is_primary"] }
        return unless span

        path = File.expand_path(span.fetch("file_name"), directory)
        location = source_location(path, span.fetch("line_start"), directory)
        location ||= { "path" => path, "line" => span.fetch("line_start"), "column" => span.fetch("column_start") }
        Span.new(**location.transform_keys(&:to_sym))
      end

      def source_location(path, line, directory)
        return unless path == File.join(File.expand_path(directory), "src/main.rs")

        map = JSON.parse(File.read(File.join(directory, "source-map.json")))
        map.fetch("files").fetch("src/main.rs")[line.to_s]
      end
    end
  end
end
