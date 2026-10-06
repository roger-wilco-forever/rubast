# Rubast

Rubast is an experimental ahead-of-time compiler from Ruby to Rust. The compiler itself is written in Ruby. It is inspired by [Spinel](https://github.com/matz/spinel), which compiles Ruby to native programs through C.

**Status:** a small Ruby subset works end to end: signed 64-bit integers, UTF-8 strings, top-level local variables, `gets`, safe `chomp`, interpolation, and `puts`. Unsupported syntax produces a source diagnostic.

The proposed pipeline is:

```text
Ruby source → Prism (Ruby API) → semantic IR (Ruby) → generated Rust + Rust runtime → Cargo binary
```

Ruby and Prism are needed to run the compiler. Its Ruby services are assembled with `dry-system` and loaded with Zeitwerk. Acceptance behavior is specified with Cucumber; compiler components are checked with RSpec. The compiled program uses the Rust runtime linked into its binary.

The current CLI requires CRuby 3.4.5, Bundler, Rust and Cargo. Dependencies are locked in `Gemfile.lock`.

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

Run checks with `bundle exec rubocop`, `bundle exec cucumber --publish-quiet`, `bundle exec rspec`, and `cargo test --manifest-path runtime/rubast_runtime/Cargo.toml`. GitHub Actions runs all checks on pushes and pull requests. Cucumber compares supported programs with CRuby and checks diagnostics for unsupported programs. The compiler currently exposes only `run`; the broader language subset and `emit-rust`/`build` commands are planned in [the architecture](docs/architecture.md).

See [the architecture and implementation plan](docs/architecture.md) and [proposed technology stack](docs/technology-stack.md). Documentation and Cucumber scenarios are written in English.

No license has been selected yet.
