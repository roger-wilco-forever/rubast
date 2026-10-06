# Rubast

Rubast is an experimental ahead-of-time compiler from Ruby to Rust. The compiler itself is written in Ruby. It is inspired by [Spinel](https://github.com/matz/spinel), which compiles Ruby to native programs through C.

**Status:** the first end-to-end slice works. It accepts a single Ruby file containing statements of the form `puts INTEGER`, where `INTEGER` fits in signed 64 bits. Other syntax is rejected with a source diagnostic.

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

Run checks with `bundle exec cucumber --publish-quiet`, `bundle exec rspec`, and `cargo test --manifest-path runtime/rubast_runtime/Cargo.toml`. Cucumber compares supported programs with CRuby and checks diagnostics for unsupported programs. The compiler currently exposes only `run`; the broader language subset and `emit-rust`/`build` commands are planned in [the architecture](docs/architecture.md).

See [the architecture and implementation plan](docs/architecture.md) and [proposed technology stack](docs/technology-stack.md). Both documents are currently in Russian.

No license has been selected yet.
