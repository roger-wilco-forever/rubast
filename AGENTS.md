# Working on Rubast

Rubast is a Ruby-written AOT compiler for a documented Ruby subset. It uses Prism, a Ruby semantic IR, Rust emission, and Cargo. This file is the starting point for agents and contributors. The implementation and executed checks are authoritative for current behavior; architecture documents also describe planned work.

## Start here

| Need | Read |
| --- | --- |
| Run Rubast or see the current subset | [README.md](README.md) |
| Understand semantic boundaries and future milestones | [docs/architecture.md](docs/architecture.md) |
| Follow the implementation sequence | [docs/roadmap.md](docs/roadmap.md) |
| Find container keys and stage contracts | [docs/technology-stack.md](docs/technology-stack.md) |
| Choose the owning file and verification | [docs/development.md](docs/development.md) |
| See executable behavior examples | [features/](features/) and [examples/](examples/) |

Current pipeline: source bytes → Prism AST → normalized IR → validation → Rust source and runtime → Cargo binary. The CLI exposes only `run`. signed 64-bit integers, UTF-8 strings, top-level locals, `gets`, safe `chomp`, interpolation, `puts`, and stateless user classes form the current subset. Other constructs described in the architecture may still be proposals.

## Invariants

1. **An accepted construct must behave like CRuby on its declared inputs.** A green parser or validator test does not establish runtime support. Add a Cucumber scenario that executes the generated program and compares stdout, stderr, and exit status with pinned CRuby before expanding the accepted subset.
2. **Unsupported semantics fail before Rust emission.** Preserve a diagnostic code and Ruby location. Do not drop a Prism node, substitute a value, or broaden validation merely to make compilation succeed.
3. **Stage ownership is explicit.** Prism syntax belongs in the frontend; Ruby meaning and supported-call rules belong in IR and analysis; the backend receives validated IR; Rust runtime behavior belongs in `runtime/rubast_runtime/`. Keep Ruby semantic rules out of Cargo execution.
4. **Dependency direction stays one-way.** `system/container.rb` assembles services from `app/`. Only the CLI resolves the top-level compiler. Services receive constructor dependencies; IR, diagnostics, and per-run data in `lib/rubast/` do not use the container.
5. **Compilation state is per run.** Do not memoize mutable state in container-managed services across compilations. The planned `CompilationContext` is not implemented yet.
6. **Preserve observable evaluation.** New expressions must maintain Ruby value, side-effect order, and error behavior. Use inputs that distinguish a correct translation from a plausible incorrect one.

## Change workflow

1. Locate the owner in [docs/development.md](docs/development.md). Capture the smallest Ruby repro and expected CRuby result.
2. For new observable behavior, write or use a Cucumber scenario first and run it red. For unsupported behavior, assert the diagnostic code and source location.
3. Implement in the owning stage. Add a focused RSpec example when it tests a pass decision or container wiring that the scenario cannot isolate.
4. Run the focused check, then `bin/verify` before reporting completion. This runs RuboCop, RSpec, Cucumber, Rust formatting, and Cargo tests. CI runs the same checks on pushes and pull requests.
5. Report which checks actually ran. Update the documented subset when support changes. A diagnostic removed without emitted execution evidence is not a completed feature.
6. Complete roadmap stages in order. After each stage passes `bin/verify`, commit its implementation, tests, and documentation and push it to GitHub before starting the next stage. Report the commit and push result; distinguish local checks from hosted CI status.

Write project documentation, Cucumber features, and Cucumber step definitions in English. Do not weaken a user-provided scenario or suppress a failing comparison to make a check green. Documentation-only edits need no new behavior test.
