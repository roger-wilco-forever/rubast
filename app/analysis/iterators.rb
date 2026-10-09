# frozen_string_literal: true

module Rubast
  module Analysis
    module Iterators
      # ponytail: specialize 1,000 invocations per validation; use loop summaries for larger workloads.
      MAX_STEPS = 1_000
      MAX_ALLOCATIONS = 10_000

      module Bodies
        private

        def loop_allocation?
          (@loop_depth || 0) > (@bounded_loop_depth || 0)
        end

        def record_bounded_allocation
          return unless @allocation_origin

          @bounded_allocations = (@bounded_allocations || 0) + 1
          unsupported(@allocation_origin) if @bounded_allocations > MAX_ALLOCATIONS
        end

        def bounded_iterator_body(block, type, locals)
          saved = [@bounded_loop_depth, @allocation_origin]
          @bounded_loop_depth = (@bounded_loop_depth || 0) + 1
          @allocation_origin = block
          iterator_body(block, type, locals)
        ensure
          @bounded_loop_depth, @allocation_origin = saved
        end

        def iterator_body(block, value_type, locals, exit_context: @block_exit_context)
          saved_context = [@loop_context, @block_exit_context]
          @loop_context = nil
          @block_exit_context = exit_context
          exit_count = block_exit_lists.sum(&:length)
          @loop_depth = (@loop_depth || 0) + 1
          @iterator_steps = (@iterator_steps || 0) + 1
          unsupported(block) if @iterator_steps > MAX_STEPS
          body = validate_iterator_body(block, value_type, locals)
          check_block_fallthrough(block, body, exit_count)
          body
        ensure
          @loop_depth -= 1
          @loop_context, @block_exit_context = saved_context
        end

        def validate_iterator_body(block, value_type, locals)
          scope = locals.merge(block.locals.to_h { |name| [name, :nil] })
          block.parameters.each { |name| scope[name] = value_type }
          context = new_block_context(block, scope)
          body = with_block_next_context(context) do
            value = validate_expression(block.body, scope)
            complete_block_body(value, context, scope, block)
          end
          locals.each_key { |name| locals[name] = scope.fetch(name) }
          body
        end

        def complete_block_body(body, context, locals, origin)
          return body unless context[:used]

          types = context.fetch(:exits).map(&:first)
          states = context.fetch(:exits).map(&:last)
          unless body.result_type == :never
            types << body.result_type
            states << snapshot(locals)
          end
          merge_states(states, locals, origin)
          IR::BlockBody.new(exit_id: context.fetch(:id), body: body,
                            result_type: join_types(types, origin), span: origin.span)
        end

        def check_block_fallthrough(block, body, exit_count)
          unsupported(block) if body.result_type == :never && block_exit_lists.sum(&:length) == exit_count
        end

        def check_detached_block(block, locals, summarize: false)
          before = snapshot(locals)
          exit_counts = flow_exit_counts
          with_block_exit_context(new_block_context(block, locals)) do
            bounded_iterator_body(block, :unknown, locals)
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
            unsupported(node) unless type.is_a?(IR::IntegerType)
            [type.maximum, 0].max
          else
            unsupported(node) unless array_type?(type)
            type.fields.fetch(:length).maximum
          end
        end

        def iterator_item(type, index, node)
          node.call.name == :times ? integer_type(index, index, node) : type.fields.fetch(index)
        end

        def check_iterator_length(type, count, node)
          unsupported(node) if array_type?(type) && type.fields.fetch(:length) != count
        end
      end

      include Bodies

      private

      def check_iterator_call(node)
        call = node.call
        unless call.receiver && !call.safe_navigation && call.arguments.empty? && %i[each times map].include?(call.name)
          unsupported(node)
        end
        unsupported(node) if call.name == :map && loop_allocation?
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
        last = steps.last
        normal = last&.body&.result_type == :never && !last.guarded ? :never : iterator_result(node, type, steps)
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
        shape = array_type?(type) ? type.fields.fetch(:length) : type
        @block_exit_context[:traversal] = [type, shape]
        check_detached_block(node.block, locals) if count.zero?
        steps = []
        count.times do |index|
          step = iterator_step(node, type, shape, index, locals)
          steps << step
          break if step.body.result_type == :never && !step.guarded
        end
        steps
      end

      def iterator_step(node, type, shape, index, locals)
        check_iterator_length(type, shape, node)
        guarded = index >= [shape.minimum, 0].max
        before = snapshot(locals) if guarded
        body = bounded_iterator_body(node.block, iterator_item(type, index, node), locals)
        check_iterator_length(type, shape, node)
        join_optional_step(before, body, locals, node) if guarded
        IR::BlockStep.new(index: index, body: body, span: node.block.span, guarded: guarded)
      end

      def join_optional_step(before, body, locals, node)
        states = body.result_type == :never ? [before] : [before, snapshot(locals)]
        merge_states(states, locals, node)
      end

      def iterator_result(node, receiver_type, steps)
        return receiver_type unless node.call.name == :map

        array = object_type(:Array, :nil)
        steps.each_with_index { |step, index| array.fields[index] = step.body.result_type }
        length = receiver_type.fields.fetch(:length)
        array.fields[:length] = integer_type(length.minimum, length.maximum, node)
        array
      end
    end
  end
end
