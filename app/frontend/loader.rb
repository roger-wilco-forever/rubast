# frozen_string_literal: true

require_relative "../../system/import"

module Rubast
  module Frontend
    class Loader
      include Import["source.reader", "frontend.parser", "frontend.normalizer"]

      def call(path)
        expand_file(path, {})
      end

      private

      def expand_file(path, loaded)
        source = reader.call(path)
        program = normalizer.call(parser.call(source), source)
        program.with(statements: program.statements.map { |node| expand_statement(node, loaded) }.freeze)
      end

      def expand_statement(node, loaded)
        return expand_load(node, loaded) if loading_call?(node)
        return node.with(value: expand_statement(node.value, loaded)) if node.is_a?(IR::LocalWrite)

        if node.is_a?(IR::Call) && node.receiver.nil? && %i[puts p].include?(node.name)
          return node.with(arguments: node.arguments.map { |part| expand_statement(part, loaded) }.freeze)
        end

        reject_nested_loads(node)
        node
      end

      def loading_call?(node)
        node.is_a?(IR::Call) && %i[require_relative require load autoload].include?(node.name) &&
          (node.receiver.nil? || node.receiver.is_a?(IR::SelfRead) ||
           (node.receiver.is_a?(IR::ConstantRead) && node.receiver.name == :Kernel))
      end

      def reject_nested_loads(node)
        # Namespace calls need semantic lookup: user methods can override Kernel's loader names.
        return if node.is_a?(IR::ClassDefinition)

        load_error(node, "loading is restricted to unconditional file-level statements") if loading_call?(node)
        return unless node.respond_to?(:span)

        node.to_h.except(:span).each_value do |value|
          Array(value).each { |child| reject_nested_loads(child) }
        end
      end

      def expand_load(node, loaded)
        argument = node.arguments.first
        unless %i[require_relative require].include?(node.name) && node.receiver.nil? &&
               !node.safe_navigation && node.arguments.one? && argument.is_a?(IR::StringLiteral)
          load_error(node, "require needs one literal UTF-8 path and an implicit receiver")
        end
        path = resolve_path(node, argument.value)
        key = reader.realpath(path, span: node.span)
        return IR::BooleanLiteral.new(value: false, span: node.span) if loaded.key?(key)

        # The in-progress mark is also the circular-load guard; insertion preserves dependency order.
        loaded[key] = true
        IR::SourceLoad.new(program: expand_file(path, loaded), name: node.name, frames: load_frames(node),
                           result_type: nil, span: node.span)
      end

      def load_frames(node)
        node.name == :require ? reader.require_frames(node.span) : [[node.span, "Kernel#require_relative"]].freeze
      end

      def resolve_path(node, value)
        validate_path(node, value)
        extension = File.extname(value)
        load_error(node, "only Ruby .rb source dependencies are supported") unless ["", ".rb"].include?(extension)
        base = node.name == :require_relative ? File.dirname(reader.realpath(node.span.path, span: node.span)) : Dir.pwd
        path = File.expand_path(value, base)
        path.end_with?(".rb") ? path : "#{path}.rb"
      end

      def validate_path(node, value)
        unless value.encoding == Encoding::UTF_8 && value.valid_encoding? && !value.include?("\0")
          load_error(node, "source paths must be valid UTF-8 without null bytes")
        end
        return unless node.name == :require && !value.start_with?("/", "./", "../")

        load_error(node, "require needs an absolute or explicit ./ or ../ path; load-path lookup is unsupported")
      end

      def load_error(node, message)
        raise CompilationError.new(code: "E_LOAD", message: message, span: node.span)
      end
    end
  end
end
