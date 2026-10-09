# Compiler artifacts and diagnostics

| Command | Result |
| --- | --- |
| `run FILE.rb` | Build and execute, forwarding stdin/stdout/stderr and program exit status |
| `build FILE.rb -o BIN` | Save an executable without executing the program |
| `emit-rust FILE.rb -o DIR` | Save generated Rust and runtime without invoking Cargo |
| `dump-ir FILE.rb --stage normalized` | Print dependency-expanded normalized IR before semantic validation |
| `dump-ir FILE.rb --stage semantic` | Print validated semantic IR; this stage is the default |

`run` and `build` accept `--release` (optimized Cargo profile) and `--keep-project DIR`. Debug is the default. Build requires an explicit binary destination. Existing files, directories, and dangling links at that destination are rejected with `E_OUTPUT`; there is no overwrite flag. Parent directories are created when the binary is saved. Retained/emitted project destinations must be new or empty. Binary and project destinations cannot contain each other, including through directory aliases.

Compiler/output/build errors exit 2; usage errors exit 64. A successful build or emission exits 0 without printing or executing the program. A run returns the generated program's exit status. Source validation finishes before artifacts are written. An explicitly retained project remains after successful builds, program errors, missing Cargo, or Cargo compilation failures; failures before emission do not create it. Temporary projects are removed when no retained destination is requested.

## Standalone binaries and reproduction

```sh
bundle exec ruby bin/rubast build examples/workloads/multi_file_quote.rb \
  -o target/quote --release --keep-project target/quote-build
target/quote
cargo build --release --offline --manifest-path target/quote-build/Cargo.toml
target/quote-build/target/release/rubast_program
```

Both binaries embed the compiled source dependencies and link the Rust runtime. They need neither Ruby nor Cargo to execute. Runtime data files remain runtime inputs; normal platform shared-library requirements still apply. Release is Cargo's standard optimized profile, not a promise of a measured speedup over CRuby.

To reproduce a Cargo failure, rebuild the directory named in `Generated project retained at ...` with `cargo build` (add `--release` for that profile). Retention includes the manifests, emitted Rust, runtime source, source map, and any Cargo artifacts created before failure. Cargo availability, the Rust toolchain, and the operating system are external build requirements.

## IR inspection

```sh
bundle exec ruby bin/rubast dump-ir examples/workloads/class_definitions.rb --stage normalized
bundle exec ruby bin/rubast dump-ir examples/workloads/class_definitions.rb --stage semantic
```

Dumps contain `version: 1`, `stage`, a `root` reference, and a `nodes` table. Each table entry has its Ruby `type` and either named `members`, array `items`, or hash `entries` and `default`. Composite values use `{"$ref": "ID"}`; symbols use `{"symbol": "name"}`. IDs are local to one dump. This preserves shared references and cycles in object/collection types without recursive expansion. Ruby spans retain source paths, lines, and columns. Normalized inspection can succeed when semantic inspection rejects the program, but parsing/normalization/source-loading errors still fail. IR inspection does not invoke Cargo or execute application Ruby code.

The versioned format is a debugging representation, not a stable semantic IR API or an executable program format. All reference tables are local to a dump; no mutable compilation context is stored in container services.

## Ruby-to-Rust locations

Every generated project has `source-map.json` with `version: 1` and a `files` table. Its `src/main.rs` member maps one-based Rust line numbers to Ruby `path`, `line`, and `column`. Nested source markers in Rust comments identify the innermost emitted IR origin, including loaded files, methods, branches, and inlined blocks. Synthetic scaffolding may use an enclosing Ruby span or have no mapping.

Rubast requests Cargo JSON output. On a build error, a mapped primary Rust span supplies the diagnostic's Ruby location; the original rendered Rust errors remain in the detail for backend debugging. Unmapped generated/runtime lines and Cargo infrastructure errors retain Rust/build locations. The map does not rewrite runtime backtraces, which already carry Ruby locations.

Line mappings describe the exact emitted source. Manual editing or `cargo fmt` can invalidate them; re-emit into a new/empty directory to regenerate a matching map. This stage does not add DWARF Ruby debugging, automatic map updates for edited projects, cross-compilation, build caches, or a `CompilationContext`.
