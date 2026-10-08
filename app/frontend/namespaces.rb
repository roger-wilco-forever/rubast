# frozen_string_literal: true

module Rubast
  module Frontend
    module Namespaces
      private

      def normalize_namespace(node, source)
        case node
        when Prism::ClassNode, Prism::ModuleNode then normalize_class(node, source)
        when Prism::DefNode then normalize_method(node, source)
        when Prism::SingletonClassNode then normalize_singleton(node, source)
        when Prism::ConstantPathNode then normalize_constant_path(node, source)
        else normalize_constant_write(node, source)
        end
      end

      def constant_parent_path(parent)
        return [parent.parts, parent.absolute] if parent.is_a?(IR::ConstantPath)

        parent ? [[parent.name], false] : [[], true]
      end

      def normalize_constant_path(node, source)
        parent = node.parent && normalize(node.parent, source)
        supported = [IR::ConstantRead, IR::ConstantPath]
        unsupported(node, source) if parent && supported.none? { |type| parent.is_a?(type) }
        parts, absolute = constant_parent_path(parent)
        IR::ConstantPath.new(parts: [*parts, node.name].freeze, absolute: absolute, span: span(node, source))
      end

      def normalize_constant_write(node, source)
        target = if node.is_a?(Prism::ConstantWriteNode)
                   IR::ConstantRead.new(name: node.name, span: span(node, source))
                 else
                   normalize(node.target, source)
                 end
        IR::ConstantWrite.new(target: target, value: normalize(node.value, source), span: span(node, source))
      end

      def normalize_singleton(node, source)
        unsupported(node, source) unless node.expression.is_a?(Prism::SelfNode)
        IR::SingletonBody.new(definitions: in_scope(node.locals) do
          (node.body&.body || []).map { |part| normalize(part, source) }.freeze
        end, span: span(node, source))
      end
    end
  end
end
