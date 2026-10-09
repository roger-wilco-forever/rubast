# frozen_string_literal: true

require "json"

module Rubast
  module Analysis
    module NativeMethods
      DATA = JSON.parse(File.read(File.expand_path("../../lib/rubast/native_methods.json", __dir__)), freeze: true)

      private

      def native_method_visibility(type, name)
        kind = namespace_type?(type) ? @namespace_kinds.fetch(type.class_name.name).to_s : "object"
        DATA.fetch("methods").fetch(kind).each do |visibility, names|
          return visibility.to_sym if names.include?(name.to_s)
        end
        nil
      end

      def method_visibility(type, name)
        declared = method_ancestors(type.class_name).filter_map { |key| @visibilities.fetch(key, {})[name] }.first
        declared || native_method_visibility(type, name)
      end
    end
  end
end
