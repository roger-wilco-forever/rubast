# frozen_string_literal: true

module Rubast
  module Analysis
    module RegistryOperations
      module Arrays
        private

        def array_concat_type(left, right, origin)
          unsupported(origin) if @loop_depth&.positive? || !array_type?(right)
          first = array_length(left, origin)
          second = array_length(right, origin)
          result = object_type(:Array, :nil)
          set_array_length(result, first + second, origin)
          first.times { |index| result.fields[index] = left.fields.fetch(index) }
          second.times { |index| result.fields[first + index] = right.fields.fetch(index) }
          result
        end

        def array_metadata_type(node, array)
          node.name == :length ? array.fields.fetch(:length) : :boolean
        end

        def array_value_type(node, left, right)
          node.name == :+ ? array_concat_type(left, right, node) : array_equal_type(left, right, node)
        end

        def array_equal_type(left, right, origin)
          check_array_equality(left, origin)
          check_array_equality(right, origin)
          :boolean
        end

        def check_array_equality(type, origin, path = [])
          members(type).each do |item|
            unsupported(origin) if item.is_a?(IR::ExceptionType)
            next if item == :unknown || !item.is_a?(IR::ObjectType)

            unsupported(origin) unless array_type?(item) && !path.include?(item.object_id)
            array_length(item, origin).times do |index|
              check_array_equality(item.fields.fetch(index), origin, [*path, item.object_id])
            end
          end
        end
      end

      module Predicates
        private

        def validate_nil_predicate(node, receiver, type)
          unsupported(node) unless node.arguments.empty?
          values = members(type)
          known = values.include?(:unknown) || (values.include?(:nil) && values.length > 1) ? nil : type == :nil
          IR::NilCheck.new(receiver: receiver, known: known,
                           result_type: type == :never ? :never : :boolean, span: node.span)
        end

        def known_predicate(node)
          node.known if node.is_a?(IR::NilCheck)
        end

        def validate_known_conditional(node, predicate, locals)
          before = snapshot(locals)
          live, dead = if known_predicate(predicate)
                         [node.consequent, node.alternative]
                       else
                         [node.alternative, node.consequent]
                       end
          active = validate_expression(live, locals)
          after = snapshot(locals)
          exits = flow_exit_counts
          restore(before, locals)
          inactive = validate_expression(dead, locals)
          restore(after, locals)
          restore_flow_exits(exits)
          branches = known_predicate(predicate) ? [active, inactive] : [inactive, active]
          node.with(predicate: predicate, consequent: branches.first, alternative: branches.last,
                    result_type: active.result_type)
        end
      end

      include Arrays
      include Predicates

      private

      def validate_p(node, locals)
        unsupported(node) unless node.arguments.one? && node.receiver.nil? && !node.safe_navigation
        value = validate_expression(node.arguments.first, locals)
        type = type_of(value, locals)
        supported = members(type).all? { |member| member.is_a?(IR::IntegerType) || %i[nil boolean unknown never].include?(member) }
        unsupported(node) unless supported
        IR::Print.new(value: value, result_type: type, span: node.span)
      end
    end
  end
end
