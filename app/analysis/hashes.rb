# frozen_string_literal: true

module Rubast
  module Analysis
    module Hashes
      # ponytail: bound enumerated insertion orders; summarize shapes if branching workloads need more.
      MAX_SHAPES = 32
      HASH_OPERATIONS = %i[[] []= key? length keys values !].freeze

      module Shapes
        private

        def hash_type?(type)
          type.is_a?(IR::ObjectType) && type.class_name == :Hash
        end

        def hash_key(type, origin, expression = nil)
          return [:string, expression.value].freeze if expression.is_a?(IR::StringLiteral)

          case type
          when IR::SymbolType then [:symbol, type.name].freeze
          when IR::IntegerType
            unsupported(origin) unless type.minimum == type.maximum
            [:integer, type.minimum].freeze
          else unsupported(origin)
          end
        end

        def hash_key_type(key)
          if key.first == :string
            :frozen_string
          elsif key.first == :symbol
            IR::SymbolType.new(name: key.last)
          else
            IR::IntegerType.new(minimum: key.last,
                                maximum: key.last)
          end
        end

        def hash_shapes(hash)
          members(hash.fields.fetch(:shape))
        end

        def argument_key(key, span)
          case key.first
          when :symbol then IR::SymbolLiteral.new(value: key.last.encode(Encoding::UTF_8), span: span)
          when :string then IR::StringLiteral.new(value: key.last, frozen: true, span: span)
          else IR::IntegerLiteral.new(value: key.last, span: span)
          end
        end

        def write_hash(hash, key, value, origin)
          if key == :unknown || hash.fields[:shape] == :unknown
            hash.fields[:shape] = :unknown
          else
            shapes = hash_shapes(hash).map do |shape|
              keys = shape.keys.include?(key) ? shape.keys : [*shape.keys, key].freeze
              unsupported(origin) if keys.length > Collections::MAX_ARRAY_LENGTH
              IR::HashShape.new(keys: keys)
            end
            hash.fields[:shape] = join_types(shapes, origin)
            hash.fields[key] = value
          end
          value
        end
      end

      include Shapes

      private

      def check_hash_shapes(types, origin)
        unsupported(origin) if types.grep(IR::HashShape).uniq.length > MAX_SHAPES
      end

      def explicit_loop_hash?(node)
        loop_allocation? && !node.is_a?(IR::ParameterHash)
      end

      def validate_hash(node, locals)
        unsupported(node) if explicit_loop_hash?(node)
        unsupported(node) if node.elements.length > Collections::MAX_ARRAY_LENGTH * 2
        names = (0...node.elements.length).to_a
        elements, types = validate_arguments(node.elements, names, locals)
        keys = (0...elements.length).step(2).map do |index|
          type = types.fetch(index)
          %i[unknown never].include?(type) ? type : hash_key(type, node, elements[index])
        end
        result = if types.value?(:never)
                   :never
                 else
                   build_hash(keys, types, node)
                 end
        node.with(elements: elements, result_type: result)
      end

      def build_hash(keys, types, origin)
        return :unknown if keys.include?(:unknown)

        hash = object_type(:Hash, :nil)
        hash.fields[:shape] = IR::HashShape.new(keys: [].freeze)
        keys.each_with_index { |key, index| write_hash(hash, key, types.fetch((index * 2) + 1), origin) }
        hash
      end

      def hash_result(node, hash, types)
        case node.name
        when :! then :boolean
        when :length then hash_length(hash, node)
        when :keys, :values then hash_array(hash, node)
        else hash_index_result(node, hash, types)
        end
      end

      def hash_length(hash, origin)
        return :unknown if hash.fields[:shape] == :unknown

        lengths = hash_shapes(hash).map { |shape| shape.keys.length }
        integer_type(lengths.min, lengths.max, origin)
      end

      def hash_index_result(node, hash, types)
        type = types.fetch(0)
        return dynamic_string_lookup(node, hash) if dynamic_string_key?(node, type)

        key = type == :unknown ? :unknown : hash_key(type, node, node.arguments.first)
        return write_hash(hash, key, types.fetch(1), node) if node.name == :[]=
        return :boolean if node.name == :key?

        key == :unknown || hash.fields[:shape] == :unknown ? :unknown : hash.fields[key]
      end

      def dynamic_string_key?(node, type)
        node.name != :[]= && string_type?(type) && !node.arguments.first.is_a?(IR::StringLiteral)
      end

      def dynamic_string_lookup(node, hash)
        return :boolean if node.name == :key?
        return :unknown if hash.fields[:shape] == :unknown

        keys = hash_shapes(hash).flat_map(&:keys).uniq.select { |key| key.first == :string }
        join_types([:nil, *keys.map { |key| hash.fields[key] }], node)
      end

      def hash_array(hash, node)
        unsupported(node) if loop_allocation?
        return :unknown if hash.fields[:shape] == :unknown

        shapes = hash_shapes(hash)
        unsupported(node) unless shapes.one?
        keys = shapes.first.keys
        array = object_type(:Array, :nil)
        keys.each_with_index do |key, index|
          array.fields[index] = node.name == :keys ? hash_key_type(key) : hash.fields[key]
        end
        set_array_length(array, keys.length, node)
        array
      end
    end
  end
end
