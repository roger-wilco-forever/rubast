# Rubast working conventions

Rubast is a Ruby AOT compiler that generates Rust source and builds it with Cargo. The supported Ruby subset is defined in `docs/architecture.md`; technology and component boundaries are in `docs/technology-stack.md`.

## Architecture

- Build Ruby services with `dry-system` and Zeitwerk from `system/container.rb`. `system/import.rb` exposes the injector.
- Auto-register services from `app/`. Keep IR nodes, diagnostics, and per-compilation data in `lib/rubast/` outside the container.
- Only the CLI resolves the top-level compiler from the container. Services receive dependencies through constructors. Do not access the container from compiler passes.
- Keep state for each run in a fresh compilation context. Do not memoize stateful passes across compilations.
- Ruby source semantics belong to the IR and analysis layers. Rust emission and Cargo execution are separate boundaries.

## TDD

- For new observable behavior, write or use a Cucumber `.feature` scenario before implementation. Run it to see the failure, implement the smallest behavior that makes it pass, then refactor.
- Treat user-provided scenarios as the specification. Do not weaken or rewrite them merely to make a test pass.
- Use RSpec for local pass behavior and container wiring. Use differential scenarios against a pinned CRuby for supported programs and diagnostic scenarios for unsupported programs.
- Run the relevant scenario/spec during development and the full suite before declaring behavior complete. Documentation-only edits do not need new tests.

Run `bundle exec cucumber --publish-quiet` and `bundle exec rspec` for Ruby changes. Run `cargo test --manifest-path runtime/rubast_runtime/Cargo.toml` for Rust runtime changes. The current supported input is one file with `puts INTEGER` statements, with signed 64-bit integers.
