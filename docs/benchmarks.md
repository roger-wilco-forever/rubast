# Preliminary synthetic benchmark — 2026-10-07

For current sustained application workloads and the stage-18 optimization, see [the practical benchmark](practical-benchmarks.md). This page preserves the original stage-5 experiment.

## Why we are measuring

Rubast explores compiling a useful Ruby subset into standalone native programs: faster startup and execution for repeated runs, lower process memory, and deployment without a Ruby interpreter. This baseline checks whether the current implementation already provides those benefits and records evidence for later optimization. It compares CRuby with **Rubast's emitted Rust**, including its current runtime and cloning, rather than hand-written Rust.

This is an early measurement of the stage-5 subset. It does not complete the measured-optimization milestone or change the roadmap sequence. No compiler optimization was added for this benchmark.

## Conditions and reproduction

- Compiler: `1fcd82c72d89f6b3a5c99b0cc4e84213f6b97ff8`.
- CRuby 3.4.5, default interpreter configuration; `RUBYOPT` was empty.
- Rust/Cargo 1.95.0, ordinary `cargo build --release --offline`; `RUSTFLAGS` was empty. No custom LTO, native CPU flags, or stripping.
- Linux 7.1.8, AMD Ryzen 9 7900, 24 available logical CPUs; no CPU affinity restriction. The host was not dedicated to benchmarking.
- Python 3.14.7, standard library only. GNU `/usr/bin/time` measures peak RSS in KiB.

From the repository root, with its Ruby dependencies installed:

```sh
python3 benchmarks/synthetic.py
```

The destination `target/synthetic-benchmark/` must not exist. For another run, pass a new `--output` directory. The runner keeps generated Ruby, emitted Cargo projects, binaries, and JSON samples. `--batches`, `--operations`, and `--samples` select workload sizes and repetitions. The small executable correctness check is:

```sh
python3 benchmarks/synthetic.py --output target/synthetic-check --batches 1 --operations 2 --samples 1
```

The committed [raw results](../benchmarks/results/2026-10-07.json) contain all samples, versions, source and generator hashes, input hash, affinity, generation/build times, and binary sizes. The [runner](../benchmarks/synthetic.py) regenerates the sources. Final local artifacts from this measurement are in `target/synthetic-final/`.

## What is timed

Time is end-to-end wall time of a **new process**: launch, source parsing for CRuby, program execution, and exit. It includes the harness's launch/wait overhead. It excludes Rubast generation and Cargo compilation. The target processes run directly, without Bundler; `rubast run` is not used for timing because it performs a fresh debug build.

Each workload is emitted and built once into a fresh Cargo project. Before measurements, successful exit status, stdout, and stderr must agree with CRuby on three inputs: EOF, `alternate\n`, and a 897-byte UTF-8 line containing repeated `Ada λ `. Timing uses the UTF-8 input. Only the final result is printed; measured output goes to `/dev/null` for both programs.

There are 3 untimed warmups per engine, followed by 21 timed runs per engine. Ruby/Rust order is shuffled with a fixed seed within each pair. Reported times are medians. OS caches are warm; the Ruby interpreter is still started for every run. Peak RSS is measured separately in 7 new processes per engine; the table reports the median of those per-process peaks, not allocator-only memory. Verification and benchmark execution ran separately.

A step is one repeated source fragment, not a hardware instruction or a uniform operation across workloads. There are 50 steps inside a shared instance method and either 20 or 200 top-level calls: 1,000 or 10,000 steps total.

| Workload | Repeated work |
| --- | --- |
| Startup | `puts 0`, with no class or work steps |
| Arithmetic | Bounded multiply/add/modulo on an input-selected integer |
| Conditions | Integer comparison and selected add/subtract branch |
| Methods | Instance helper call performing bounded integer arithmetic |
| Fields | Helper call reading and mutating an integer instance field on one shared object |
| Strings | Safe `chomp`, comparison with the previous result, and UTF-8 interpolation; text length stays bounded |

## Execution and memory results

Speedup = Ruby time / Rust time. RSS ratio = Ruby peak RSS / Rust peak RSS. A ratio above 1 means the compiled program took less time or resident memory.

| Workload | Ruby ms | Rust ms | Speedup | Ruby RSS MiB | Rust RSS MiB | RSS ratio |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| startup (0 steps) | 29.938 | 0.684 | 43.74× | 13.36 | 2.09 | 6.40× |
| arithmetic (1,000 steps) | 30.642 | 0.719 | 42.62× | 13.56 | 2.11 | 6.43× |
| conditions (1,000 steps) | 29.683 | 0.646 | 45.96× | 13.52 | 2.11 | 6.41× |
| methods (1,000 steps) | 31.048 | 0.706 | 43.96× | 13.21 | 2.25 | 5.88× |
| fields (1,000 steps) | 30.106 | 0.729 | 41.29× | 13.00 | 2.24 | 5.81× |
| strings (1,000 steps) | 31.164 | 0.914 | 34.10× | 14.32 | 2.39 | 6.00× |
| arithmetic (10,000 steps) | 30.428 | 0.876 | 34.72× | 13.38 | 2.23 | 6.00× |
| conditions (10,000 steps) | 31.172 | 0.900 | 34.65× | 13.52 | 2.25 | 6.02× |
| methods (10,000 steps) | 35.683 | 1.127 | 31.66× | 13.37 | 2.24 | 5.97× |
| fields (10,000 steps) | 47.368 | 1.763 | 26.86× | 13.55 | 2.29 | 5.93× |
| strings (10,000 steps) | 35.915 | 3.204 | 11.21× | 16.34 | 2.68 | 6.11× |

For the 10,000-step workloads, observed process speedups range from approximately **11× to 35×**, and peak RSS is approximately **5.9× to 6.1× lower**. The startup control alone is about **44× faster**, so most of the large short-program speedup comes from avoiding interpreter startup. These are process-run benefits; they do not establish that individual arithmetic operations or method calls are faster by those factors.

The field workload had substantial timing variation. Keep its median as an observation, but repeat under controlled host load before using that ratio to guide an optimization. Sub-millisecond results are also sensitive to launch overhead and scheduling. Observed ranges:

| Workload | Ruby min–max ms | Rust min–max ms |
| --- | ---: | ---: |
| startup (0 steps) | 28.694–36.433 | 0.471–0.761 |
| arithmetic (1,000 steps) | 29.100–32.340 | 0.511–0.952 |
| conditions (1,000 steps) | 28.808–34.194 | 0.504–0.871 |
| methods (1,000 steps) | 28.720–32.793 | 0.527–0.980 |
| fields (1,000 steps) | 28.470–33.612 | 0.527–0.951 |
| strings (1,000 steps) | 29.810–39.002 | 0.762–1.143 |
| arithmetic (10,000 steps) | 28.944–33.763 | 0.691–1.269 |
| conditions (10,000 steps) | 29.172–34.618 | 0.705–1.111 |
| methods (10,000 steps) | 30.101–47.945 | 0.836–1.701 |
| fields (10,000 steps) | 30.544–72.143 | 1.102–5.394 |
| strings (10,000 steps) | 34.440–37.878 | 2.996–3.811 |

## Generation, build, and binary size

These are separate single observations, not medians. Generation includes starting the Ruby compiler through Bundler and writing the project. Cargo builds each fresh project independently; no project build cache is reused. Peak compilation memory was not measured.

| Workload | Emit seconds | Release build seconds | Binary KiB |
| --- | ---: | ---: | ---: |
| startup (0 steps) | 0.286 | 0.233 | 445.1 |
| arithmetic (1,000 steps) | 0.277 | 0.457 | 510.5 |
| conditions (1,000 steps) | 0.297 | 0.667 | 532.3 |
| methods (1,000 steps) | 0.289 | 0.609 | 541.5 |
| fields (1,000 steps) | 0.298 | 0.515 | 534.1 |
| strings (1,000 steps) | 0.277 | 0.892 | 571.9 |
| arithmetic (10,000 steps) | 0.477 | 3.362 | 644.7 |
| conditions (10,000 steps) | 0.669 | 3.778 | 666.5 |
| methods (10,000 steps) | 0.723 | 3.220 | 683.4 |
| fields (10,000 steps) | 0.760 | 3.148 | 677.6 |
| strings (10,000 steps) | 0.418 | 4.071 | 812.0 |

Compilation must be amortized over repeated executions. A one-off invocation that generates and builds first takes longer than directly running these small Ruby sources. Larger unrolled sources also increase build cost; an exploratory 1,000-call release build was stopped and is excluded from this completed baseline.

## Limits and next measurements

Loops are not supported yet, so this benchmark unfolds repeated work into source code. It measures this exact subset, startup, and source-size scaling. It is not a sustained-loop throughput benchmark, and release compilation can fold or eliminate pure computations. Input selection keeps the program result dependent on runtime input, but does not prevent optimization within it.

The memory tests use one object and bounded strings. They do not characterize many-object allocation, cycles, reclamation, or long-lived memory growth; the current runtime retains object entries until process exit. CRuby parsing and interpreter memory are included in RSS, which is appropriate for the process comparison.

Keep these samples as the initial baseline. After loops are supported, add long-running workloads with stable source size and report startup and sustained execution separately. Benchmark object allocation once object lifetimes are part of the supported contract. Optimize cloning, field lookup, or emission only when a named measurement and profiling justify the change.

## Validation

All 11 workload/size pairs matched CRuby on all 3 inputs. The complete `bin/verify` passed: RuboCop, 2 RSpec examples, 149 Cucumber scenarios (515 steps), Rust formatting, and Cargo build/doc-test checks (0 Rust assertions). Generated benchmark Ruby is excluded from RuboCop as a build artifact under `target/`.
