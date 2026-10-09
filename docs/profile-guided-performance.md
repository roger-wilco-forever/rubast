# Profile-guided performance — stage 20, 2026-10-09

This experiment refreshes the stage 19 baseline and profiles the existing million-iteration workloads. The measured runtime change is one #[inline] attribute on Runtime::enter. It makes the frame-push implementation available for optimization in generated caller functions across the runtime crate boundary. Frame storage, exception snapshots, causes, Ruby locations, and control flow retain their existing behavior.

## Method and reproduction

The existing [practical runner](../benchmarks/practical.py) retains default settings: 21 timed process runs per engine, three warmups, seven separate peak-RSS samples, and three fresh generation/release builds per workload. The paired run shuffles CRuby/current-Rust/retained-stage-19-Rust order with seed 42, pins children to one allowed CPU, and compares exact stdout/stderr/status on EOF, alternate input, and the long UTF-8 input. The final paired timing window ran separately from profiling and full verification. The host is shared.

```sh
python3 benchmarks/practical.py --output target/practical-stage20-before
# After applying the runtime change:
python3 benchmarks/practical.py --output target/practical-stage20-measured-after \
  --compare target/practical-stage20-before/results.json
```

Use new output directories when reproducing. The baseline must be built from compiler commit 3345342 with the current benchmark runner; its updated inventory includes native JSON metadata. Both committed reports record that commit and a dirty worktree. Their runtime hashes distinguish the two states. Independent checks confirm that exceptions.rs is the only changed compiler/runtime source between the inventories; its baseline bytes match that commit. Workload/dependency sources and runner hashes match.

[Baseline artifacts and initial samples](../benchmarks/results/2026-10-09-stage20-before.json) and [paired final samples](../benchmarks/results/2026-10-09-stage20-after.json) retain every observation, input/source/binary hashes, flags, CPU/affinity, versions, and build measurements. Timed execution excludes compilation and includes process startup/exit. GNU time measures process peak RSS.

## Final execution and memory results

All entries use the final paired-run medians, including freshly re-measured retained baseline binaries. Initial baseline-report timings are not used in these tables. Positive change means less elapsed time than the retained baseline.

| Workload | CRuby ms | Baseline Rust ms | Final Rust ms | Rust change | CRuby / final Rust |
| --- | ---: | ---: | ---: | ---: | ---: |
| startup | 27.754 | 0.514 | 0.510 | +0.66% | 54.39× |
| quote_requests | 133.221 | 384.994 | 372.389 | +3.27% | 0.36× |
| invoice_summaries | 541.863 | 661.927 | 633.333 | +4.32% | 0.86× |
| receipt_labels | 243.569 | 228.711 | 231.426 | -1.19% | 1.05× |

The observed median improvement is 3.27% for quote calculations and 4.32% for invoice summaries. Quote and invoice programs remain slower than CRuby, by about 2.80× and 1.17× respectively. Receipt formatting is 1.19% slower than the retained Rust baseline in this window and about 1.05× faster than CRuby. Receipt has no sustained user-method frame pushes; the measured regression is reported without attributing it to a particular instruction. Startup changes are small. Timing ranges overlap, so these are observations on this host rather than a universal throughput guarantee.

| Workload | CRuby min–max ms | Baseline Rust min–max ms | Final Rust min–max ms |
| --- | ---: | ---: | ---: |
| startup | 27.386–28.119 | 0.486–0.663 | 0.487–0.578 |
| quote_requests | 131.409–173.240 | 356.930–401.777 | 351.057–379.602 |
| invoice_summaries | 519.929–580.045 | 652.411–688.704 | 624.355–657.966 |
| receipt_labels | 237.189–266.032 | 225.586–309.943 | 227.305–257.968 |

| Workload | CRuby RSS MiB | Baseline Rust RSS MiB | Final Rust RSS MiB |
| --- | ---: | ---: | ---: |
| startup | 13.71 | 2.07 | 2.07 |
| quote_requests | 13.75 | 2.12 | 2.13 |
| invoice_summaries | 14.33 | 2.26 | 2.23 |
| receipt_labels | 15.09 | 2.08 | 2.07 |

RSS differences between the Rust versions are small and do not establish a reclamation improvement. The arena still retains objects until exit. Final Rust process RSS is about 6.4–7.3× lower than CRuby for these bounded workloads.

## Build costs

| Workload | Emit s | Cargo s | Total build s | Binary KiB |
| --- | ---: | ---: | ---: | ---: |
| startup | 0.281 | 0.738 | 1.013 | 511.8 |
| quote_requests | 0.277 | 1.124 | 1.401 | 599.6 |
| invoice_summaries | 0.282 | 1.093 | 1.375 | 608.4 |
| receipt_labels | 0.269 | 0.848 | 1.120 | 541.4 |

Each build uses a fresh project and Cargo target directory. Separate medians need not add exactly. Build peak memory was not measured. The default release flags are unchanged; retained binaries and their hashes remain under the recorded target paths.

## CPU profile and selected change

The [profiling runner](../benchmarks/profile.py) uses the [small glibc sampler](../benchmarks/profile_cpu.c), installed GCC and GNU gprof, and separate copies of the generated projects. It snapshots executable CPU histograms over 31 process runs. All three benchmark inputs match the retained binary, and each sampled run matches the long-input result. It checks usable gmon records and retains child CPU time, profile binary/sampler hashes, flags, and raw histogram files.

```sh
python3 benchmarks/profile.py \
  --project target/practical-stage20-before/quote_requests-0 \
  --output target/profile-stage20-before-quote
# Repeat for invoice_summaries and receipt_labels, then for final projects.
```

The profiler requires 64-bit Linux/glibc, GCC, and GNU gprof. Its copied projects use -C relocation-model=static -C link-arg=-no-pie -C debuginfo=1 so sampled addresses map to executable symbols. These profile builds are separate from the default release timing builds. Sampling covers the main executable, including statically linked Rust code; shared-library samples are excluded. It records CPU samples rather than instrumented call counts. Inlining and merged symbols limit attribution, and percentages describe sampled executable time.

Before optimization, Runtime::enter accounts for 10.75% of executable samples in quote_requests and 7.45% in invoice_summaries. Disassembly shows each call copying a 72-byte Location into the frame vector. It is the largest separately named runtime function in the quote profile; invoice field lookup is larger at 16.49% and remains unchanged. Making enter inlineable allows caller optimization of frame construction/push while retaining owned Location snapshots. An inlined cost moves into caller symbols; disappearance of a standalone symbol does not prove that its work is free.

A preliminary static-reference frame representation was evaluated. Its paired quote improvement was about 2%, versus about 3.3% for the final one-line change. The existing representation was retained for the final implementation. Preliminary and interrupted runs are excluded from the final result tables.

Profile summaries and flat reports: [raw profiles](../benchmarks/results/2026-10-09-stage20-profiles.json). Raw gmon files and copied profile binaries remain in the target paths recorded there.

## Verification

Final bin/verify passed: RuboCop (94 files), six RSpec examples, 998 Cucumber scenarios (3,491 steps), Rust formatting, and Cargo tests (zero runtime unit/doc assertions). Focused execution checks also passed for first-backtrace preservation, exception equality, hook/native I/O errors, and application workloads. Python byte-compilation, strict GCC compilation, profiler self-checks, sample counts, retained binary hashes, and matching inventories were checked separately. No Ruby support boundary changes in this stage.
