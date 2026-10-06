# frozen_string_literal: true

module Rubast
  module Backend
    class Rust
      def call(program)
        statements = program.statements.map do |statement|
          "    runtime.puts(Value::Integer(#{statement.value}));"
        end

        main = [
          "use rubast_runtime::{Runtime, Value};",
          "",
          "fn main() {",
          "    let mut runtime = Runtime::new();",
          *statements,
          "}",
          ""
        ].join("\n")

        manifest = <<~TOML
          [package]
          name = "rubast_program"
          version = "0.1.0"
          edition = "2021"

          [dependencies]
          rubast_runtime = { path = "rubast_runtime" }
        TOML

        GeneratedProject.new(files: {
          "Cargo.toml" => manifest,
          "src/main.rs" => main
        }.freeze)
      end
    end
  end
end
