# Rubast

Rubast is an experimental ahead-of-time compiler from Ruby to Rust. The compiler itself is written in Ruby. It is inspired by [Spinel](https://github.com/matz/spinel), which compiles Ruby to native programs through C.

**Status:** architecture and scope are being defined. There is no working compiler yet.

The proposed pipeline is:

```text
Ruby source → Prism (Ruby API) → semantic IR (Ruby) → generated Rust + Rust runtime → Cargo binary
```

Ruby and Prism are needed to run the compiler. The compiled program uses the Rust runtime linked into its binary.

The first milestone targets a documented subset of single-file Ruby programs. Each supported behavior will be checked against a pinned CRuby version. Unsupported constructs should produce a diagnostic tied to the Ruby source instead of silently changing the program.

See [the architecture and implementation plan](docs/architecture.md) and [proposed technology stack](docs/technology-stack.md). Both documents are currently in Russian.

No license has been selected yet.
