# Rubast

Rubast is an experimental ahead-of-time compiler from Ruby to Rust. The compiler itself is written in Ruby. It is inspired by [Spinel](https://github.com/matz/spinel), which compiles Ruby to native programs through C.

**Status:** a small Ruby subset works end to end: signed 64-bit integers, UTF-8 strings, top-level local variables, `gets`, safe `chomp`, interpolation, `puts`, and stateless user classes. Unsupported syntax produces a source diagnostic.

The proposed pipeline is:

```text
Ruby source → Prism (Ruby API) → semantic IR (Ruby) → generated Rust + Rust runtime → Cargo binary
```

Ruby and Prism are needed to run the compiler. Its Ruby services are assembled with `dry-system` and loaded with Zeitwerk. Acceptance behavior is specified with Cucumber; compiler components are checked with RSpec. The compiled program uses the Rust runtime linked into its binary.

The compiler requires CRuby 3.4.5 and Bundler. Building or running a generated program also requires Rust and Cargo. Dependencies are locked in `Gemfile.lock`.

```sh
bundle install
printf 'puts 42\n' > example.rb
bundle exec ruby bin/rubast run example.rb
# 42
```

The [interactive greeting example](examples/hello_user.rb) prompts for a name and prints an interpolated greeting:

```console
$ bundle exec ruby bin/rubast run examples/hello_user.rb
What is your name?
Ada
Hello, Ada!
```

The prompt is flushed before the program waits for input. An EOF produces `Hello, !`, matching CRuby for `gets&.chomp`. The current input reader expects valid UTF-8.

To keep and inspect the generated Rust, emit a standalone Cargo project into a new or empty directory:

```sh
bundle exec ruby bin/rubast emit-rust examples/greeter.rb -o target/greeter
# generated source: target/greeter/src/main.rs
cargo build --manifest-path target/greeter/Cargo.toml
target/greeter/target/debug/rubast_program
```

`emit-rust` does not invoke Cargo or execute the Ruby program. The output includes `Cargo.toml`, `src/main.rs`, and the runtime source; runtime build caches are excluded. Existing nonempty destinations are rejected with `E_OUTPUT`. Compiler and output errors exit with status 2; invalid command usage exits with status 64. `run` continues to build and execute in a temporary directory that is removed afterward.

User classes support `Class.new` without arguments and instance methods with required positional scalar arguments. Each method has one expression as its body; its value is returned. See [the class example](examples/greeter.rb):

```ruby
class Greeter
  def greet(name)
    "Hello, #{name}!"
  end
end
puts Greeter.new.greet("Ada")
```

Classes must be defined before use and contain at least one method. Empty classes, reopening classes or existing Ruby constants, inheritance, `initialize`, instance variables, singleton methods, implicit instance calls, `self`, explicit `return`, and optional/keyword/block parameters are unsupported. Methods cannot receive or return objects; object printing and interpolation are unsupported. Parameter values may be returned or interpolated, but parameter-dependent operations such as `name&.chomp` inside a method are not yet analyzed. Unsupported forms retain `E_UNSUPPORTED` and a Ruby location.

Run the complete local checks with `bin/verify` (RuboCop, RSpec, Cucumber, Rust formatting, and Cargo tests). GitHub Actions runs the same checks on pushes and pull requests. Cucumber compares supported programs with CRuby and checks diagnostics for unsupported programs. The CLI exposes `run` and `emit-rust`; a separate `build` command and the broader language subset remain planned. See [the implementation roadmap](docs/roadmap.md) for the agreed sequence and acceptance criteria.

See [the architecture and implementation plan](docs/architecture.md), [proposed technology stack](docs/technology-stack.md), and [contributor and agent development guide](docs/development.md). Documentation and Cucumber scenarios are written in English.

No license has been selected yet.
