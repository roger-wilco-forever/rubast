# frozen_string_literal: true

module Rubast
  module Analysis
    module Modules
      module Lookup
        private

        def method_ancestors(key)
          return [] unless key

          [*@prepends.fetch(key, []), key, *@includes.fetch(key, []), *method_ancestors(@superclasses[key])]
        end

        def lookup_method(class_name, name, start: 0)
          method_ancestors(class_name).each_with_index do |key, index|
            next if index < start

            method = @classes.fetch(key)[name]
            return [IR::MethodOwner.new(key: key, index: index), method] if method
          end
          nil
        end

        def constant_ancestors(key)
          return [] unless key

          [key, *@prepends.fetch(key, []), *@includes.fetch(key, []), *constant_ancestors(@superclasses[key])]
        end
      end

      module Composition
        private

        def composition_call?(node)
          @definition_owner && %i[include extend
                                  prepend].include?(node.name) && !lookup_method(@receiver_type.class_name, node.name)
        end

        def composition_receiver(call, locals)
          check_namespace_declaration(call)
          supported = [IR::SelfRead, IR::ConstantRead, IR::ConstantPath, IR::LocalRead]
          unsupported(call) if call.receiver && supported.none? { |kind| call.receiver.is_a?(kind) }
          receiver = validate_expression(call.receiver || IR::SelfRead.new(result_type: nil, span: call.span), locals)
          unsupported(call) unless type_of(receiver, locals).equal?(@namespace_values.fetch(@definition_owner))
          receiver
        end

        def validate_composition(call, locals)
          unsupported(call) if call.safe_navigation || call.arguments.empty?
          receiver = composition_receiver(call, locals)
          type = type_of(receiver, locals)
          arguments = call.arguments.map { |argument| validate_expression(argument, locals) }
          names = arguments.map { |argument| composition_name(type_of(argument, locals), call) }
          owner = call.name == :extend ? type.class_name : @definition_owner
          unsupported(call) if @composed_modules.include?(owner)
          names.reverse_each { |name| include_module(owner, name, call, prepend: call.name == :prepend) }
          IR::Sequence.new(expressions: [receiver, *arguments, receiver].freeze, result_type: type, span: call.span)
        end

        def composition_name(type, origin)
          unsupported(origin) unless namespace_type?(type) && @namespace_kinds[type.class_name.name] == :module
          type.class_name.name
        end

        def include_module(owner, name, origin, prepend:)
          unsupported(origin) if method_ancestors(name).include?(owner)
          singleton = IR::SingletonClass.new(name: name)
          callbacks = %i[included extended prepended append_features extend_object prepend_features]
          unsupported(origin) if callbacks.any? { |hook| lookup_method(singleton, hook) }
          @composed_modules << name
          list = ((prepend ? @prepends : @includes)[owner] ||= [])
          inherited = prepend ? [] : method_ancestors(@superclasses[owner])
          insert_ancestors(list, method_ancestors(name), inherited)
        end

        def insert_ancestors(list, names, inherited)
          cursor = 0
          names.each do |key|
            existing = list.index(key)
            if existing
              cursor = existing + 1
            elsif !inherited.include?(key)
              list.insert(cursor, key)
              cursor += 1
            end
          end
        end
      end

      module SuperCalls
        private

        def super_target(current)
          owner = @method_context.first
          chain = method_ancestors(@receiver_type.class_name)
          index = owner.is_a?(IR::MethodOwner) ? owner.index : chain.index(owner)
          lookup_method(@receiver_type.class_name, current.name, start: index + 1)
        end

        def unbound_module_owner?(owner)
          key = owner.is_a?(IR::MethodOwner) ? owner.key : owner
          @checking_unused && @namespace_kinds[key] == :module
        end

        def validate_super(node, locals)
          unsupported(node) unless @method_context
          owner, current = @method_context
          arguments = node.forward_arguments ? forwarded_arguments(current, node.span) : node.arguments
          call = IR::Call.new(name: current.name, receiver: nil, arguments: arguments,
                              safe_navigation: false, span: node.span)
          target = super_target(current)
          if !target && unbound_module_owner?(owner)
            return defer_call(call, IR::SelfRead.new(result_type: :unknown, span: node.span), locals)
          end

          unsupported(node) unless target || current.name == :initialize
          receiver = IR::SelfRead.new(result_type: @receiver_type, span: node.span)
          validate_super_invocation(node, call, receiver, target || [:BasicObject, default_initializer(call)], locals)
        end
      end

      include Lookup
      include Composition
      include SuperCalls
    end
  end
end
