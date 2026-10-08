# frozen_string_literal: true

module Rubast
  module Analysis
    module Iterators
      # ponytail: specialize 1,000 invocations per validation; use loop summaries for larger workloads.
      MAX_STEPS = 1_000

      module Bodies
        private

        def iterator_body(block, value_type, locals, exit_context: @block_exit_context)
          saved_context = [@loop_context, @block_exit_context]
          @loop_context = nil
          @block_exit_context = exit_context
          exit_count = block_exit_lists.sum(&:length)
          @loop_depth = (@loop_depth || 0) + 1
          @iterator_steps = (@iterator_steps || 0) + 1
          unsupported(block) if @iterator_steps > MAX_STEPS
          scope = locals.merge(block.locals.to_h { |name| [name, :nil] })
          block.parameters.each { |name| scope[name] = value_type }
          body = validate_expression(block.body, scope)
          check_block_fallthrough(block, body, exit_count)
          locals.each_key { |name| locals[name] = scope.fetch(name) }
          body
        ensure
          @loop_depth -= 1
          @loop_context, @block_exit_context = saved_context
        end

        def check_block_fallthrough(block, body, exit_count)
          unsupported(block) if body.result_type == :never && block_exit_lists.sum(&:length) == exit_count
        end

        def check_detached_block(block, locals, summarize: false)
          before = snapshot(locals)
          exit_counts = flow_exit_counts
          with_block_exit_context(new_block_context(block, locals)) do
            iterator_body(block, :unknown, locals)
          end
          after = snapshot(locals) if summarize
        ensure
          restore(before, locals)
          restore_flow_exits(exit_counts)
          summarize_iterator_state(before, after, locals) if after
        end

        def summarize_iterator_state(before, after, locals)
          summarize_iterator_map(before.fetch(:locals), after.fetch(:locals), locals)
          before.fetch(:fields).each do |id, (object, fields)|
            summarize_iterator_map(fields, after.fetch(:fields).fetch(id).last, object.fields)
          end
        end

        def summarize_iterator_map(before, after, target)
          (before.keys | after.keys).each do |name|
            target[name] = :unknown unless same_loop_type?(before[name], after[name])
          end
        end

        def iterator_count(type, node)
          if node.call.name == :times
            unsupported(node) unless type.is_a?(IR::IntegerType) && type.minimum == type.maximum
            [type.minimum, 0].max
          else
            unsupported(node) unless array_type?(type)
            array_length(type, node)
          end
        end

        def iterator_item(type, index, node)
          node.call.name == :times ? integer_type(index, index, node) : type.fields.fetch(index)
        end

        def check_iterator_length(type, count, node)
          unsupported(node) if array_type?(type) && array_length(type, node) != count
        end
      end

      include Bodies

      private

      def check_iterator_call(node)
        call = node.call
        unless call.receiver && !call.safe_navigation && call.arguments.empty? && %i[each times map].include?(call.name)
          unsupported(node)
        end
        unsupported(node) if call.name == :map && @loop_depth&.positive?
      end

      def validate_iterator_receiver(node, receiver, type, locals)
        call = node.call
        if type == :unknown
          check_detached_block(node.block, locals, summarize: true)
          return node.with(call: call.with(receiver: receiver), result_type: :unknown)
        end
        context = new_block_context(node.block, locals)
        with_block_exit_context(context) do
          steps = iterator_steps(node, type, locals)
          result = complete_iterator(node, type, steps, context, locals)
          IR::Iterator.new(exit_id: context.fetch(:id), name: call.name,
                           family: call.name == :times ? :integer : :array, receiver: receiver,
                           parameters: node.block.parameters, locals: node.block.locals, steps: steps.freeze,
                           result_type: result, span: node.span)
        end
      end

      def complete_iterator(node, type, steps, context, locals)
        normal = steps.last&.body&.result_type == :never ? :never : iterator_result(node, type, steps)
        types = context.fetch(:exits).map(&:first)
        states = context.fetch(:exits).map(&:last)
        unless normal == :never
          types << normal
          states << snapshot(locals)
        end
        merge_states(states, locals, node)
        join_types(types, node)
      end

      def iterator_steps(node, type, locals)
        count = iterator_count(type, node)
        unsupported(node) if count > MAX_STEPS
        @block_exit_context[:traversal] = [type, count]
        check_detached_block(node.block, locals) if count.zero?
        steps = []
        count.times do |index|
          check_iterator_length(type, count, node)
          body = iterator_body(node.block, iterator_item(type, index, node), locals)
          check_iterator_length(type, count, node)
          steps << IR::BlockStep.new(index: index, body: body, span: node.block.span)
          break if body.result_type == :never
        end
        steps
      end

      def iterator_result(node, receiver_type, steps)
        return receiver_type unless node.call.name == :map

        array = object_type(:Array, :nil)
        steps.each_with_index { |step, index| array.fields[index] = step.body.result_type }
        set_array_length(array, steps.length, node)
        array
      end
    end
  end
end
