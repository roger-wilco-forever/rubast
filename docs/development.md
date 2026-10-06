# Developing Rubast

This handbook is for contributors and coding agents. [AGENTS.md](../AGENTS.md) lists the invariants; [architecture.md](architecture.md) distinguishes current support from planned milestones.

## Set up and inspect

Use the Ruby version in [`.ruby-version`](../.ruby-version), Bundler, and Rust with Cargo. Install gems with `bundle install`. Run the [interactive example](../examples/hello_user.rb) with:

```sh
bundle exec ruby bin/rubast run examples/hello_user.rb
```

The CLI currently supports `run` only. Read [features/first_program.feature](../features/first_program.feature) and [features/hello_user.feature](../features/hello_user.feature) for executable examples. Treat their observed behavior and the current implementation as the live support claim. Architectural milestones describe intended behavior.

## Ownership map

| Change | Start here |
| --- | --- |
| CLI and error presentation | [`bin/rubast`](../bin/rubast), [`lib/rubast/compilation_error.rb`](../lib/rubast/compilation_error.rb) |
| Source bytes and Prism parse errors | [`app/source/reader.rb`](../app/source/reader.rb), [`app/frontend/parser.rb`](../app/frontend/parser.rb) |
| Prism syntax to IR | [`app/frontend/normalizer.rb`](../app/frontend/normalizer.rb), [`lib/rubast/ir.rb`](../lib/rubast/ir.rb) |
| Supported Ruby semantics and diagnostics | [`app/analysis/validator.rb`](../app/analysis/validator.rb) |
| Generated Rust and Cargo manifest | [`app/backend/rust.rb`](../app/backend/rust.rb), [`lib/rubast/generated_project.rb`](../lib/rubast/generated_project.rb) |
| Generated program behavior | [`runtime/rubast_runtime/src/lib.rs`](../runtime/rubast_runtime/src/lib.rs) |
| Cargo execution | [`app/build/cargo.rb`](../app/build/cargo.rb) |
| Stage wiring | [`app/compiler.rb`](../app/compiler.rb), [`system/container.rb`](../system/container.rb) |
| End-to-end behavior and diagnostics | [`features/`](../features/), [`features/step_definitions/compiler_steps.rb`](../features/step_definitions/compiler_steps.rb) |
| Component and wiring checks | [`spec/`](../spec/) |

A new IR form may require changes in the normalizer, validator, emitter, and runtime. The validator must reject it until all stages can preserve its Ruby meaning. Keep external operations at the source/Cargo boundaries and generated program I/O in the Rust runtime.

## Verification by claim

| Check | What it establishes | Limit |
| --- | --- | --- |
| RSpec | A local pass decision or dependency wiring behaves as specified | Does not execute the generated binary |
| Diagnostic Cucumber scenario | Unsupported input fails with a code and Ruby location | Does not establish support |
| Differential Cucumber scenario | A generated binary matches pinned CRuby for the tested input, stdin, stdout, stderr, and exit status | Covers the stated example, not arbitrary Ruby |
| Cargo tests | The Rust runtime crate builds and any Rust tests execute | There are currently zero Rust test assertions; generated behavior is covered by Cucumber |
| RuboCop and Rust formatting | Source meets style gates | Does not establish semantics |

Removing a diagnostic is a support claim. Use an example that distinguishes correct Ruby behavior from a likely wrong translation, such as EOF versus a normal input line, Unicode input, or a side effect that reveals evaluation order. The supported scenario must execute Rubast's output and compare it with CRuby. If the generated program cannot preserve the behavior, keep the diagnostic and document the gap. Do not normalize away a real mismatch.

## Local cycle

1. Record a minimal Ruby source file, any stdin, and CRuby's observed result.
2. Add a Cucumber scenario for the public behavior; run the relevant feature and observe it fail.
3. Change the owning stage. Add a focused RSpec example where useful, and run the focused checks.
4. Run `bin/verify` before completion. It runs the same five checks as [GitHub Actions](../.github/workflows/ci.yml), sequentially and stops on failure.
5. Update the current-subset wording in [README.md](../README.md), [architecture.md](architecture.md), and [AGENTS.md](../AGENTS.md) if support changes. Report actual checks and any untested boundary.

```sh
bundle exec cucumber --publish-quiet features/hello_user.feature
bundle exec rspec spec/system/container_spec.rb
bin/verify
```

A focused test is useful while editing but does not replace the full local check. The current Cargo test command completes with zero Rust unit tests; it is a build check until runtime tests are added. CI is the hosted check for the pushed commit. Documentation-only changes do not require a new behavior test.

For a pull request, include the minimal Ruby repro, the acceptance or diagnostic scenario, commands actually run, and any remaining coverage gap. The [pull request template](../.github/pull_request_template.md) captures these items.

## Origin of these practices

The project map, ownership guide, verification layers, and explicit support claim were adapted to Rubast's smaller pipeline from Roundhouse's [agent guidance](https://github.com/rubys/roundhouse/blob/main/AGENTS.md), [compiler change guide](https://github.com/rubys/roundhouse/blob/main/docs/development/compiler-changes.md), and [testing guide](https://github.com/rubys/roundhouse/blob/main/docs/development/testing.md). Rubast keeps its existing full CI gate because it has one backend and a small suite.
