# Memory management (stage 22)

The runtime now reclaims unreachable instances, arrays, and hashes, including mixed cycles. Reachable aliases retain their identity and shared mutations. The selected language API is zero-argument `GC.start` (also `::GC.start`), returning `nil`; lexical user constants named GC keep ordinary lookup priority. [Differential scenarios](../features/garbage_collection.feature) compare complete execution with pinned CRuby.

## Ownership and collection

An arena slot owns its object storage and a weak handle token. Each `Value::Object` owns a strong handle token. Collection counts direct incoming handles in instance fields, array slots, and hash keys/values. A token with more strong references than incoming arena references is a root. An iterative mark traverses its object graph; sweeping releases unmarked storage and returns slots to a free list. New tokens distinguish identities when slots are reused. No unsafe code or new dependency is involved.

This covers locals, constants, class/module state, receivers, evaluated arguments, splat/rest copies, return values, captured block locals/self, temporary collection results, and pending `Outcome`/`Flow::Exit` values. Values in an allocation's not-yet-inserted payload also remain roots while collection runs. Supported exceptions use shared scalar messages and acyclic cause chains, retained by their existing reference counts and exception context. No separate emitted root stack is required.

Collection runs before an allocation after 256 arena allocations. After each collection its next allocation budget is the greater of 256 and twice the retained object count, avoiding repeated whole-heap scans for a growing live graph. `GC.start` forces the same collection and resets that budget. Strings contain bytes rather than object edges; their buffers already use reference counting. Sweeping a dead object releases its string references too.

The implementation lives in [heap.rs](../runtime/rubast_runtime/src/heap.rs); existing runtime allocation/access methods use that heap. Analysis resolves only the selected GC call into the existing Builtin IR, and the backend emits the runtime collection plus `Value::Nil`. Source mapping and artifact serialization retain the call's Ruby span.

## Boundaries

Generated Rust temporaries conservatively remain roots until their Rust scope ends. Reassignment or Ruby's last use does not guarantee immediate reclamation. Returning from an ordinary method drops its temporaries, allowing later collections to reclaim discarded batches. No liveness pass, moving collector, finalizers, weak Ruby references, or retained closures are introduced.

Slots and free-list capacity retain their high-water metadata and are reused. A collection scans slots and object edges; it does not compact the slot table or promise to return every freed byte to the OS allocator. Reachable growing graphs require growing memory. Object counts and process peak RSS therefore measure different things.

GC options, blocks, safe navigation, disable/enable/stat, ObjectSpace APIs, and mutation of the built-in namespace remain diagnostics. Existing analysis limits are unchanged: fresh arena allocation under while/until and user-yield bodies remains unsupported; built-in literal iterators retain their 1,000-body/10,000-allocation ceilings. The collector establishes runtime reclamation, not arbitrary unbounded Ruby allocation support. Native error messages containing object cycles are outside the Ruby exception contract.

## Reproducible retention experiment

The [native harness](../benchmarks/memory_workload.rs) creates an instance → hash → array → instance cycle with a fresh 4,096-byte string payload, then drops its external handles. A separate rooted array keeps either no cycles or every cycle. It checks collection operations and a deterministic checksum throughout. Automatic collection runs during allocation; one explicit collection precedes the final retained-object observation. A checkpoint records `[completed_cycles, retained_objects, arena_slots]` every 1,000 cycles.

This is a direct runtime stress test, **not generated Rust for an accepted unbounded Ruby program**. The compiled [Ruby batch](../examples/workloads/memory_batch.rb) separately demonstrates the supported finite method/iterator path and produces `19900` and `true` under both engines. Runtime tests also check actual buffer release, rooted aliases, pending payloads/exits/exceptions, slot reuse over 20,000 cycles, and a 20,001-object graph without recursive marking.

Reproduce with a new result path:

```sh
python3 benchmarks/memory.py --output benchmarks/results/memory-reproduction.json
```

The [runner](../benchmarks/memory.py) reconstructs stage 21 at `b8978ebb0b1155a6b659b8ef3e3e5bf23f0e1515` and copies the current runtime into separate retained Cargo projects. The baseline receives only a retained-object/slot count accessor and a no-op collection method so the identical harness can observe its original retention behavior. Both build with `cargo build --release --offline`. The report includes that exact instrumentation, runtime/source/runner/binary hashes, platform/toolchain versions, CPU model, and raw samples. Retained projects are under `target/<result-stem>/before/` and `after/`.

The [2026-10-10 report](../benchmarks/results/2026-10-10-memory-final.json) uses Linux, Rust/Cargo 1.95.0, Python 3.14.7, AMD Ryzen 9 7900, and CPU 0. Three shuffled fresh-process peak-RSS observations per engine/case use GNU time, separately from internal object counts. Results after the final collection:

| Cycles / retention | Arena objects before | Arena objects after | Median peak RSS before (KiB) | Median peak RSS after (KiB) |
| --- | ---: | ---: | ---: | ---: |
| 1,000 / discard | 3,001 | 1 | 7,088 | 2,732 |
| 10,000 / discard | 30,001 | 1 | 51,248 | 2,684 |
| 50,000 / discard | 150,001 | 1 | 248,608 | 2,696 |
| 1,000 / retain | 3,001 | 3,001 | 7,076 | 7,332 |
| 10,000 / retain | 30,001 | 30,001 | 51,760 | 53,368 |

Discarded cycles reuse a maximum of 259 slots across all measured sizes. The 50,000-cycle case reduces peak RSS by about 98.9%; the rooted 10,000-cycle control retains all objects and uses about 3.1% more peak RSS. Handle tokens and heap metadata have a cost. These samples establish bounded retention for this workload, not a general memory ceiling or a speed improvement. Execution time, compilation time/memory, CRuby memory, and the stage 18/20 application timings were not measured again.

## Verification

The initial six new execution scenarios failed before implementation, while all seven unsupported API cases retained their diagnostics. The final focused feature passes 16 scenarios and 56 steps; Cargo passes seven reclamation tests. The complete local gate is recorded in [the roadmap](roadmap.md).
