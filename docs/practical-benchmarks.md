# Application-shaped benchmark and measured optimization — 2026-10-09

This stage measures sustained work with stable source size, after stage 17's persistent builds. It compares pinned CRuby with Rubast's emitted release programs, including the generic Value runtime, object fields, call frames, and string allocation. It does not compare Ruby with hand-written Rust.

The stage-5 [synthetic baseline](benchmarks.md) remains a historical startup/source-size measurement. Its large short-process speedups do not establish sustained throughput. The current experiment uses one million iterations, separately measures a startup control, and records compilation costs and peak process RSS.

## Programs and correctness

| Workload | Application task |
| --- | --- |
| startup | Print `0` without classes or work iterations |
| quote_requests | Reuse the existing multi-file Shop classes, update subtotal/discount, call prepended/inherited tax methods, and accumulate a bounded checksum |
| invoice_summaries | Load the unchanged invoice fixture, reuse customer/line/invoice objects, change quantities, and format UTF-8 summaries |
| receipt_labels | Form a receipt body from customer input and varying integer totals; modeled on receipt export, without file I/O |

[Workload sources](../benchmarks/workloads/) have constant-size loops with literal bounds of 1,000,000. Checksums reduce their previous value before addition to remain within the current conservative integer-range proof. Strings have bounded lengths, and objects are reused; original example fixtures are unchanged. The invoice fixture prints its original demonstration once when loaded, followed by the benchmark's final result. Only final workload results are printed, not every iteration. Receipt formatting does not measure filesystem or device throughput.

Before timing, every workload must match CRuby's exact stdout, stderr, and exit status on EOF, `alternate\n`, and a 897-byte UTF-8 line containing repeated `Ada λ `. Baseline, optimized, and retained old binaries all participate in the same checks. The long input is used for timing. Cucumber additionally executes all three workloads and checks frozen/shared interpolation semantics.

## Conditions and reproduction

The [runner](../benchmarks/practical.py) uses Python's standard library and the existing synthetic runner's process/version helpers and input fixtures. Default settings are 21 process runs per engine, 3 untimed warmups, 7 separate peak-RSS samples, and 3 fresh generation/release-build samples per workload. Ruby/current-Rust/old-Rust order is shuffled within each sample using seed 42. All child processes inherit one allowed CPU selected by the runner. OS caches are warm; no Cargo target directory is reused across build samples. The host is shared, not dedicated to benchmarking. Compiler checks run separately from timing.

```sh
python3 benchmarks/practical.py --output target/practical-current
python3 benchmarks/practical.py --output target/practical-comparison \
  --compare target/practical-baseline/results.json
```

The output directory must not exist, CRuby must match `.ruby-version`, and CARGO_TARGET_DIR must be unset for fresh builds. `--samples`, `--build-samples`, and `--rss-samples` change repetition counts. Each output keeps generated projects, runtime sources, release binaries, input, and JSON measurements. Comparison mode verifies the retained old binaries' hashes and that workload/dependency source hashes match, then re-measures those binaries alongside the current programs. It never recompiles the old binaries.

To regenerate a baseline, use compiler commit `763db4b` in a separate checkout with the current benchmarks/practical.py and benchmarks/workloads files copied into it; the examples and synthetic helper already exist there. Keep its output, then run comparison mode with the optimized compiler. Paths in compiled diagnostic strings may differ between checkouts, so byte-identical binaries are not promised. This recorded experiment used the same source paths for both builds, temporarily restored the original stage-17 runtime for the baseline, and restored the optimized runtime before comparison. Source hashes distinguish the two compiler states even though both measurements precede the stage-18 commit.

Raw reports record versions, UTC timestamps, CPU and affinity, Ruby/Rust flags, runner/source/binary/input hashes, all timing/RSS samples, and fresh build durations. Target commands run directly without Bundler or `rubast run`. Timed wall time includes process creation, CRuby parsing/loading, workload execution, and exit; it excludes Rubast/Cargo compilation. Peak RSS comes from GNU /usr/bin/time in KiB, not allocator-only live data.

## Execution, startup, and process memory

Raw data: [unoptimized builds and samples](../benchmarks/results/2026-10-09-practical-before.json), [paired current/retained-baseline samples](../benchmarks/results/2026-10-09-practical-after.json). Both record compiler commit `763db4bf0c4376982e91a4cbf48d9326bd07d125` and a dirty worktree; the recorded runtime/source hashes identify the original and optimized states. The runner hash matches the committed runner.

CRuby 3.4.5, Rust/Cargo 1.95.0, Python 3.14.7, Linux 7.1.8, AMD Ryzen 9 7900, CPU affinity `{0}`. RUBYOPT/RUSTFLAGS were empty. No concurrent compiler verification ran during the measurements. All figures below are medians from the paired comparison, so the old/current binaries were sampled in the same measurement window. Ratio = CRuby time / current Rust time; below 1 means Rust was slower.

| Workload | CRuby ms | Old Rust ms | Current Rust ms | CRuby / Rust | Rust change |
| --- | ---: | ---: | ---: | ---: | ---: |
| startup | 27.323 | 0.515 | 0.521 | 52.45× | -1.07% |
| quote_requests | 131.707 | 419.631 | 422.709 | 0.31× | -0.73% |
| invoice_summaries | 535.806 | 811.040 | 737.930 | 0.73× | +9.01% |
| receipt_labels | 246.091 | 326.272 | 298.746 | 0.82× | +8.44% |

The targeted change improves invoice formatting by **9.0%** and receipt formatting by **8.4%** against retained unoptimized Rust binaries. Startup and quote changes are small and negative, not evidence of a string-copy improvement. The startup control is about **52× faster**, but all three million-iteration native programs remain slower than CRuby: quote calculations take about 3.2× as long, invoice summaries about 1.38×, and receipt labels about 1.21×. Do not transfer the startup ratio to sustained throughput. The compiler currently trades faster short-process startup and lower process RSS for generic-runtime overhead on these long workloads.

| Workload | CRuby RSS MiB | Current Rust RSS MiB | CRuby / Rust RSS |
| --- | ---: | ---: | ---: |
| startup | 13.75 | 2.07 | 6.64× |
| quote_requests | 13.75 | 2.18 | 6.31× |
| invoice_summaries | 14.32 | 2.24 | 6.40× |
| receipt_labels | 15.09 | 2.25 | 6.71× |

Resident memory is roughly **6.3–6.7× lower** in the compiled processes. The interpolation change does not establish a consistent peak-RSS reduction over old Rust: allocator/page variation is larger than some observed changes. This is a per-process memory benefit, not proof of object reclamation or lower live heap usage.

Timing ranges disclose host/process variation:

| Workload | CRuby min–max ms | Old Rust min–max ms | Current Rust min–max ms |
| --- | ---: | ---: | ---: |
| startup | 26.836–28.557 | 0.495–0.672 | 0.488–0.538 |
| quote_requests | 130.392–147.767 | 409.706–462.805 | 414.114–468.932 |
| invoice_summaries | 518.459–586.953 | 791.525–862.207 | 714.386–814.067 |
| receipt_labels | 235.122–262.026 | 323.083–368.527 | 295.605–328.313 |

## Generation, compilation, and binary size

Each build sample starts from a fresh project/target directory. OS caches are warm. Generation includes the Ruby compiler's Bundler startup and writing all runtime/source-map files; Cargo compilation is measured separately. The table uses separate medians for emission, Cargo, and their per-sample total, so the first two medians need not sum exactly to the third. Build peak memory was not measured. Binary sizes are the unstripped standard release executables.

| Workload | Emit seconds | Cargo seconds | Total build seconds | Binary KiB |
| --- | ---: | ---: | ---: | ---: |
| startup | 0.247 | 0.704 | 0.975 | 511.8 |
| quote_requests | 0.268 | 1.064 | 1.333 | 599.4 |
| invoice_summaries | 0.277 | 1.049 | 1.328 | 608.6 |
| receipt_labels | 0.264 | 0.797 | 1.063 | 541.8 |

Fresh emission/release builds take approximately **1.0–1.3 seconds** for these sources. A one-off compile-and-run costs more than directly running Ruby. There is no CPU-time amortization advantage for the million-iteration workloads while their native execution remains slower. Independent binaries and lower process memory are still useful outcomes; future execution improvements must be measured rather than assumed.

The recorded projects remain under target/practical-stage18-million-before and target/practical-stage18-million-after. Their release binaries match CRuby on all three inputs. The raw reports retain per-build observations and hashes for independent reproduction.

## Optimization and boundaries

Code inspection of the measured string workloads found an intermediate String clone for every string part in Runtime::interpolate. The optimization appends a borrowed string's bytes directly into the independent result buffer. Other scalar conversions keep their existing path. Results remain mutable, source aliases remain shared, frozen inputs retain their state, and no Rust borrow escapes the operation. This removes intermediate string copies; it does not remove source literals, integer conversion allocations, call frames, or the final owned string.

No call specialization change, build cache, allocation reclamation, custom LTO, native CPU tuning, or new Ruby support was added. The startup/quote control is included to reveal changes outside the string-heavy workloads; small differences there should not be attributed to eliminated interpolation copies. Runtime profiling beyond this targeted inspection remains necessary before choosing the next optimization.

Sustained results apply to these exact bounded programs and inputs. They do not establish gem compatibility, many-object lifetimes, GC behavior, long-running object growth, arbitrary Ruby, other machines, or I/O throughput. The runtime retains arena objects until exit; these cases reuse a small fixed set. Ruby and Rust may optimize computations differently; runtime inputs, field updates, final strings, and checksums prevent the benchmark from consisting only of unused constant results, but no instruction-level throughput claim is made.

## Verification

The complete bin/verify passed: RuboCop (87 files), 6 RSpec examples, 902 Cucumber scenarios (3,160 steps), Rust formatting, and Cargo tests (zero runtime unit/doc assertions). The full Cucumber run included the final million-iteration workloads. Each measured program matched CRuby on all three inputs, and paired measurements also checked the retained old binaries. Independent checks verified sample counts, measured binary hashes, current compiler/workload/runner hashes, and the original runtime hash against stage 17. No unsupported Ruby diagnostic was removed.
