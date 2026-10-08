# frozen_string_literal: true

module Rubast
  module Backend
    module Exceptions
      module FlowHelpers
        private

        def location(span, label = frame_label)
          "Location::new(#{Rust.rust_string(span.path)}, #{span.line}, #{Rust.rust_string(label)})" \
            ".highlight(#{Rust.rust_string(span.highlight)})" \
            ".name_highlight(#{Rust.rust_string(span.name_highlight)})"
        end

        def frame_label
          return @frame_name if @block_depth.zero?
          return "block in #{@frame_name}" if @block_depth == 1

          "block (#{@block_depth} levels) in #{@frame_name}"
        end

        def with_target(name, kind = :value)
          previous = @targets[name]
          @targets[name] = [@closure_depth, kind]
          yield
        ensure
          previous ? @targets[name] = previous : @targets.delete(name)
        end

        def emit_jump(name, value)
          depth, kind = @targets.fetch(name)
          return "{ return Err(Flow::Exit(#{Rust.rust_string(name)}, #{value})); }" if depth < @closure_depth

          case kind
          when :return then "{ return Ok(#{value}); }"
          when :next then "{ let _ = #{value}; break '#{name}; }"
          when :retry then "{ let _ = #{value}; continue '#{name}; }"
          else "{ break '#{name} #{value}; }"
          end
        end

        def capture_result
          @closure_depth += 1
          statements = []
          value = yield statements
          statements << "    Ok(#{value})"
          "(|| -> Outcome {\n#{statements.join("\n")}\n    })()"
        ensure
          @closure_depth -= 1
        end

        def emit_outcome(result, lines)
          arms = @targets.keys.map do |name|
            "Err(Flow::Exit(#{Rust.rust_string(name)}, value)) => #{emit_jump(name, 'value')},"
          end
          emit_value("match #{result} { Ok(value) => value, #{arms.join(' ')} Err(flow) => return Err(flow) }", lines)
        end

        def traced_result(locations, lines, &)
          locations.each { |value| lines << "    runtime.enter(#{value});" }
          expression = capture_result(&)
          result = "outcome_#{@next_temp}"
          @next_temp += 1
          lines << "    let #{result}: Outcome = #{expression};"
          locations.length.times { lines << "    runtime.leave();" }
          emit_outcome(result, lines)
        end
      end

      include FlowHelpers

      private

      def emit_exception(node, lines)
        case node
        when IR::ExceptionValue
          message = emit_expression(node.message, lines)
          emit_value("Runtime::exception(#{Rust.rust_string(node.class_name.to_s)}, #{message})", lines)
        when IR::CallError
          value = "Runtime::exception(#{Rust.rust_string(node.class_name.to_s)}, " \
                  "Value::from(#{Rust.rust_string(node.message)}.to_owned()))"
          emit_value("runtime.raise(Some(#{value}), #{location(node.span, node.label || frame_label)})?", lines)
        when IR::Raise
          value = node.arguments.empty? ? "None" : "Some(#{emit_expression(node.arguments.first, lines)})"
          emit_value("runtime.raise(#{value}, #{location(node.span)})?", lines)
        when IR::Retry then emit_jump(@retry_label, "Value::Nil")
        else emit_protected(node, lines)
        end
      end

      def emit_protected(node, lines)
        saved_retry = @retry_label
        label = "retry_#{@next_temp}"
        @next_temp += 1
        statements = []
        with_target(label, :retry) do
          body = capture_result { |parts| emit_expression(node.body, parts) }
          statements << "    let mut pending: Outcome = #{body};"
          emit_rescues(node, statements, label)
          statements << "    if matches!(&pending, Err(Flow::Exit(#{Rust.rust_string(label)}, _))) " \
                        "{ continue '#{label}; }"
          emit_ensure(node.ensure_body, statements) if node.ensure_body
          statements << "    break '#{label} pending;"
        end
        result = "{ '#{label}: loop {\n#{statements.join("\n")}\n    } }"
        emit_outcome(result, lines)
      ensure
        @retry_label = saved_retry
      end

      def emit_rescues(node, lines, label)
        handlers = node.handlers.map do |handler|
          classes = handler.classes.map { |name| Rust.rust_string(name.to_s) }.join(", ")
          body = rescue_result(handler, label)
          "if Runtime::matches(&error, &[#{classes}]) { #{body} } else "
        end.join
        success = node.otherwise ? capture_result { |parts| emit_expression(node.otherwise, parts) } : "Ok(value)"
        lines << "    pending = match pending { Ok(value) => #{success}, Err(Flow::Exception(error)) => {\n" \
                 "#{handlers} { Err(Flow::Exception(error)) }\n    }, Err(flow) => Err(flow) };"
      end

      def rescue_result(handler, label)
        previous = @retry_label
        @retry_label = label
        body = capture_result do |parts|
          parts << "    #{@locals.fetch(handler.reference)} = Value::Exception(error.clone());" if handler.reference
          emit_expression(handler.body, parts)
        end
        "{ runtime.enter_exception(error.clone()); let handled: Outcome = #{body}; runtime.leave_exception(); handled }"
      ensure
        @retry_label = previous
      end

      def emit_ensure(body, lines)
        expression = capture_result { |parts| emit_expression(body, parts) }
        lines << "    let entered_exception = if let Err(Flow::Exception(error)) = &pending {\n    " \
                 "runtime.enter_exception(error.clone()); true } else { false };"
        lines << "    let cleanup: Outcome = #{expression};"
        lines << "    if entered_exception { runtime.leave_exception(); }"
        lines << "    if cleanup.is_err() { pending = cleanup; }"
      end
    end
  end
end
