# frozen_string_literal: true

module Rubast
  module Analysis
    module TextIo
      REFERENCES = { STDIN: :stdin, STDOUT: :stdout, STDERR: :stderr, File: :file_class }.freeze

      GLOBALS = { :$stdin => :stdin, :$stdout => :stdout, :$stderr => :stderr }.freeze
      SYSTEM_ERRORS = Exceptions::PARENTS.select { |_, parent| parent == :SystemCallError }.keys.freeze

      private

      def io_type?(type)
        REFERENCES.value?(type)
      end

      def validate_stream_global(node)
        unsupported(node) unless GLOBALS.key?(node.name)
        IR::IOReference.new(result_type: GLOBALS.fetch(node.name), span: node.span)
      end

      def io_reference(node)
        parts, = constant_parts(node)
        return unless parts.one? && REFERENCES.key?(parts.first)

        IR::IOReference.new(result_type: REFERENCES.fetch(parts.first), span: node.span)
      end

      def validate_io_kernel(node, locals)
        stream = node.name == :warn ? :stderr : :stdout
        stream = :stdin if node.name == :gets
        receiver = IR::IOReference.new(result_type: stream, span: node.span)
        call = validate_io_call(node, receiver, stream, locals)
        call.with(name: :"kernel_#{node.name}")
      end

      def validate_io_call(node, receiver, type, locals)
        unsupported(node) if node.safe_navigation || !io_arity?(node, type)
        arguments, types = validate_arguments(node.arguments, (0...node.arguments.length).to_a, locals) do |argument|
          validate_output(argument, locals)
        end
        if (type == :file_class) && !(string_type?(types.fetch(0)) || %i[unknown never].include?(types.fetch(0)))
          unsupported(node.arguments.first)
        end
        result = types.value?(:never) ? :never : io_result(node, type)
        record_io_errors(node, type, locals) unless result == :never
        IR::Builtin.new(family: :io, name: node.name, receiver: receiver, arguments: arguments,
                        result_type: result, span: node.span)
      end

      def io_arity?(node, type)
        if type == :file_class
          return node.arguments.length == (node.name == :read ? 1 : 2) if %i[read write].include?(node.name)

          return false
        end
        case node.name
        when :gets, :read, :flush then node.arguments.empty?
        when :puts then true
        when :warn then node.receiver.nil?
        when :print, :write then !node.arguments.empty?
        else false
        end
      end

      def io_result(node, type)
        return :string if node.name == :read
        return :string_or_nil if node.name == :gets
        return type if node.name == :flush
        return integer_type(0, Validator::MAX_INTEGER, node) if node.name == :write

        :nil
      end

      def record_io_errors(node, type, locals)
        classes = [:IOError, :SystemCallError, *SYSTEM_ERRORS]
        classes << :ArgumentError if type == :file_class
        classes << :"Encoding::InvalidByteSequenceError" if %i[read gets].include?(node.name)
        classes.each { |name| record_exception(name, locals, node) }
      end
    end
  end
end
