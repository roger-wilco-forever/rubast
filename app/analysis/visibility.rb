# frozen_string_literal: true

module Rubast
  module Analysis
    module Visibility
      VISIBILITIES = %i[public protected private].freeze
      DECLARATIONS = [*VISIBILITIES, :private_class_method, :public_class_method,
                      :attr_reader, :attr_writer, :attr_accessor].freeze

      module Declarations
        private

        def declaration_call?(node)
          @definition_owner && node.receiver.nil? && DECLARATIONS.include?(node.name) && !implicit_method?(node)
        end

        def validate_declaration(node, locals)
          unsupported(node) if node.safe_navigation
          return validate_attributes(node, locals) if %i[attr_reader attr_writer attr_accessor].include?(node.name)

          owner, visibility = visibility_target(node)
          return set_default_visibility(node, owner, visibility) if node.arguments.empty?

          values = node.arguments.map { |part| visibility_argument(part) }
          values.each do |part|
            name = declaration_name(part)
            unsupported(node) unless visibility_method?(owner, name)
            (@visibilities[owner] ||= {})[name] = visibility
          end
          visibility_result(node, values, locals)
        end

        def visibility_method?(owner, name)
          lookup_method(owner, name) || native_constructor?(owner, name)
        end

        def native_constructor?(owner, name)
          owner.is_a?(IR::SingletonClass) && name == :new && @namespace_kinds[owner.name] == :class
        end

        def visibility_result(node, values, locals)
          values = values.map { |value| validate_literal(value) }
          if %i[private_class_method public_class_method].include?(node.name)
            receiver = IR::SelfRead.new(result_type: @receiver_type, span: node.span)
            return IR::Sequence.new(expressions: [*values, receiver].freeze,
                                    result_type: @receiver_type, span: node.span)
          end
          return values.first if values.one?

          validate_array(IR::ArrayLiteral.new(elements: values.freeze, result_type: nil, span: node.span), locals)
        end

        def set_default_visibility(node, owner, visibility)
          unsupported(node) unless VISIBILITIES.include?(node.name)
          @default_visibility[owner] = visibility
          IR::NilLiteral.new(span: node.span)
        end

        def visibility_target(node)
          classes = { private_class_method: :private, public_class_method: :public }
          if classes.key?(node.name)
            [IR::SingletonClass.new(name: @definition_owner), classes.fetch(node.name)]
          else
            [@definition_key, node.name]
          end
        end

        def visibility_argument(part)
          return part unless part.is_a?(IR::MethodDefinition)

          unsupported(part) if part.singleton
          register_namespace_method(part)
        end

        def declaration_name(part)
          unsupported(part) unless part.is_a?(IR::SymbolLiteral) || part.is_a?(IR::StringLiteral)
          part.value.to_sym
        end

        def declaration_names(names, span, locals)
          values = names.map { |name| IR::SymbolLiteral.new(value: name.to_s.encode(Encoding::UTF_8), span: span) }
          validate_array(IR::ArrayLiteral.new(elements: values.freeze, result_type: nil, span: span), locals)
        end
      end

      module Attributes
        private

        def validate_attributes(node, locals)
          names = node.arguments.flat_map do |part|
            name = declaration_name(part)
            unsupported(part) unless /\A[[:alpha:]_][[:alnum:]_]*\z/.match?(name.to_s)
            attribute_methods(name, node).map do |method|
              register_namespace_method(method)
              method.name
            end
          end
          declaration_names(names, node.span, locals)
        end

        def attribute_methods(name, node)
          span = node.span
          read = IR::InstanceRead.new(name: :"@#{name}", result_type: nil, span: span)
          value = IR::LocalRead.new(name: :value, span: span)
          write = IR::InstanceWrite.new(name: :"@#{name}", value: value, span: span)
          methods = []
          methods << attribute_method(name, [], read, span) unless node.name == :attr_writer
          methods << attribute_method(:"#{name}=", [:value], write, span) unless node.name == :attr_reader
          methods
        end

        def attribute_method(name, parameters, body, span)
          IR::MethodDefinition.new(name: name, parameters: parameters.freeze, locals: parameters.freeze,
                                   body: IR::Sequence.new(expressions: [body].freeze, result_type: nil, span: span),
                                   span: span, native: true)
        end

        def validate_setter(node, locals)
          call = validate_call(node.call, locals)
          result = type_of(call, locals) == :never ? :never : type_of(call.arguments.last, locals)
          node.with(call: call, result_type: result)
        end
      end

      include Declarations
      include Attributes

      private

      def record_method_visibility(owner, method)
        default = @default_visibility.fetch(owner, :public)
        visibility = method.name == :initialize ? :private : default
        visibility = :public if method.singleton
        (@visibilities[owner] ||= {})[method.name] = visibility
      end

      def implicit_visibility?(call, target)
        (call.name == :new && target && target.last.name == :initialize) ||
          call.receiver.nil? || call.receiver.is_a?(IR::SelfRead)
      end

      def protected_receiver?(chain, owner)
        @receiver_type && method_ancestors(@receiver_type.class_name).include?(owner) && chain.include?(owner)
      end

      def check_method_visibility(call, type, target)
        return if implicit_visibility?(call, target)

        chain = method_ancestors(type.class_name)
        visibility = chain.filter_map { |key| @visibilities.fetch(key, {})[call.name] }.first || :public
        return if visibility == :public

        return if visibility == :protected && protected_receiver?(chain, target ? target.first.key : type.class_name)

        unsupported(call)
      end
    end
  end
end
