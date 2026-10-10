# frozen_string_literal: true

module Rubast
  module Analysis
    module Namespaces
      module Constants
        private

        def constant_parts(node)
          return [[node.name], false] if node.is_a?(IR::ConstantRead)
          return [[node], false] if node.is_a?(Symbol)

          unsupported(node) unless node.is_a?(IR::ConstantPath)
          [node.parts, node.absolute]
        end

        def constant_name(owner, name)
          owner ? :"#{owner}::#{name}" : name
        end

        def namespace_type?(type)
          type.is_a?(IR::ObjectType) && type.class_name.is_a?(IR::SingletonClass)
        end

        def constant_ancestor(owner, name)
          constant_ancestors(owner).each do |ancestor|
            key = constant_name(ancestor, name)
            return key if @constants.key?(key)
          end
          nil
        end

        def lexical_constant(name)
          @constant_scopes.each do |owner|
            key = constant_name(owner, name)
            return key if @constants.key?(key)
          end
          constant_ancestor(@constant_scopes.first, name) || (@constants.key?(name) && name)
        end

        def resolve_constant(node)
          parts, absolute = constant_parts(node)
          key = absolute ? (@constants.key?(parts.first) && parts.first) : lexical_constant(parts.first)
          parts.drop(1).each do |name|
            type = key && @constants[key]
            unsupported(node) unless namespace_type?(type)
            key = constant_ancestor(type.class_name.name, name)
          end
          key
        end

        def validate_constant_read(node)
          key = resolve_constant(node)
          unless key
            reference = io_reference(node)
            return reference if reference

            unsupported(node) unless @checking_unused
            return IR::ConstantGet.new(name: constant_parts(node).first.join("::"), result_type: :unknown,
                                       span: node.span)
          end
          IR::ConstantGet.new(name: key, result_type: @constants.fetch(key), span: node.span)
        end

        def constant_destination(node)
          parts, absolute = constant_parts(node)
          owner = absolute ? nil : @constant_scopes.first
          if parts.length > 1
            parent = IR::ConstantPath.new(parts: parts[0...-1], absolute: absolute, span: node.span)
            type = @constants[resolve_constant(parent)]
            unsupported(node) unless namespace_type?(type)
            owner = type.class_name.name
          end
          constant_name(owner, parts.last)
        end

        def validate_constant_write(node, locals)
          name = constant_destination(node.target)
          unsupported(node) if existing_constant?(name)
          value = validate_expression(node.value, locals)
          type = type_of(value, locals)
          unsupported(node) if block_type?(type)
          @constants[name] = type
          IR::ConstantSet.new(name: name, value: value, result_type: type, span: node.span)
        end
      end

      module Bodies
        private

        def validate_class(node)
          name = constant_destination(node.name)
          parent = namespace_parent(node)
          fresh = !existing_constant?(name)
          name = reopen_namespace(node, name, parent) unless fresh
          register_namespace(name, node.kind, parent) if fresh
          scope = node.locals.to_h { |local| [local, :nil] }
          body = namespace_body(node, name, scope, fresh: fresh)
          IR::NamespaceBody.new(name: name, kind: node.kind, receiver: namespace_read(name, node.span),
                                locals: node.locals, body: body, result_type: body.result_type, span: node.span,
                                label: constant_parts(node.name).first.last.to_s)
        end

        def reopen_namespace(node, name, parent)
          type = @constants[name]
          unsupported(node) unless namespace_type?(type)
          actual = type.class_name.name
          unsupported(node) unless @namespace_kinds[actual] == node.kind
          unsupported(node) if node.superclass && @superclasses[actual] != parent
          actual
        end

        def namespace_parent(node)
          return nil unless node.superclass

          type = @constants[resolve_constant(node.superclass)]
          unsupported(node.superclass) unless namespace_type?(type) && @namespace_kinds[type.class_name.name] == :class
          type.class_name.name
        end

        def register_namespace(name, kind, parent)
          singleton = IR::SingletonClass.new(name: name)
          @classes[name] = {}
          @classes[singleton] = {}
          @superclasses[name] = parent
          @superclasses[singleton] = parent && IR::SingletonClass.new(name: parent)
          @namespace_kinds[name] = kind
          @namespace_values[name] = object_type(singleton, :nil)
          @constants[name] = @namespace_values.fetch(name)
        end

        def namespace_read(name, span)
          IR::ConstantGet.new(name: name, result_type: @namespace_values.fetch(name), span: span)
        end

        def namespace_body(node, name, locals, fresh:)
          saved = [@receiver_type, @constant_scopes, @definition_owner, @definition_key, @namespace_methods]
          visibility = @default_visibility.fetch(name, :public)
          @default_visibility[name] = :public
          @namespace_methods = []
          @receiver_type = @namespace_values.fetch(name)
          @constant_scopes = [name, *@constant_scopes]
          @definition_owner = name
          @definition_key = name
          first = namespace_entry(name, node.span, fresh)
          parts = [first, *node.definitions.map { |part| validate_namespace_part(part, locals) }]
          check_namespace_methods(@namespace_methods, locals)
          last = node.definitions.empty? ? :nil : type_of(parts.last, locals)
          result = continuing_type(parts, locals, last)
          IR::Sequence.new(expressions: parts.freeze, result_type: result, span: node.span)
        ensure
          @default_visibility[name] = visibility
          @receiver_type, @constant_scopes, @definition_owner, @definition_key, @namespace_methods = saved
        end

        def namespace_entry(name, span, fresh)
          return namespace_read(name, span) unless fresh

          allocation = IR::ClassValue.new(result_type: @receiver_type, span: span)
          IR::ConstantSet.new(name: name, value: allocation, result_type: @receiver_type, span: span)
        end

        def validate_namespace_part(part, locals)
          with_namespace_declaration(part) do
            case part
            when IR::MethodDefinition then register_namespace_method(part)
            when IR::SingletonBody then validate_singleton_body(part)
            else validate_statement(part, locals)
            end
          end
        end

        def with_namespace_declaration(part)
          previous = @namespace_declaration
          @namespace_declaration = part
          yield
        ensure
          @namespace_declaration = previous
        end
      end

      module Methods
        private

        def register_namespace_method(method, singleton: method.singleton)
          owner = singleton ? IR::SingletonClass.new(name: @definition_owner) : @definition_key
          reject_definition_callbacks(method, owner)
          methods = @classes.fetch(owner)
          methods[method.name] = method
          @namespace_methods << [owner, method]
          @source_symbols |= [method.name.to_s]
          record_method_visibility(owner, method)
          @method_scopes[method] = @constant_scopes.dup.freeze
          IR::SymbolLiteral.new(value: method.name.to_s.encode(Encoding::UTF_8), span: method.span)
        end

        def reject_definition_callbacks(method, owner)
          hooks = %i[method_added singleton_method_added inherited]
          namespace = owner.is_a?(IR::SingletonClass) || @namespace_kinds[owner] == :module
          unsupported(method) if namespace && hooks.include?(method.name)
        end

        def validate_singleton_body(node)
          previous = @definition_key
          @definition_key = IR::SingletonClass.new(name: @definition_owner)
          visibility = @default_visibility.fetch(@definition_key, :public)
          @default_visibility[@definition_key] = :public
          parts = node.definitions.map do |part|
            if part.is_a?(IR::MethodDefinition) && !part.singleton
              register_namespace_method(part)
            elsif part.is_a?(IR::Call) && declaration_call?(part)
              with_namespace_declaration(part) { validate_declaration(part, {}) }
            else
              unsupported(part)
            end
          end
          IR::Sequence.new(expressions: parts.freeze,
                           result_type: parts.empty? ? :nil : type_of(parts.last, {}), span: node.span)
        ensure
          @default_visibility[@definition_key] = visibility
          @definition_key = previous
        end

        def check_namespace_methods(methods, locals)
          before = snapshot(locals)
          count = @objects.length
          exits = flow_exit_counts
          previous = @checking_unused
          @checking_unused = true
          methods.each do |owner, method|
            receiver = object_type(owner, :unknown)
            parameters = method.parameters.to_h { |parameter| [parameter, :unknown] }
            position = method_ancestors(owner).index(owner)
            target = IR::MethodOwner.new(key: owner, index: position)
            validate_method_body(method, parameters, receiver, owner: target)
          end
        ensure
          restore(before, locals)
          @objects.slice!(count..)
          restore_flow_exits(exits)
          @checking_unused = previous
        end
      end

      include Constants
      include Bodies
      include Methods

      private

      def validate_namespace_reference(node, locals)
        return validate_source_load(node) if node.is_a?(IR::SourceLoad)
        return validate_stream_global(node) if node.is_a?(IR::GlobalRead)

        node.is_a?(IR::Setter) ? validate_setter(node, locals) : validate_constant_read(node)
      end

      def validate_builtin_call(node, locals)
        validate_loading_call(node) if %i[require_relative require load autoload].include?(node.name)
        memory = validate_memory_call(node)
        return memory if memory

        return validate_declaration(node, locals) if declaration_call?(node)
        return validate_composition(node, locals) if composition_call?(node)
        return validate_kernel_call(node, locals) if node.receiver.nil? && %i[puts p print warn gets raise
                                                                              fail].include?(node.name)

        nil
      end

      def validate_memory_call(node)
        receiver = node.receiver
        return unless receiver.is_a?(IR::ConstantRead) || receiver.is_a?(IR::ConstantPath)
        return unless constant_parts(receiver).first == [:GC] && !resolve_constant(receiver)

        unsupported(node) unless node.name == :start && node.arguments.empty? && !node.safe_navigation
        IR::Builtin.new(family: :memory, name: :start, receiver: IR::NilLiteral.new(span: receiver.span),
                        arguments: [], result_type: :nil, span: node.span)
      end

      def validate_loading_call(node)
        return unless kernel_load_receiver?(node)
        return if @checking_unused && implicit_load_receiver?(node) &&
                  unbound_module_owner?(@receiver_type.class_name)
        return if node.receiver.is_a?(IR::SelfRead) && implicit_method?(node.with(receiver: nil))

        raise CompilationError.new(code: "E_LOAD", message: "loading requires an unconditional file-level site",
                                   span: node.span)
      end

      def implicit_load_receiver?(node)
        node.receiver.nil? || node.receiver.is_a?(IR::SelfRead)
      end

      def kernel_load_receiver?(node)
        return true if implicit_load_receiver?(node)

        node.receiver.is_a?(IR::ConstantRead) && node.receiver.name == :Kernel && !resolve_constant(node.receiver)
      end

      def existing_constant?(name)
        @constants.key?(name) || (!name.to_s.include?("::") && Object.const_defined?(name, false))
      end

      def initialize_namespaces
        @classes = {}
        @superclasses = {}
        @namespace_kinds = {}
        @namespace_values = {}
        @constants = {}
        @constant_scopes = []
        @method_scopes = {}.compare_by_identity
        @includes = {}
        @prepends = {}
        @composed_modules = []
        @visibilities = {}
        @default_visibility = {}
      end

      def constructor_call?(node, type, target)
        namespace_type?(type) && node.name == :new && !target
      end

      def builtin_exception_receiver?(node)
        node.receiver.is_a?(IR::ConstantRead) && exception_class?(node.receiver.name) &&
          !resolve_constant(node.receiver)
      end
    end
  end
end
