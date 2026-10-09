# frozen_string_literal: true

module Rubast
  module Source
    class Reader
      def require_frames(span)
        # ponytail: calibrate pinned CRuby's standard loader; custom require wrappers need their own contract.
        frames = []
        trace = TracePoint.new(:c_call) do |event|
          next unless event.method_id == :require

          directory = File.dirname(event.path)
          # Compiler-only wrappers such as Zeitwerk live outside the native loader's directory.
          locations = caller_locations(1).take_while do |entry|
            entry.path != __FILE__ && entry.path.start_with?(directory)
          end
          frames = locations.map { |entry| loader_frame(entry, entry.label) }
          label = event.defined_class == Kernel ? "Kernel#require" : "Kernel.require"
          frames.unshift(event.path == __FILE__ ? [span, label].freeze : loader_frame(event, label))
        end
        # Prism is already loaded; capture this CRuby's loader frames without executing application code.
        trace.enable { require "prism" }
        frames.reverse.freeze
      end

      def realpath(path, span:)
        File.realpath(path)
      rescue SystemCallError => error
        raise CompilationError.new(code: "E_LOAD", message: error.message, span: span)
      end

      def call(path)
        absolute_path = File.expand_path(path)
        Rubast::SourceFile.new(path: absolute_path, bytes: File.binread(absolute_path))
      rescue SystemCallError => error
        raise CompilationError.new(
          code: "E_SOURCE",
          message: error.message,
          span: Span.new(path: absolute_path, line: 1, column: 1)
        )
      end

      private

      def loader_frame(location, label)
        [Span.new(path: location.path, line: location.lineno, column: 1), label].freeze
      end
    end
  end
end
