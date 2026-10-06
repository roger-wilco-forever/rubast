# frozen_string_literal: true

require "dry/system"

module Rubast
  class Container < Dry::System::Container
    use :zeitwerk

    configure do |config|
      config.name = :rubast
      config.root = File.expand_path("..", __dir__)
      config.component_dirs.add("app") do |dir|
        dir.namespaces.add_root const: "rubast"
      end
    end
  end
end
