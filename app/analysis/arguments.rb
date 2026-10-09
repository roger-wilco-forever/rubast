# frozen_string_literal: true

module Rubast
  module Analysis
    module Arguments
      private

      def prepare_arguments(node, method, locals, owner: nil)
        pack = call_payload(node, locals)
        bindings = bind_call_arguments(node, method, pack, owner) unless pack[:unknown]
        [pack[:arguments].freeze, pack[:types], bindings]
      end

      def bind_call_arguments(node, method, pack, owner)
        signature = method.signature
        inputs = pack[:positional].dup
        keywords = pack[:keywords]
        accepts = signature.any? { |item| %i[keyword keyword_rest].include?(item.kind) }
        inputs << parameter_hash(keywords, node.span) unless accepts || keywords.empty?
        error = arity_error(signature, inputs.length) || (keyword_error(signature, keywords) if accepts)
        return [argument_error(error, method, owner, node)] if error

        bind_positionals(signature, inputs) + (accepts ? bind_keywords(signature, keywords) : [])
      end

      module Positionals
        private

        def bind_positionals(signature, inputs)
          pairs = positional_pairs(signature, inputs)
          assigned, defaults = pairs.partition { |_, value| value }
          (assigned + defaults).map do |parameter, value|
            IR::LocalWrite.new(name: parameter.name, value: value || parameter.default, span: parameter.span)
          end
        end

        def parameters_of(signature, kind)
          signature.select { |item| item.kind == kind }
        end

        def positional_pairs(signature, inputs)
          leading = parameters_of(signature, :required)
          trailing = parameters_of(signature, :post)
          middle = inputs.drop(leading.length).take(inputs.length - leading.length - trailing.length)
          pairs = leading.zip(inputs.take(leading.length)) + trailing.zip(inputs.last(trailing.length))
          pairs + middle_pairs(signature, middle)
        end

        def middle_pairs(signature, middle)
          optional = parameters_of(signature, :optional)
          pairs = optional.zip(middle.take(optional.length))
          rest = signature.find { |item| item.kind == :rest }
          if rest
            array = IR::ParameterArray.new(elements: middle.drop(optional.length).freeze,
                                           result_type: nil, span: rest.span)
            pairs.unshift([rest, array])
          end
          pairs
        end

        def arity_error(signature, count)
          minimum = parameters_of(signature, :required).length + parameters_of(signature, :post).length
          maximum = minimum + parameters_of(signature, :optional).length
          rest = signature.any? { |item| item.kind == :rest }
          return if count >= minimum && (rest || count <= maximum)

          expected = expected_arity(minimum, maximum, rest) + required_keyword_suffix(signature)
          "wrong number of arguments (given #{count}, expected #{expected})"
        end

        def expected_arity(minimum, maximum, rest)
          return "#{minimum}+" if rest

          minimum == maximum ? minimum.to_s : "#{minimum}..#{maximum}"
        end

        def required_keyword_suffix(signature)
          required = parameters_of(signature, :keyword).reject(&:default).map(&:name)
          return "" if required.empty?

          suffix = required.one? ? "keyword" : "keywords"
          "; required #{suffix}: #{required.join(', ')}"
        end
      end

      module Keywords
        private

        def keyword_error(signature, values)
          named = parameters_of(signature, :keyword)
          required = named.reject(&:default).map { |item| [:symbol, item.name.to_s] }
          missing = required - values.keys
          return keyword_message("missing", missing) unless missing.empty?
          return if signature.any? { |item| item.kind == :keyword_rest }

          extras = values.keys - named.map { |item| [:symbol, item.name.to_s] }
          keyword_message("unknown", extras) unless extras.empty?
        end

        def keyword_message(kind, keys)
          names = keys.map { |key| key.first == :symbol ? key.last.to_sym.inspect : key.last.inspect }
          suffix = keys.one? ? "keyword" : "keywords"
          "#{kind} #{suffix}: #{names.join(', ')}"
        end

        def bind_keywords(signature, values)
          remaining = values.dup
          pairs = signature.filter_map do |item|
            next unless item.kind == :keyword

            [item, remaining.delete([:symbol, item.name.to_s])]
          end
          rest = signature.find { |item| item.kind == :keyword_rest }
          pairs << [rest, parameter_hash(remaining, rest.span)] if rest
          assigned, defaults = pairs.partition { |_, value| value }
          (assigned + defaults).map do |item, value|
            IR::LocalWrite.new(name: item.name, value: value || item.default, span: item.span)
          end
        end

        def parameter_hash(values, span)
          elements = values.flat_map { |key, value| [argument_key(key, span), value] }
          IR::ParameterHash.new(elements: elements.freeze, result_type: nil, span: span)
        end
      end

      module Entries
        private

        def validate_output(node, locals)
          value = validate_scalar(node, locals)
          unsupported(node) if block_type?(type_of(value, locals)) || members(type_of(value, locals)).any? do |type|
            io_type?(type)
          end
          value
        end

        def deferred_invocation(method, receiver, owner, prepared, origin)
          arguments, parameters = prepared
          unsupported(origin) unless @checking_unused
          unsupported(origin) if @active_methods.include?([receiver.class_name, owner, method.name])
          body = IR::Sequence.new(expressions: [].freeze, result_type: :unknown, span: origin.span)
          { arguments: arguments.freeze, parameters: parameters.keys.freeze,
            locals: (method.locals + parameters.keys).uniq.freeze, body: body }
        end

        def argument_error(message, method, owner, origin)
          label = owner == :BasicObject ? "BasicObject#initialize" : method.name.to_s
          IR::CallError.new(class_name: :ArgumentError, message: message, label: method.native ? :caller : label,
                            result_type: :never, span: method.native ? origin.span : method.span)
        end

        def validate_call_error(node, locals)
          record_exception(node.class_name, locals, node)
          node
        end

        def entry_body(method, bindings)
          return method.body if !bindings || bindings.empty?
          return bindings.first if bindings.first.is_a?(IR::CallError)

          IR::Sequence.new(expressions: [*bindings, method.body].freeze, result_type: nil, span: method.span)
        end

        def validate_method_body(method, parameters, receiver, origin = method, **context)
          body = with_dead_call_effects(parameters, {}) do
            checked_method_body(method, parameters, receiver, origin, **context)
          end
          parameters.value?(:never) ? body.with(result_type: :never) : body
        end

        def checked_entry_body(method, context, locals)
          check_parameter_defaults(method, locals) unless context[:bindings]
          bindings = context[:bindings]
          if bindings && !bindings.first.is_a?(IR::CallError)
            bindings = block_binding(method, context[:block]) + bindings
          end
          validate_expression(entry_body(method, bindings), locals)
        end

        def block_binding(method, context)
          parameter = method.signature.find { |item| item.kind == :block }
          return [] unless parameter

          value = if context
                    IR::BlockValue.new(id: context.fetch(:id), span: parameter.span)
                  else
                    IR::NilLiteral.new(span: parameter.span)
                  end
          [IR::LocalWrite.new(name: parameter.name, value: value, span: parameter.span)]
        end

        def check_parameter_defaults(method, locals)
          method.signature.each do |parameter|
            next unless parameter.default

            before = snapshot(locals)
            counts = flow_exit_counts
            validate_expression(parameter.default, locals)
            restore(before, locals)
            restore_flow_exits(counts)
          end
        end
      end

      module Forwarding
        private

        def forwarded_arguments(method, span)
          positional = []
          keywords = []
          method.signature.each do |item|
            value = IR::LocalRead.new(name: item.name, span: span)
            case item.kind
            when :block then next
            when :rest then positional << IR::ArgumentSplat.new(kind: :array, value: value, span: span)
            when :keyword
              key = IR::SymbolLiteral.new(value: item.name.to_s.encode(Encoding::UTF_8), span: span)
              keywords << IR::ParameterHash.new(elements: [key, value].freeze, result_type: nil, span: span)
            when :keyword_rest then keywords << IR::ArgumentSplat.new(kind: :hash, value: value, span: span)
            else positional << value
            end
          end
          positional << IR::Keywords.new(parts: keywords.freeze, span: span) unless keywords.empty?
          positional.freeze
        end

        def default_initializer(node)
          IR::MethodDefinition.new(name: :initialize, parameters: [].freeze, locals: [].freeze,
                                   body: IR::Sequence.new(expressions: [].freeze, result_type: :nil, span: node.span),
                                   span: node.span)
        end
      end

      include Positionals
      include Keywords
      include Entries
      include Forwarding
    end
  end
end
