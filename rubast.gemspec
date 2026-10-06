# frozen_string_literal: true

Gem::Specification.new do |spec|
  spec.name = "rubast"
  spec.version = "0.1.0"
  spec.summary = "A Ruby-to-Rust AOT compiler"
  spec.authors = ["Rubast contributors"]
  spec.required_ruby_version = ">= 3.4"
  spec.metadata["rubygems_mfa_required"] = "true"
  spec.files = Dir["README.md", "lib/**/*.rb", "app/**/*.rb", "system/**/*.rb", "runtime/**/*"]
  spec.bindir = "bin"
  spec.executables = ["rubast"]

  spec.add_dependency "dry-system", "~> 1.2"
  spec.add_dependency "prism", "~> 1.9"
end
