# frozen_string_literal: true

module Rubast
  module Analysis
    module Reflection
      module Responding
        private

        def reflective_response(node, receiver, scope, name, values)
          visibility = method_visibility(type_of(receiver, scope), name.to_sym)
          flag = values[1] || IR::BooleanLiteral.new(value: false, span: node.span)
          unsupported(node) unless members(type_of(flag, scope)).all? { |item| inspectable_type?(item) }
          body = if visibility == :public
                   IR::BooleanLiteral.new(value: true, span: node.span)
                 elsif visibility
                   private_reflective_response(node, receiver, scope, name, flag)
                 else
                   missing_reflective_response(node, receiver, scope, name, flag)
                 end
          signature = [visibility, @source_symbols.include?(name)].freeze
          IR::Reflection.new(name: :respond_to?, body: body, signature: signature,
                             result_type: type_of(body, scope), span: node.span)
        end

        def private_reflective_response(node, receiver, scope, name, flag)
          before = snapshot(scope)
          missing = missing_reflective_response(node, receiver, scope, name, flag)
          after = snapshot(scope)
          restore(before, scope)
          states = type_of(missing, scope) == :never ? [before] : [before, after]
          merge_states(states, scope, node)
          IR::Conditional.new(predicate: flag, consequent: IR::BooleanLiteral.new(value: true, span: node.span),
                              alternative: missing, result_type: :boolean, span: node.span)
        end

        def missing_reflective_response(node, receiver, scope, name, flag)
          unless lookup_method(type_of(receiver, scope).class_name, :respond_to_missing?)
            return IR::BooleanLiteral.new(value: false, span: node.span)
          end

          known = @source_symbols.include?(name) || method_visibility(type_of(receiver, scope), name.to_sym)
          if node.arguments.first.is_a?(IR::StringLiteral) && !known
            # shortcut: ambiguous native identifier state is rejected; wider startup environments need a contract.
            unsupported(node) if NativeMethods::DATA.fetch("symbols").include?(name)
            return promoted_reflective_response(node, receiver, scope, name, flag) if name.start_with?("@")

            return reflection_hook(node, receiver, scope, name, flag)
          end
          boolean_response(reflection_hook(node, receiver, scope, name, boolean_flag(flag, node.span)), scope,
                           node.span)
        end

        def promoted_reflective_response(node, receiver, scope, name, flag)
          before = snapshot(scope)
          consequent = boolean_response(reflection_hook(node, receiver, scope, name,
                                                        boolean_flag(flag, node.span)), scope, node.span)
          first = snapshot(scope)
          restore(before, scope)
          alternative = reflection_hook(node, receiver, scope, name, flag)
          second = snapshot(scope)
          states = []
          states << first unless type_of(consequent, scope) == :never
          states << second unless type_of(alternative, scope) == :never
          restore(before, scope)
          merge_states(states, scope, node)
          predicate = IR::Reflection.new(name: :identifier_known, body: nil, signature: name,
                                         result_type: :boolean, span: node.span)
          IR::Conditional.new(predicate: predicate, consequent: consequent, alternative: alternative,
                              result_type: join_types([type_of(consequent, scope), type_of(alternative, scope)], node),
                              span: node.span)
        end

        def boolean_response(body, scope, span)
          result = type_of(body, scope) == :never ? :never : :boolean
          negate = IR::Operation.new(name: :!, operands: [body].freeze, result_type: result, span: span)
          IR::Operation.new(name: :!, operands: [negate].freeze, result_type: result, span: span)
        end

        def boolean_flag(flag, span)
          negate = IR::Call.new(name: :!, receiver: flag, arguments: [], safe_navigation: false, span: span)
          negate.with(receiver: negate)
        end

        def reflection_hook(node, receiver, scope, name, flag)
          symbol = IR::SymbolLiteral.new(value: name, span: node.span)
          call = IR::Call.new(name: :respond_to_missing?, receiver: receiver, arguments: [symbol, flag].freeze,
                              safe_navigation: false, span: node.span, visibility: :send)
          validate_method_call(call, scope)
        end
      end

      module Fields
        private

        def reflective_field(node, receiver, scope, name, values)
          type = type_of(receiver, scope)
          unsupported(node) unless /\A@[[:alpha:]_][[:alnum:]_]*\z/.match?(name)
          if node.name == :instance_variable_set
            value = type_of(values.last, scope)
            unsupported(node) if block_type?(value)
            type.fields[name.to_sym] = value unless value == :never
          end
          result = continuing_type(values, scope, type.fields[name.to_sym])
          body = IR::Builtin.new(family: :reflection, name: node.name, receiver: receiver,
                                 arguments: values.freeze, result_type: result, span: node.span)
          IR::Reflection.new(name: node.name, body: body, signature: name, result_type: result, span: node.span)
        end
      end

      include Responding
      include Fields

      private

      def validate_reflection_call(node, receiver, type, locals)
        name = reflection_selector(node)
        arguments, scope, names, reference = reflection_arguments(node, receiver, type, locals)
        values = names.drop(1).map { |key| IR::LocalRead.new(name: key, span: node.span) }
        types = scope.slice(*names)
        body = with_dead_call_effects(types, locals) do
          if node.name == :respond_to?
            reflective_response(node, reference, scope, name.value, values)
          else
            reflective_field(node, reference, scope, name.value, values)
          end
        end
        IR::ArgumentEvaluation.new(arguments: arguments, names: names, body: body,
                                   result_type: continuing_type(arguments, locals, body.result_type), span: node.span)
      end

      def reflection_selector(node)
        limits = case node.name
                 when :respond_to? then (1..2)
                 when :instance_variable_set then [2]
                 else [1]
                 end
        unsupported(node) unless limits.include?(node.arguments.length)
        name = node.arguments.first
        unsupported(node) unless name.is_a?(IR::StringLiteral) || name.is_a?(IR::SymbolLiteral)
        name
      end

      def reflection_arguments(node, receiver, type, locals)
        names = node.arguments.each_index.map { |index| [:reflection, index].freeze }
        arguments, types = validate_arguments(node.arguments, names, locals)
        receiver_name = %i[reflection receiver].freeze
        scope = locals.merge(types).merge(receiver_name => type)
        reference = IR::LocalRead.new(name: receiver_name, span: node.span)
        [[receiver, *arguments].freeze, scope, [receiver_name, *names].freeze, reference]
      end
    end
  end
end
