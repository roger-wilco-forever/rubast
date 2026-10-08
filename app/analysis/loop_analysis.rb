# frozen_string_literal: true

module Rubast
  module Analysis
    module LoopAnalysis
      module States
        private

        def loop_maps(state)
          [state.fetch(:locals), *state.fetch(:fields).values.map(&:last), *state.fetch(:captures).map(&:last)]
        end

        def same_loop_state?(first, second)
          return false unless first.fetch(:fields).keys == second.fetch(:fields).keys

          loop_maps(first).zip(loop_maps(second)).all? do |left, right|
            left.keys == right.keys && left.keys.all? { |key| same_loop_type?(left[key], right[key]) }
          end
        end

        def same_loop_type?(left, right)
          left.is_a?(IR::ObjectType) ? left.equal?(right) : left == right
        end

        def widen_loop_state(previous, current)
          loop_maps(previous).zip(loop_maps(current)).each do |old, new|
            new.each do |name, type|
              before = old[name]
              next unless before.is_a?(IR::IntegerType) && type.is_a?(IR::IntegerType)

              new[name] = IR::IntegerType.new(
                minimum: type.minimum < before.minimum ? Validator::MIN_INTEGER : type.minimum,
                maximum: type.maximum > before.maximum ? Validator::MAX_INTEGER : type.maximum
              )
            end
          end
          current
        end

        def loop_exit_lists
          [@loop_context&.fetch(:break), @loop_context&.fetch(:next), *block_exit_lists].compact
        end

        def validate_loop_exit(node, locals)
          return validate_block_exit(node, locals) unless @loop_context

          unsupported(node) unless @loop_context && !@loop_context.fetch(:predicate)
          value = validate_expression(node.value, locals)
          type = type_of(value, locals)
          @loop_context.fetch(node.kind) << [type, snapshot(locals)] unless type == :never
          node.with(value: value)
        end
      end

      module Bounds
        INVERSE = { :< => :>=, :<= => :>, :> => :<=, :>= => :< }.freeze

        private

        def loop_truth(node)
          case node
          when IR::BooleanLiteral then node.value
          when IR::NilLiteral, IR::Puts then false
          when IR::StringLiteral, IR::IntegerLiteral then true
          when IR::LocalWrite, IR::InstanceWrite then loop_truth(node.value)
          when IR::Sequence then node.expressions.empty? ? false : loop_truth(node.expressions.last)
          end
        end

        def constrain_loop_guard?(predicate, truth, locals)
          return true unless predicate.is_a?(IR::Operation) && INVERSE.key?(predicate.name)

          variable, bound = predicate.operands
          return true unless bound.is_a?(IR::IntegerLiteral)

          map = loop_variable_map(variable, locals)
          return true unless map && map[variable.name].is_a?(IR::IntegerType)

          operator = truth ? predicate.name : INVERSE.fetch(predicate.name)
          narrow_loop_integer?(map, variable.name, operator, bound.value)
        end

        def loop_variable_map(variable, locals)
          case variable
          when IR::LocalRead then locals
          when IR::InstanceRead then @receiver_type.fields
          end
        end

        def narrow_loop_integer?(map, name, operator, bound)
          type = map[name]
          minimum = type.minimum
          maximum = type.maximum
          case operator
          when :< then maximum = [maximum, bound - 1].min
          when :<= then maximum = [maximum, bound].min
          when :> then minimum = [minimum, bound + 1].max
          when :>= then minimum = [minimum, bound].max
          end
          return false if minimum > maximum

          map[name] = IR::IntegerType.new(minimum: minimum, maximum: maximum)
          true
        end

        def loop_guard_states(predicate, node, locals)
          return [nil, nil] if type_of(predicate, locals) == :never

          state = snapshot(locals)
          continue_truth = !node.until_loop
          truth = loop_truth(predicate)
          continuing = snapshot(locals) if truth != !continue_truth && constrain_loop_guard?(predicate, continue_truth,
                                                                                             locals)
          restore(state, locals)
          ending = snapshot(locals) if truth != continue_truth && constrain_loop_guard?(predicate, !continue_truth,
                                                                                        locals)
          restore(state, locals)
          [continuing, ending]
        end
      end

      module Iterations
        private

        def loop_iteration(node, locals)
          @loop_context = { break: [], next: [], predicate: false }
          node.post_test ? loop_post_iteration(node, locals) : loop_pre_iteration(node, locals)
        end

        def loop_predicate(node, locals)
          @loop_context[:predicate] = true
          validate_scalar(node.predicate, locals)
        ensure
          @loop_context[:predicate] = false
        end

        def loop_pre_iteration(node, locals)
          predicate = loop_predicate(node, locals)
          continuing, ending = loop_guard_states(predicate, node, locals)
          restore(continuing, locals) if continuing
          exit_counts = flow_exit_counts
          body = validate_expression(node.body, locals)
          back = loop_back_states(body, locals)
          unless continuing
            back = []
            @loop_context[:break].clear
            restore_flow_exits(exit_counts)
          end
          [node.with(predicate: predicate, body: body), back, ending]
        end

        def loop_post_iteration(node, locals)
          body = validate_expression(node.body, locals)
          back = loop_back_states(body, locals)
          merge_states(back, locals, node)
          exit_counts = flow_exit_counts
          predicate = loop_predicate(node, locals)
          continuing, ending = loop_guard_states(predicate, node, locals)
          if back.empty?
            continuing = ending = nil
            restore_flow_exits(exit_counts)
          end
          [node.with(predicate: predicate, body: body), [continuing].compact, ending]
        end

        def loop_back_states(body, locals)
          states = @loop_context.fetch(:next).map(&:last)
          states << snapshot(locals) unless body.result_type == :never
          states
        end

        def loop_pass(node, head, locals, exit_counts)
          restore_flow_exits(exit_counts)
          restore(head, locals)
          loop_iteration(node, locals)
        end
      end

      include States
      include Bounds
      include Iterations

      private

      def validate_loop(node, locals)
        saved_context = @loop_context
        @loop_depth = (@loop_depth || 0) + 1
        entry = snapshot(locals)
        exit_counts = flow_exit_counts
        head = solve_loop(node, entry, locals, exit_counts)
        value, _, ending = loop_pass(node, head, locals, exit_counts)
        exits = @loop_context.fetch(:break)
        states = [ending, *exits.map(&:last)].compact
        restore(entry, locals)
        merge_states(states, locals, node)
        types = exits.map(&:first)
        types << :nil if ending
        value.with(result_type: join_types(types, node))
      ensure
        @loop_depth -= 1
        @loop_context = saved_context
      end

      def solve_loop(node, entry, locals, exit_counts)
        head = entry
        # ponytail: reject after 16 passes; use a richer domain if real loops need more convergence steps.
        16.times do
          value, back, = loop_pass(node, head, locals, exit_counts)
          merge_states([entry, *back], locals, node)
          current = snapshot(locals)
          return head if same_loop_state?(head, current)

          head = widen_loop_state(head, current)
          head = constrain_post_header(value, entry, head, locals) if node.post_test
        end
        unsupported(node)
      end

      def constrain_post_header(node, entry, head, locals)
        restore(head, locals)
        states = [entry]
        states << snapshot(locals) if constrain_loop_guard?(node.predicate, !node.until_loop, locals)
        merge_states(states, locals, node)
        snapshot(locals)
      end
    end
  end
end
