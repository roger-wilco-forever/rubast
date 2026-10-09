# frozen_string_literal: true

module Rubast
  module Analysis
    module CallArguments
      private

      def validate_arguments(nodes, names, locals)
        types = {}
        dead = nil
        arguments = nodes.zip(names).map do |node, name|
          value = block_given? ? yield(node) : validate_expression(node, locals)
          types[name] = type_of(value, locals)
          unsupported(node) if block_type?(types[name])
          dead = argument_state(types[name], dead, locals)
          value
        end
        [arguments.freeze, types]
      end

      def call_payload(node, locals)
        pack = { arguments: [], types: {}, positional: [], keywords: {}, unknown: false }
        node.arguments.each do |argument|
          if argument.is_a?(IR::Keywords)
            argument.parts.each { |part| collect_keywords(part, pack, locals, node) }
          else
            collect_positional(argument, pack, locals, node)
          end
        end
        pack
      end

      def collect_positional(node, pack, locals, origin)
        value = call_argument(node, locals, origin)
        type = type_of(value, locals)
        unsupported(node) if block_type?(type)
        if node.is_a?(IR::ArgumentSplat)
          length = %i[unknown never].include?(type) ? 0 : array_length(type, node)
          pack[:unknown] ||= type == :unknown
          reference = call_input(value, [:array, length].freeze, pack, locals, origin)
          pack[:positional].concat(length.times.map { |index| argument_index(reference, index, origin.span) })
        else
          pack[:positional] << call_input(value, :positional, pack, locals, origin)
        end
      end

      def collect_keywords(node, pack, locals, origin)
        value = call_argument(node, locals, origin)
        type = type_of(value, locals)
        unsupported(node) if block_type?(type)
        keys = keyword_keys(type, node)
        pack[:unknown] ||= type == :unknown
        reference = call_input(value, [:keywords, keys].freeze, pack, locals, origin)
        keys.each { |key| pack[:keywords][key] = argument_hash_index(reference, key, origin.span) }
      end

      def keyword_keys(type, origin)
        return [] if %i[unknown never].include?(type)

        shapes = hash_shapes(type)
        unsupported(origin) unless shapes.one?
        shapes.first.keys
      end

      def call_argument(node, locals, origin)
        return validate_expression(node, locals) unless node.is_a?(IR::ArgumentSplat)

        validate_argument_copy(node, locals, origin)
      end

      def call_input(value, descriptor, pack, locals, origin)
        name = [:argument, pack[:arguments].length, descriptor].freeze
        pack[:arguments] << value
        pack[:types][name] = type_of(value, locals)
        pack[:dead] = argument_state(pack[:types][name], pack[:dead], locals)
        IR::LocalRead.new(name: name, span: origin.span)
      end

      def argument_state(type, dead, locals)
        if dead
          state, counts = dead
          restore(state, locals)
          restore_flow_exits(counts)
          dead
        elsif type == :never
          [snapshot(locals), flow_exit_counts]
        end
      end

      def with_dead_call_effects(types, locals)
        state = snapshot(locals) if types.value?(:never)
        counts = flow_exit_counts if state
        yield
      ensure
        if state
          restore(state, locals)
          restore_flow_exits(counts)
        end
      end

      def argument_index(reference, index, span)
        key = IR::IntegerLiteral.new(value: index, span: span)
        IR::Call.new(name: :[], receiver: reference, arguments: [key].freeze, safe_navigation: false, span: span)
      end

      def argument_hash_index(reference, key, span)
        IR::Call.new(name: :[], receiver: reference, arguments: [argument_key(key, span)].freeze,
                     safe_navigation: false, span: span)
      end

      module Copies
        private

        def validate_argument_copy(node, locals, origin)
          value = validate_expression(node.value, locals)
          type = type_of(value, locals)
          unsupported(node) if block_type?(type)
          return invalid_keyword_splat(value, type, locals, origin) if node.kind == :hash && !hash_copy_type?(type)

          result = copied_argument_type(node.kind, type, node)
          IR::ArgumentCopy.new(kind: node.kind, value: value, result_type: result, span: node.span)
        end

        def hash_copy_type?(type)
          %i[unknown never nil].include?(type) || hash_type?(type)
        end

        def copied_argument_type(kind, type, origin)
          return type if %i[unknown never].include?(type)

          return build_hash([], {}, origin) if kind == :hash && type == :nil

          return copy_argument_object(type) if kind == :hash || array_type?(type)

          copy_argument_scalar(type, origin)
        end

        def copy_argument_scalar(type, origin)
          unsupported(origin) if type.is_a?(IR::ObjectType) && lookup_method(type.class_name, :to_a)
          array = object_type(:Array, :nil)
          array.fields[0] = type unless type == :nil
          set_array_length(array, type == :nil ? 0 : 1, origin)
          array
        end

        def copy_argument_object(type)
          copy = object_type(type.class_name, :nil)
          copy.fields.replace(type.fields.dup)
          copy
        end

        def invalid_keyword_splat(value, type, locals, origin)
          name = case type
                 when IR::IntegerType then "Integer"
                 when :boolean
                   unsupported(origin) unless value.is_a?(IR::BooleanLiteral)
                   value.value.to_s
                 when :string, :frozen_string then "String"
                 when IR::SymbolType then "Symbol"
                 else unsupported(origin)
                 end
          error = IR::CallError.new(class_name: :TypeError, message: "no implicit conversion of #{name} into Hash",
                                    label: nil, result_type: :never, span: origin.span)
          validate_call_error(error, locals)
          IR::Sequence.new(expressions: [value, error].freeze, result_type: :never, span: origin.span)
        end
      end

      include Copies
    end
  end
end
