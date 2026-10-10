# Developing Rubast

This handbook is for contributors and coding agents. [AGENTS.md](../AGENTS.md) lists the invariants; [architecture.md](architecture.md) distinguishes current support from planned milestones.

## Set up and inspect

Use the Ruby version in [`.ruby-version`](../.ruby-version), Bundler, and Rust with Cargo. Install gems with `bundle install`. Run the [interactive example](../examples/hello_user.rb) with:

```sh
bundle exec ruby bin/rubast run examples/hello_user.rb
```

The CLI supports `run`, `build FILE -o BIN`, `emit-rust FILE -o DIR`, and `dump-ir FILE --stage normalized|semantic`. `run`/`build` accept `--release` and `--keep-project DIR`; see [compiler artifacts](compiler-artifacts.md). Use `emit-rust` to retain a Cargo project in a new or empty directory for source inspection and independent builds. See [the roadmap](roadmap.md) for the implementation order. Read [features/first_program.feature](../features/first_program.feature) and [features/hello_user.feature](../features/hello_user.feature) for executable examples. Treat their observed behavior and the current implementation as the live support claim. Architectural milestones describe intended behavior.

## Ownership map

| Change | Start here |
| --- | --- |
| CLI and error presentation | [`bin/rubast`](../bin/rubast), [`lib/rubast/compilation_error.rb`](../lib/rubast/compilation_error.rb) |
| Source bytes and Prism parse errors | [`app/source/reader.rb`](../app/source/reader.rb), [`app/frontend/parser.rb`](../app/frontend/parser.rb) |
| Static source dependencies and loading grammar | [`app/frontend/loader.rb`](../app/frontend/loader.rb), [`app/source/reader.rb`](../app/source/reader.rb), [`features/source_loading.feature`](../features/source_loading.feature) |
| Prism syntax to IR | [`app/frontend/normalizer.rb`](../app/frontend/normalizer.rb), [`app/frontend/namespaces.rb`](../app/frontend/namespaces.rb), [`app/frontend/arguments.rb`](../app/frontend/arguments.rb), [`app/frontend/block_scopes.rb`](../app/frontend/block_scopes.rb), [`app/frontend/exceptions.rb`](../app/frontend/exceptions.rb), [`lib/rubast/ir.rb`](../lib/rubast/ir.rb) |
| Text I/O validation and runtime behavior | [`app/analysis/text_io.rb`](../app/analysis/text_io.rb), [`runtime/rubast_runtime/src/text_io.rs`](../runtime/rubast_runtime/src/text_io.rs), [`features/practical_io.feature`](../features/practical_io.feature); regenerate pinned Unicode inspection data with [`bin/generate-inspection-table`](../bin/generate-inspection-table) |
| Supported Ruby semantics and diagnostics | [`app/analysis/validator.rb`](../app/analysis/validator.rb), [`app/analysis/namespaces.rb`](../app/analysis/namespaces.rb), [`app/analysis/modules.rb`](../app/analysis/modules.rb), [`app/analysis/visibility.rb`](../app/analysis/visibility.rb), [`app/analysis/registry_operations.rb`](../app/analysis/registry_operations.rb), [`app/analysis/loop_analysis.rb`](../app/analysis/loop_analysis.rb), [`app/analysis/collections.rb`](../app/analysis/collections.rb), [`app/analysis/hashes.rb`](../app/analysis/hashes.rb), [`app/analysis/iterators.rb`](../app/analysis/iterators.rb), [`app/analysis/arguments.rb`](../app/analysis/arguments.rb), [`app/analysis/call_arguments.rb`](../app/analysis/call_arguments.rb), [`app/analysis/block_arguments.rb`](../app/analysis/block_arguments.rb), [`app/analysis/blocks.rb`](../app/analysis/blocks.rb), [`app/analysis/exceptions.rb`](../app/analysis/exceptions.rb) |
| Generated Rust and Cargo manifest | [`app/backend/rust.rb`](../app/backend/rust.rb), [`app/backend/namespaces.rb`](../app/backend/namespaces.rb), [`app/backend/iterators.rb`](../app/backend/iterators.rb), [`app/backend/blocks.rb`](../app/backend/blocks.rb), [`app/backend/exceptions.rb`](../app/backend/exceptions.rb), [`lib/rubast/generated_project.rb`](../lib/rubast/generated_project.rb) |
| Generated program behavior | [`runtime/rubast_runtime/src/lib.rs`](../runtime/rubast_runtime/src/lib.rs), [`runtime/rubast_runtime/src/exceptions.rs`](../runtime/rubast_runtime/src/exceptions.rs), [`runtime/rubast_runtime/src/heap.rs`](../runtime/rubast_runtime/src/heap.rs) |
| IR graph serialization and source mapping | [`app/debug/ir.rb`](../app/debug/ir.rb), [`app/backend/source_map.rb`](../app/backend/source_map.rb), [`features/compiler_artifacts.feature`](../features/compiler_artifacts.feature) |
| Project files, binary destinations, and runtime copying | [`app/build/writer.rb`](../app/build/writer.rb) |
| Cargo execution and build diagnostics | [`app/build/cargo.rb`](../app/build/cargo.rb), [`app/build/diagnostics.rb`](../app/build/diagnostics.rb), [`spec/build/cargo_spec.rb`](../spec/build/cargo_spec.rb) |
| Performance workloads and measurements | [`benchmarks/practical.py`](../benchmarks/practical.py), [`benchmarks/workloads/`](../benchmarks/workloads/), [`benchmarks/profile.py`](../benchmarks/profile.py), [`benchmarks/profile_cpu.c`](../benchmarks/profile_cpu.c), [`docs/practical-benchmarks.md`](practical-benchmarks.md), [`docs/profile-guided-performance.md`](profile-guided-performance.md); run timing, profiling, and verification separately |
| Definition changes, send, hooks, and reflection | [`app/analysis/namespaces.rb`](../app/analysis/namespaces.rb), [`app/analysis/static_dispatch.rb`](../app/analysis/static_dispatch.rb), [`app/analysis/reflection.rb`](../app/analysis/reflection.rb), [`app/analysis/native_methods.rb`](../app/analysis/native_methods.rb), [`app/backend/reflection.rb`](../app/backend/reflection.rb), [`runtime/rubast_runtime/src/lib.rs`](../runtime/rubast_runtime/src/lib.rs) for reflective identifier promotion, [`features/selected_dynamic.feature`](../features/selected_dynamic.feature); regenerate pinned metadata with [`bin/generate-native-methods`](../bin/generate-native-methods) |
| Literal Symbol callbacks | [`app/analysis/symbol_blocks.rb`](../app/analysis/symbol_blocks.rb), [`app/backend/symbol_blocks.rb`](../app/backend/symbol_blocks.rb), [`features/symbol_to_proc.feature`](../features/symbol_to_proc.feature) |
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
| Cargo tests | The Rust runtime crate builds and any Rust tests execute | Runtime reclamation assertions check roots, cycles, buffers, and slot reuse; generated behavior is covered by Cucumber |
| RuboCop and Rust formatting | Source meets style gates | Does not establish semantics |

Removing a diagnostic is a support claim. Use an example that distinguishes correct Ruby behavior from a likely wrong translation, such as EOF versus a normal input line, Unicode input, or a side effect that reveals evaluation order. The supported scenario must execute Rubast's output and compare it with CRuby. If the generated program cannot preserve the behavior, keep the diagnostic and document the gap. Do not normalize away a real mismatch.

## Local cycle

1. Record a minimal Ruby source file, any stdin, and CRuby's observed result.
2. Add a Cucumber scenario for the public behavior; run the relevant feature and observe it fail.
3. Change the owning stage. Add a focused RSpec example where useful, and run the focused checks.
4. Run `bin/verify` before completion. It runs the same five checks as [GitHub Actions](../.github/workflows/ci.yml), sequentially and stops on failure.
5. Update the current-subset wording in [README.md](../README.md), [architecture.md](architecture.md), and [AGENTS.md](../AGENTS.md) if support changes. Report actual checks and any untested boundary.

```sh
bundle exec cucumber --publish-quiet features/hello_user.feature features/emit_rust.feature
bundle exec rspec spec/system/container_spec.rb
bin/verify
```

A focused test is useful while editing but does not replace the full local check. Cargo also runs the heap reclamation tests; their object-count assertions supplement the differential execution scenarios. CI is the hosted check for the pushed commit. Documentation-only changes do not require a new behavior test.

For a pull request, include the minimal Ruby repro, the acceptance or diagnostic scenario, commands actually run, and any remaining coverage gap. The [pull request template](../.github/pull_request_template.md) captures these items.

## Origin of these practices

The project map, ownership guide, verification layers, and explicit support claim were adapted to Rubast's smaller pipeline from Roundhouse's [agent guidance](https://github.com/rubys/roundhouse/blob/main/AGENTS.md), [compiler change guide](https://github.com/rubys/roundhouse/blob/main/docs/development/compiler-changes.md), and [testing guide](https://github.com/rubys/roundhouse/blob/main/docs/development/testing.md). Rubast keeps its existing full CI gate because it has one backend and a small suite.
