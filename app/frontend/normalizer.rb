# frozen_string_literal: true

require "error_highlight"

module Rubast
  module Frontend
    class Normalizer
      def call(parsed, source)
        Session.new.call(parsed, source)
      end

      class Session < Normalizer
        def call(parsed, source)
          ast = parsed.value
          @scopes = [{ names: ast.locals.to_h { |name| [name, name] }, block: false }]
          @scope_serial = 0
          IR::Program.new(statements: (ast.statements&.body || []).map { |node| normalize(node, source) }.freeze,
                          locals: ast.locals.freeze, warnings: normalize_warnings(parsed, source))
        end
      end

      module Expressions
        private

        def normalize_flow(node, source)
          case node
          when Prism::IfNode, Prism::UnlessNode then normalize_conditional(node, source)
          when Prism::EmbeddedStatementsNode then normalize_embedded(node, source)
          when Prism::ParenthesesNode then normalize_sequence(node.body, node, source)
          when Prism::ReturnNode then normalize_return(node, source)
          when Prism::WhileNode, Prism::UntilNode then normalize_loop(node, source)
          when Prism::BreakNode, Prism::NextNode then normalize_loop_exit(node, source)
          when Prism::BeginNode, Prism::RetryNode, Prism::RescueModifierNode then normalize_exception(node, source)
          end
        end

        def normalize_loop(node, source)
          IR::Loop.new(predicate: normalize(node.predicate, source),
                       body: normalize_sequence(node.statements, node, source),
                       until_loop: node.is_a?(Prism::UntilNode), post_test: node.begin_modifier?,
                       result_type: nil, span: span(node, source))
        end

        def normalize_loop_exit(node, source)
          value = normalize_control_value(node, source)
          IR::LoopExit.new(kind: node.is_a?(Prism::BreakNode) ? :break : :next, value: value, span: span(node, source))
        end

        def normalize_return(node, source)
          IR::Return.new(value: normalize_control_value(node, source), span: span(node, source))
        end

        def normalize_control_value(node, source)
          arguments = node.arguments&.arguments || []
          unsupported(node, source) if arguments.length > 1
          arguments.empty? ? IR::NilLiteral.new(span: span(node, source)) : normalize(arguments.first, source)
        end

        def normalize_conditional(node, source)
          otherwise = node.is_a?(Prism::IfNode) ? node.subsequent : node.else_clause
          consequent = normalize_sequence(node.statements, node, source)
          alternative = if otherwise.is_a?(Prism::IfNode)
                          normalize_conditional(otherwise, source)
                        else
                          normalize_sequence(otherwise&.statements, node, source)
                        end
          if node.is_a?(Prism::UnlessNode)
            IR::Conditional.new(predicate: normalize(node.predicate, source), consequent: alternative,
                                alternative: consequent, result_type: nil, span: span(node, source))
          else
            IR::Conditional.new(predicate: normalize(node.predicate, source), consequent: consequent,
                                alternative: alternative, result_type: nil, span: span(node, source))
          end
        end

        def normalize_sequence(statements, origin, source)
          body = statements&.body || []
          IR::Sequence.new(expressions: body.map { |expression| normalize(expression, source) }.freeze,
                           result_type: nil, span: span(origin, source))
        end

        def normalize_variable(node, source)
          case node
          when Prism::SelfNode then IR::SelfRead.new(result_type: nil, span: span(node, source))
          when Prism::InstanceVariableWriteNode
            IR::InstanceWrite.new(name: node.name, value: normalize(node.value, source), span: span(node, source))
          when Prism::InstanceVariableReadNode
            IR::InstanceRead.new(name: node.name, result_type: nil, span: span(node, source))
          when Prism::LocalVariableWriteNode
            IR::LocalWrite.new(name: local_name(node), value: normalize(node.value, source), span: span(node, source))
          when Prism::LocalVariableReadNode
            IR::LocalRead.new(name: local_name(node), span: span(node, source))
          when Prism::LocalVariableOperatorWriteNode, Prism::InstanceVariableOperatorWriteNode
            normalize_operator_write(node, source)
          end
        end

        def normalize_operator_write(node, source)
          instance = node.is_a?(Prism::InstanceVariableOperatorWriteNode)
          receiver = if instance
                       IR::InstanceRead.new(name: node.name, result_type: nil, span: span(node, source))
                     else
                       IR::LocalRead.new(name: local_name(node), span: span(node, source))
                     end
          value = IR::Call.new(name: node.binary_operator, receiver: receiver,
                               arguments: [normalize(node.value, source)].freeze,
                               safe_navigation: false, span: span(node, source))
          name = instance ? node.name : local_name(node)
          (instance ? IR::InstanceWrite : IR::LocalWrite).new(name: name, value: value, span: span(node, source))
        end

        def normalize_embedded(node, source)
          statements = node.statements&.body || []
          unsupported(node, source) unless statements.one?

          normalize(statements.first, source)
        end
      end

      module Literals
        private

        def normalize_literal(node, source)
          case node
          when Prism::TrueNode, Prism::FalseNode
            IR::BooleanLiteral.new(value: node.is_a?(Prism::TrueNode), span: span(node, source))
          when Prism::NilNode then IR::NilLiteral.new(span: span(node, source))
          when Prism::ConstantReadNode then IR::ConstantRead.new(name: node.name, span: span(node, source))
          when Prism::IntegerNode then IR::IntegerLiteral.new(value: node.value, span: span(node, source))
          when Prism::StringNode
            IR::StringLiteral.new(value: node.unescaped, frozen: node.frozen?, span: span(node, source))
          when Prism::SymbolNode then IR::SymbolLiteral.new(value: node.unescaped, span: span(node, source))
          when Prism::ArrayNode, Prism::HashNode then normalize_collection_literal(node, source)
          end
        end

        def normalize_collection_literal(node, source)
          hash = node.is_a?(Prism::HashNode)
          elements = hash ? node.elements.flat_map { |element| normalize_pair(element, source) } : node.elements
          (hash ? IR::HashLiteral : IR::ArrayLiteral).new(
            elements: elements.map { |element| normalize(element, source) }.freeze,
            result_type: nil, span: span(node, source)
          )
        end

        def normalize_pair(node, source)
          unsupported(node, source) unless node.is_a?(Prism::AssocNode)
          [node.key, node.value]
        end
      end

      module Calls
        private

        def normalize_call(node, source)
          unsupported(node, source) if node.attribute_write?
          return normalize_block_call(node, source) if node.block

          normalize_plain_call(node, source)
        end

        def normalize_plain_call(node, source)
          IR::Call.new(
            name: node.name,
            receiver: node.receiver && normalize(node.receiver, source),
            arguments: (node.arguments&.arguments || []).map { |arg| normalize(arg, source) }.freeze,
            safe_navigation: node.call_operator_loc&.slice == "&.",
            span: span(node, source)
          )
        end

        def normalize_index_write(node, source)
          unsupported(node, source) if node.call_operator_loc&.slice == "&."
          arguments = node.arguments&.arguments || []
          unsupported(node, source) unless arguments.length == 2 && node.receiver && !node.block
          IR::IndexWrite.new(receiver: normalize(node.receiver, source), index: normalize(arguments.first, source),
                             value: normalize(arguments.last, source), result_type: nil, span: span(node, source))
        end

        def normalize_invocation(node, source)
          return normalize_yield(node, source) if node.is_a?(Prism::YieldNode)

          if node.is_a?(Prism::CallNode) && node.attribute_write? && node.name == :[]=
            return normalize_index_write(node, source)
          end

          node.is_a?(Prism::CallNode) ? normalize_call(node, source) : normalize_super(node, source)
        end

        def normalize_super(node, source)
          unsupported(node.block, source) if node.block
          forward = node.is_a?(Prism::ForwardingSuperNode)
          arguments = forward ? [] : (node.arguments&.arguments || [])
          IR::Super.new(arguments: arguments.map { |argument| normalize(argument, source) }.freeze,
                        forward_arguments: forward, span: span(node, source))
        end
      end

      include Exceptions
      include BlockScopes
      include Expressions
      include Literals
      include Calls

      private

      def normalize_warnings(parsed, source)
        parsed.warnings.filter_map do |warning|
          next unless warning.level == :default

          "#{source.path}:#{warning.location.start_line}: warning: #{warning.message}"
        end.freeze
      end

      def normalize(node, source)
        case node
        when Prism::ClassNode then normalize_class(node, source)
        when Prism::ConstantReadNode, Prism::IntegerNode, Prism::StringNode, Prism::NilNode, Prism::TrueNode, Prism::FalseNode,
             Prism::ArrayNode, Prism::HashNode, Prism::SymbolNode
          normalize_literal(node, source)
        when Prism::LocalVariableWriteNode, Prism::LocalVariableReadNode,
             Prism::InstanceVariableWriteNode, Prism::InstanceVariableReadNode, Prism::SelfNode,
             Prism::LocalVariableOperatorWriteNode, Prism::InstanceVariableOperatorWriteNode
          normalize_variable(node, source)
        when Prism::InterpolatedStringNode
          IR::InterpolatedString.new(
            parts: node.parts.map { |part| normalize(part, source) }.freeze,
            span: span(node, source)
          )
        when Prism::IfNode, Prism::UnlessNode, Prism::ParenthesesNode, Prism::ReturnNode, Prism::EmbeddedStatementsNode,
             Prism::WhileNode, Prism::UntilNode, Prism::BreakNode, Prism::NextNode, Prism::BeginNode,
             Prism::RetryNode, Prism::RescueModifierNode
          normalize_flow(node, source)
        when Prism::CallNode, Prism::SuperNode, Prism::ForwardingSuperNode, Prism::YieldNode
          normalize_invocation(node, source)
        else unsupported(node, source)
        end
      end

      def normalize_class(node, source)
        unsupported(node, source) unless node.constant_path.is_a?(Prism::ConstantReadNode)
        unsupported(node.superclass, source) if node.superclass && !node.superclass.is_a?(Prism::ConstantReadNode)
        methods = node.body&.body || []

        IR::ClassDefinition.new(name: node.name, superclass: node.superclass && normalize(node.superclass, source),
                                definitions: methods.map { |method| normalize_method(method, source) }.freeze,
                                span: span(node, source))
      end

      def normalize_method(node, source)
        unsupported(node, source) unless node.is_a?(Prism::DefNode) && node.receiver.nil?
        requireds = normalize_parameters(node.parameters, source)
        IR::MethodDefinition.new(name: node.name, parameters: requireds.map(&:name).freeze,
                                 locals: node.locals.freeze, body: normalize_method_body(node, source),
                                 span: span(node, source))
      end

      def normalize_method_body(node, source)
        return in_scope(node.locals) { normalize_begin(node.body, source) } if node.body.is_a?(Prism::BeginNode)

        unsupported(node.body, source) if node.body && !node.body.is_a?(Prism::StatementsNode)
        in_scope(node.locals) { normalize_sequence(node.body, node, source) }
      end

      def normalize_parameters(parameters, source)
        return [] unless parameters

        extras = [parameters.optionals, parameters.rest, parameters.posts, parameters.keywords,
                  parameters.keyword_rest, parameters.block].flatten.compact
        unsupported(parameters, source) unless extras.empty?
        parameters.requireds.each do |parameter|
          unsupported(parameter, source) unless parameter.is_a?(Prism::RequiredParameterNode)
        end
      end

      def unsupported(node, source)
        raise CompilationError.new(
          code: "E_UNSUPPORTED",
          message: "unsupported Ruby construct: #{node.class.name.split('::').last}",
          span: span(node, source)
        )
      end

      def argument_highlight(node)
        return "" unless node.is_a?(Prism::CallNode)

        spot = ErrorHighlight.spot(node, point_type: :args)
        spot ? ErrorHighlight.formatter.message_for(spot) : ""
      end

      def span(node, source)
        Span.new(path: source.path, line: node.location.start_line,
                 column: node.location.start_column + 1, highlight: argument_highlight(node))
      end
    end
  end
end
