# Rubast technology stack and component boundaries

> Decision recorded on 2026-10-06: write the compiler in Ruby; use Prism as the parser and `dry-system` with Zeitwerk for component assembly and loading from the start. Development uses Cucumber and RSpec; RuboCop is required in CI. The semantics of supported Ruby remain a separate contract in the [architecture](architecture.md).

## Why use dry-system

[`dry-system`](https://hanakai.org/learn/dry/dry-system/v1.2) registers components, assembles dependencies, supports autoloading, and permits test substitution. We use it to **assemble compiler services**. The IR and individual algorithm steps are ordinary Ruby objects.

The container knows component implementations and keys. Services receive dependencies through constructors and do not access the container from `#call`. This lets us replace the Prism adapter, Cargo execution, or backend without rewriting analysis passes. Container keys and stage contracts are internal project APIs; changing them requires updating their tests deliberately.

## Compilation flow

```text
CLI
  → Compiler
  → SourceReader → PrismParser → Normalizer → Validator/Analyzer
  → RustEmitter → GeneratedProject
  → CargoRunner (build/run only)
```

Target contract: each `Compiler#call(request)` gets a separate `CompilationContext` containing the source file, options, name tables, diagnostics, and temporary data. The container holds no per-compilation state. Stateless services may be reused. An analyzer with working tables is created for each run or receives those tables through the context. Memoization is a decision for each component.

| Stage | Input | Output |
| --- | --- | --- |
| SourceReader | Path and options | `SourceFile` with bytes and file path |
| PrismParser | `SourceFile` | Prism AST or parse diagnostics |
| Normalizer | Prism AST | Small syntax IR with `SourceSpan` |
| Validator/Analyzer | Syntax IR | Validated semantic IR |
| RustEmitter | Validated IR | Rust files, Cargo manifest, source map |
| CargoRunner | Generated project | Binary path, stdout/stderr, and exit status |

Expected user errors become structured diagnostics with codes and Ruby spans. Unexpected broken invariants remain internal compiler errors. A stage cannot proceed after its predecessor fails; partially translated Rust must never be presented as a successful build.

## Container rules

- `Rubast::Container < Dry::System::Container` lives in `system/container.rb`. `Rubast::Import = Rubast::Container.injector` lives in `system/import.rb`. The container configures `use :zeitwerk` and component directories.
- Only services under `app/` are auto-registered. IR nodes, diagnostics, and request values live under `lib/rubast/` outside the container. The `app/` root constant namespace is `Rubast`, while keys follow paths: `source.reader`, `frontend.parser`, `frontend.normalizer`, `analysis.validator`, `backend.rust`, `build.cargo`, and `compiler`. For example, `app/frontend/parser.rb` defines `Rubast::Frontend::Parser`.
- Services express dependencies through constructors. [Auto-injection](https://hanakai.org/learn/dry/dry-system/v1.2/dependency-auto-injection) is allowed at the orchestration layer; stage algorithms and IR do not know about the container.
- Introduce [providers](https://hanakai.org/learn/dry/dry-system/v1.2/providers) for resources with a `prepare/start/stop` lifecycle. An ordinary `cargo` invocation is an adapter call, not a long-lived provider.
- Choose memoization explicitly for each component. Never share mutable per-compilation state between runs.
- Integration tests can substitute external adapters through [test mode](https://hanakai.org/learn/dry/dry-system/v1.2/test-mode). Test passes directly without the container.

## Code placement

```text
bin/rubast                     # CLI
system/container.rb            # dry-system, Zeitwerk, component directories
system/import.rb               # Rubast::Import
app/compiler.rb                # orchestration of one compilation
app/frontend/                  # Prism adapter and normalization
app/analysis/                  # subset validation and analysis
app/backend/                   # Rust and Cargo manifest generation
app/build/                     # Cargo execution
lib/rubast/                    # IR, spans, and diagnostics outside the container
runtime/rubast_runtime/        # Rust crate linked into output programs
features/                      # Cucumber acceptance behavior
spec/                          # RSpec passes and container wiring
```

Dependencies flow from `compiler → stages → IR`. Adapters perform external operations. IR imports neither the container nor the CLI, Prism, or Cargo. The Rust runtime does not depend on the Ruby compiler; generated projects include the required runtime version.

## Other technology choices

| Area | Choice |
| --- | --- |
| Ruby | CRuby 3.4 is the first compatibility target; CRuby 3.4.5 is pinned in `.ruby-version`, Prism 1.9.0 and other gems in `Gemfile.lock` |
| Parser | [Prism Ruby API](https://ruby.github.io/prism/rb/docs/ruby_api_md.html) |
| Packaging | Ruby gem, gemspec, and Bundler |
| CLI | [OptionParser](https://docs.ruby-lang.org/en/3.4/OptionParser.html) |
| IR and diagnostics | `Data.define` and project-owned classes; freeze nested collections separately ([Ruby Data](https://docs.ruby-lang.org/en/3.4/Data.html)) |
| External commands | `Open3` with argument arrays, without shell interpolation ([Ruby Open3](https://docs.ruby-lang.org/en/3.4/Open3.html)) |
| Output | Rust source plus `rubast_runtime`, built with [Cargo](https://doc.rust-lang.org/cargo/) |
| Checks | RuboCop for Ruby; Cucumber for CLI behavior; RSpec for passes and wiring; `cargo fmt --check` and `cargo test` for the runtime; differential checks against pinned CRuby |

`dry-struct`, `dry-types`, and `dry-monads` are not initial dependencies. Choosing `dry-system` does not require the rest of dry-rb. The compiler owns its error schema and IR shape. Add libraries when a tested scenario needs them.

## TDD for the compiler

Start with a Cucumber scenario under `features/`: Ruby source, a Rubast command, and expected output, exit status, or diagnostic code. Run the scenario and observe the failure. Implement the smallest behavior, add focused RSpec examples for the relevant pass, get the scenario green, and then simplify the code. Never weaken an accepted scenario just to make it pass. Rubast steps operate on Ruby files and the CLI.

For a supported program, Cucumber runs the same file under pinned CRuby and Rubast in isolated temporary directories and compares stdout, stderr, and exit status. For an unsupported program, check the diagnostic code and Ruby location without invoking Cargo. RSpec checks normalization, analysis, and generation on small inputs; a wiring spec checks container keys and can substitute the Cargo runner. Run the Rust runtime checks with `cargo test`. Local commands are `bundle exec rubocop`, `bundle exec cucumber --publish-quiet`, `bundle exec rspec`, `cargo fmt --manifest-path runtime/rubast_runtime/Cargo.toml --check`, and `cargo test --manifest-path runtime/rubast_runtime/Cargo.toml`. GitHub Actions runs them on every push and pull request.

The first scenarios are implemented: `puts 42`, signed 64-bit integer boundaries, unsupported constructs and blocks, and a parse error. They exercise CLI → Prism → IR → Rust → Cargo and stop compilation on diagnostics. The current `SourceFile` contains bytes and a path. `CompilationContext`, full `SourceSpan` values, a source map, and separate `emit-rust`/`build` commands remain future work.
