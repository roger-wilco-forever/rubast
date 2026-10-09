# frozen_string_literal: true

module Rubast
  module Analysis
    module StaticDispatch
      private

      def validate_user_builtin(node, receiver, type, locals)
        case node.name
        when :send then validate_static_send(node, receiver, type, locals)
        when :nil? then validate_nil_predicate(node, receiver, type)
        else validate_identity(node, receiver, type, locals)
        end
      end

      def validate_static_send(node, receiver, type, locals)
        name = node.arguments.first
        unsupported(node) unless name.is_a?(IR::SymbolLiteral) || name.is_a?(IR::StringLiteral)
        validate_literal(name)
        call = node.with(name: name.value.to_sym, arguments: node.arguments.drop(1).freeze)
        target = lookup_method(type.class_name, call.name)
        # shortcut: literal names select user methods only; broader dispatch needs its own Ruby contract.
        unsupported(node) unless target && call.name != :initialize
        resolved_method_call(call, receiver, type, target, locals)
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
