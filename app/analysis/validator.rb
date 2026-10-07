# frozen_string_literal: true

module Rubast
  module Analysis
    class Validator
      MIN_INTEGER = -(2**63)
      MAX_INTEGER = (2**63) - 1

      def call(program)
        Session.new.call(program)
      end

      module InstanceState
        private

        def validate_variable(node, locals)
          case node
          when IR::InstanceRead
            unsupported(node) unless @receiver_type
            node.with(result_type: @receiver_type.fields[node.name])
          when IR::InstanceWrite
            unsupported(node) unless @receiver_type
            value = validate_scalar(node.value, locals)
            @receiver_type.fields[node.name] = type_of(value, locals)
            node.with(value: value)
          else validate_local(node, locals)
          end
        end

        def validate_method_body(method, parameters, receiver)
          saved_receiver = @receiver_type
          @receiver_type = receiver
          locals = method.locals.to_h { |name| [name, :nil] }.merge(parameters)
          validate_scalar(method.body, locals)
        ensure
          @receiver_type = saved_receiver
        end
      end

      class Session < Validator
        include InstanceState

        def call(program)
          @classes = {}
          locals = {}
          statements = program.statements.filter_map { |node| validate_statement(node, locals) }
          IR::Program.new(statements: statements.freeze)
        end

        private

        def validate_statement(node, locals)
          case node
          when IR::ClassDefinition then validate_class(node)
          when IR::LocalWrite then validate_local_write(node, locals)
          when IR::Call
            return validate_puts(node, locals) if node.name == :puts && node.receiver.nil?

            value = validate_call(node, locals)
            unsupported(node) unless value.is_a?(IR::MethodCall) || value.is_a?(IR::NewObject)
            value
          else
            unsupported(node)
          end
        end

        def validate_puts(node, locals)
          unless node.receiver.nil? && !node.safe_navigation && node.name == :puts && node.arguments.one?
            unsupported(node)
          end

          IR::Puts.new(value: validate_scalar(node.arguments.first, locals), span: node.span)
        end

        def validate_class(node)
          unsupported(node) if @classes.key?(node.name) || Object.const_defined?(node.name, false)
          methods = {}
          node.definitions.each do |method|
            unsupported(method) if methods.key?(method.name)
            parameters = method.parameters.to_h { |name| [name, :scalar] }
            receiver = IR::ObjectType.new(class_name: node.name, fields: Hash.new(:scalar))
            validate_method_body(method, parameters, receiver)
            methods[method.name] = method
          end
          @classes[node.name] = methods.freeze
          nil
        end

        def validate_scalar(node, locals)
          value = validate_expression(node, locals)
          unsupported(node) if type_of(value, locals).is_a?(IR::ObjectType)
          value
        end

        def validate_expression(node, locals)
          case node
          when IR::IntegerLiteral, IR::StringLiteral, IR::NilLiteral then validate_literal(node)
          when IR::LocalRead, IR::LocalWrite, IR::InstanceRead, IR::InstanceWrite then validate_variable(node, locals)
          when IR::Sequence then validate_sequence(node, locals)
          when IR::InterpolatedString
            parts = node.parts.map { |part| validate_scalar(part, locals) }
            IR::InterpolatedString.new(parts: parts.freeze, span: node.span)
          when IR::Call then validate_call(node, locals)
          else unsupported(node)
          end
        end

        def validate_call(node, locals)
          return validate_puts(node, locals) if node.receiver.nil? && node.name == :puts
          return IR::GetLine.new(span: node.span) if gets_call?(node)
          return validate_safe_chomp(node, locals) if safe_chomp_call?(node)
          return validate_new(node, locals) if node.receiver.is_a?(IR::ConstantRead)
          return validate_method_call(node, locals) if node.receiver && !node.safe_navigation

          unsupported(node)
        end

        def validate_new(node, locals)
          name = node.receiver.name
          unsupported(node) unless @classes.key?(name) && node.name == :new && !node.safe_navigation
          type = IR::ObjectType.new(class_name: name, fields: Hash.new(:nil))
          invocation = validate_invocation(node, @classes.fetch(name)[:initialize], locals, type)
          IR::NewObject.new(class_name: name, **invocation, result_type: type, span: node.span)
        end

        def validate_method_call(node, locals)
          receiver = validate_expression(node.receiver, locals)
          type = type_of(receiver, locals)
          unsupported(node) unless type.is_a?(IR::ObjectType) && node.name != :initialize
          method = @classes.fetch(type.class_name)[node.name]
          unsupported(node) unless method
          invocation = validate_invocation(node, method, locals, type)
          IR::MethodCall.new(receiver: receiver, **invocation,
                             result_type: invocation.fetch(:body).result_type, span: node.span)
        end

        def validate_safe_chomp(node, locals)
          receiver = validate_expression(node.receiver, locals)
          return IR::SafeChomp.new(receiver: receiver, span: node.span) if string_like?(receiver, locals)

          unsupported(node)
        end
      end

      private

      def validate_invocation(node, method, locals, receiver)
        names = method&.parameters || []
        unsupported(node) unless node.arguments.length == names.length
        arguments, parameters = validate_arguments(node.arguments, names, locals)
        body = if method
                 validate_method_body(method, parameters, receiver)
               else
                 IR::Sequence.new(expressions: [].freeze, result_type: :nil, span: node.span)
               end
        { arguments: arguments, parameters: names, locals: method&.locals || [], body: body }
      end

      def validate_literal(node)
        case node
        when IR::IntegerLiteral then validate_integer(node)
        when IR::StringLiteral then validate_string(node)
        when IR::NilLiteral then node
        end
      end

      def validate_local_write(node, locals)
        value = validate_expression(node.value, locals)
        locals[node.name] = type_of(value, locals)
        node.with(value: value)
      end

      def validate_local(node, locals)
        return validate_local_write(node, locals) if node.is_a?(IR::LocalWrite)

        locals.key?(node.name) ? node : unsupported(node)
      end

      def validate_sequence(node, locals)
        result_type = :nil
        expressions = node.expressions.map do |expression|
          value = validate_expression(expression, locals)
          result_type = type_of(value, locals)
          value
        end
        node.with(expressions: expressions.freeze, result_type: result_type)
      end

      def type_of(node, locals)
        case node
        when IR::NilLiteral, IR::Puts then :nil
        when IR::IntegerLiteral then :integer
        when IR::StringLiteral, IR::InterpolatedString then :string
        when IR::GetLine, IR::SafeChomp then :string_or_nil
        when IR::LocalRead, IR::LocalWrite, IR::InstanceWrite then local_type(node, locals)
        when IR::NewObject, IR::MethodCall, IR::Sequence, IR::InstanceRead then node.result_type
        end
      end

      def local_type(node, locals)
        node.is_a?(IR::LocalRead) ? locals.fetch(node.name) : type_of(node.value, locals)
      end

      def gets_call?(node)
        node.receiver.nil? && !node.safe_navigation && node.name == :gets && node.arguments.empty?
      end

      def safe_chomp_call?(node)
        node.receiver && node.safe_navigation && node.name == :chomp && node.arguments.empty?
      end

      def string_like?(node, locals)
        %i[string string_or_nil nil scalar].include?(type_of(node, locals))
      end

      def validate_arguments(nodes, names, locals)
        types = {}
        arguments = nodes.zip(names).map do |node, name|
          value = validate_scalar(node, locals)
          types[name] = type_of(value, locals)
          value
        end
        [arguments.freeze, types]
      end

      def validate_integer(node)
        return node if (MIN_INTEGER..MAX_INTEGER).cover?(node.value)

        raise CompilationError.new(
          code: "E_INTEGER_RANGE",
          message: "integer literal exceeds the current 64-bit range",
          span: node.span
        )
      end

      def validate_string(node)
        return node if node.value.encoding == Encoding::UTF_8 && node.value.valid_encoding?

        raise CompilationError.new(
          code: "E_ENCODING",
          message: "only UTF-8 string literals are supported",
          span: node.span
        )
      end

      def unsupported(node)
        raise CompilationError.new(
          code: "E_UNSUPPORTED",
          message: "unsupported Ruby expression: #{node.class.name.split('::').last}",
          span: node.span
        )
      end
    end
  end
end
