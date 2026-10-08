# frozen_string_literal: true

module Rubast
  module Analysis
    module Collections
      # ponytail: track up to 10,000 slots; use an element summary if larger workloads need it.
      MAX_ARRAY_LENGTH = 10_000
      ARRAY_OPERATIONS = %i[length [] []= push << ! + == !=].freeze
      STRING_READS = %i[+ length bytesize dup chomp].freeze
      STRING_WRITES = %i[<< concat replace clear chomp!].freeze

      module Arrays
        private

        def validate_array(node, locals)
          unsupported(node) if !node.is_a?(IR::ParameterArray) && @loop_depth&.positive?
          unsupported(node) if node.elements.length > MAX_ARRAY_LENGTH
          names = (0...node.elements.length).to_a
          elements, types = validate_arguments(node.elements, names, locals)
          array = object_type(:Array, :nil)
          array.fields.merge!(types)
          set_array_length(array, elements.length, node)
          node.with(elements: elements, result_type: types.value?(:never) ? :never : array)
        end

        def set_array_length(array, length, origin)
          unsupported(origin) if length > MAX_ARRAY_LENGTH
          array.fields[:length] = integer_type(length, length, origin)
        end

        def array_length(array, origin)
          type = array.fields.fetch(:length)
          unsupported(origin) unless type.minimum == type.maximum
          type.minimum
        end

        def array_result(node, array, types)
          return array_metadata_type(node, array) if %i[length !].include?(node.name)
          return array_concat_type(array, types.fetch(0), node) if node.name == :+

          return array_equal_type(array, types.fetch(0), node) if %i[== !=].include?(node.name)
          return unknown_array_result(node, array, types) if array.fields[:length] == :unknown

          length = array_length(array, node)
          case node.name
          when :[] then array_read_type(types.fetch(0), array, length, node)
          when :[]= then array_write_type(types, array, length, node)
          when :push, :<< then array_push_type(types, array, length, node)
          else unsupported(node)
          end
        end

        def unknown_array_result(node, array, types)
          return array unless %i[[] []=].include?(node.name)

          index = types.fetch(0)
          unsupported(node) unless index == :unknown || index.is_a?(IR::IntegerType)
          node.name == :[]= ? types.fetch(1) : :unknown
        end

        def array_read_type(index, array, length, origin)
          unsupported(origin) unless index.is_a?(IR::IntegerType)
          range = index.minimum..index.maximum
          values = (0...length).filter_map do |slot|
            next unless range.cover?(slot) || range.cover?(slot - length)

            array.fields[slot]
          end
          values << :nil if index.minimum < -length || index.maximum >= length
          join_types(values, origin)
        end

        def array_write_type(types, array, length, origin)
          index = types.fetch(0)
          unsupported(origin) unless index.is_a?(IR::IntegerType) && index.minimum == index.maximum
          slot = index.minimum.negative? ? length + index.minimum : index.minimum
          return :never if slot.negative?

          set_array_length(array, [length, slot + 1].max, origin)
          (length...slot).each { |gap| array.fields[gap] = :nil }
          array.fields[slot] = types.fetch(1)
        end

        def array_push_type(types, array, length, origin)
          set_array_length(array, length + types.length, origin)
          types.each_value.with_index { |type, index| array.fields[length + index] = type }
          array
        end

        def validate_index_write(node, locals)
          receiver = validate_expression(node.receiver, locals)
          type = type_of(receiver, locals)
          unsupported(node) unless type == :unknown || array_type?(type) || hash_type?(type)
          call = IR::Call.new(name: :[]=, receiver: receiver, arguments: [node.index, node.value],
                              safe_navigation: false, span: node.span)
          return validate_collection_call(call, receiver, type, locals) if array_type?(type) || hash_type?(type)

          arguments, types = validate_arguments(call.arguments, [0, 1], locals)
          node.with(receiver: receiver, index: arguments.first, value: arguments.last,
                    result_type: continuing_type(arguments, locals, types.fetch(1)))
        end
      end

      include Arrays

      private

      def validate_collection_expression(node, locals)
        case node
        when IR::ArrayLiteral, IR::ParameterArray then validate_array(node, locals)
        when IR::HashLiteral, IR::ParameterHash then validate_hash(node, locals)
        else validate_index_write(node, locals)
        end
      end

      def safe_chomp_type(node, locals)
        type = type_of(node.receiver, locals)
        return :never if type == :never
        return :nil if members(type) == [:nil]

        members(type).intersect?(%i[nil unknown]) ? :string_or_nil : :string
      end

      def array_type?(type)
        type.is_a?(IR::ObjectType) && type.class_name == :Array
      end

      def string_type?(type)
        members(type).all? { |member| %i[string frozen_string].include?(member) }
      end

      def collection_call?(node, type)
        return true if array_type?(type) || hash_type?(type)

        string_type?(type) && (STRING_READS + STRING_WRITES).include?(node.name)
      end

      def collection_arity?(node, family)
        arity = case node.name
                when :length, :keys, :values, :bytesize, :dup, :chomp, :chomp!, :clear, :! then 0
                when :[]= then 2
                when :push then node.arguments.length if family == :array
                else 1
                end
        node.arguments.length == arity
      end

      def validate_collection_call(node, receiver, type, locals)
        family = collection_family(type)
        operations = family == :hash ? Hashes::HASH_OPERATIONS : ARRAY_OPERATIONS
        unsupported(node) if family != :string && !operations.include?(node.name)
        unsupported(node) unless collection_arity?(node, family)
        names = (0...node.arguments.length).to_a
        arguments, types = validate_arguments(node.arguments, names, locals)
        result = if types.value?(:never)
                   :never
                 else
                   collection_result(node, family, type, types)
                 end
        record_collection_errors(node, type, types, result, locals)
        IR::Builtin.new(family: family, name: node.name, receiver: receiver, arguments: arguments,
                        result_type: result, span: node.span)
      end

      def record_collection_errors(node, type, types, result, locals)
        return if types.value?(:never)

        if frozen_mutation?(node, type)
          record_exception(:FrozenError, locals, node)
        elsif array_type?(type) && node.name == :[]= && result == :never && !types.value?(:never)
          record_exception(:IndexError, locals, node)
        end
      end

      def frozen_mutation?(node, type)
        STRING_WRITES.include?(node.name) && members(type).include?(:frozen_string)
      end

      def collection_family(type)
        return :array if array_type?(type)

        hash_type?(type) ? :hash : :string
      end

      def collection_result(node, family, type, types)
        case family
        when :array then array_result(node, type, types)
        when :hash then hash_result(node, type, types)
        else string_result(node, type, types)
        end
      end

      def string_result(node, receiver_type, types)
        unsupported(node) unless types.values.all? { |type| type == :unknown || string_type?(type) }
        return :never if STRING_WRITES.include?(node.name) && members(receiver_type) == [:frozen_string]

        case node.name
        when :length, :bytesize then integer_type(0, Validator::MAX_INTEGER, node)
        when :chomp! then :string_or_nil
        else :string
        end
      end
    end
  end
end
