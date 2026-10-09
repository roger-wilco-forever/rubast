# frozen_string_literal: true

module Rubast
  module Analysis
    module StaticDispatch
      private

      def validate_user_builtin(node, receiver, type, locals)
        case node.name
        when :respond_to?, :instance_variable_get, :instance_variable_set
          validate_reflection_call(node, receiver, type, locals)
        when :nil? then validate_nil_predicate(node, receiver, type)
        else validate_identity(node, receiver, type, locals)
        end
      end

      def resolve_user_dispatch(node, type)
        target = lookup_method(type.class_name, node.name)
        return [node, target] if target && method_visible?(node, type, target)
        return resolve_static_send(node, type) if !target && node.name == :send

        resolve_missing_dispatch(node, type, target)
      end

      def resolve_static_send(node, type)
        name = node.arguments.first
        unsupported(node) unless name.is_a?(IR::SymbolLiteral) || name.is_a?(IR::StringLiteral)
        validate_literal(name)
        call = node.with(name: name.value.to_sym, arguments: node.arguments.drop(1).freeze, visibility: :send)
        unsupported(node) if call.name == :initialize
        target = lookup_method(type.class_name, call.name)
        call, target = resolve_missing_dispatch(call, type, target) unless target
        # shortcut: literal names select user methods/hooks; native send targets need their own contract.
        unsupported(node) unless target
        [call, target]
      end

      def resolve_missing_dispatch(node, type, target)
        native = native_method_visibility(type, node.name)
        return [node, target] if !target && native && method_visible?(node, type, nil)

        missing = lookup_method(type.class_name, :method_missing)
        return [node, target] unless missing

        name = IR::SymbolLiteral.new(value: node.name.to_s.encode(Encoding::UTF_8), span: node.span)
        [node.with(name: :method_missing, arguments: [name, *node.arguments].freeze, visibility: :send), missing]
      end

      def resolved_method_call(node, receiver, type, target, locals)
        owner, method = target
        invocation = validate_invocation(node, method, locals, type, owner: owner)
        IR::MethodCall.new(class_name: owner, name: node.name, receiver: receiver, **invocation,
                           result_type: invocation.fetch(:body).result_type, span: node.span)
      end
    end
  end
end
