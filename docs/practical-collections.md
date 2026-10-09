# Practical collections

Stage 21 selects finite batch processing rather than an unbounded heap model. [Order processing](../examples/workloads/order_batch.rb) allocates independent line objects, hashes, and note arrays, preserves aliases, and totals a runtime-dependent number of charges. [Log processing](../examples/workloads/log_batch.rb) inspects at most three input lines, filters known statuses, and looks up their String labels. The original streaming log and shopping-cart fixtures remain unchanged and retain their documented blockers.

## String hash keys

Hash literals and indexed writes accept direct String literals in addition to the existing single-valued Symbol/Integer keys. Equality compares UTF-8 contents and distinguishes Strings from Symbols and Integers. Inserting a mutable String copies and freezes its contents; an already frozen key can be retained. Replacement preserves the first key and insertion position. `keys` returns the stored frozen String references; `dup` makes a mutable copy. Frozen mutation raises `FrozenError` with the existing Ruby location and inspection rules. Values retain aliases.

`[]` and `key?` also accept runtime String expressions. Analysis joins every possible String-key value with the missing-key `nil` result; unrelated Symbol/Integer entries are excluded. Existing object/scalar and different-object joins still reject unsafe results. Literal selectors retain their precise field type. Keyword-rest copies preserve String keys without promoting them to Symbols.

Computed/local/parameter String insertion keys remain `E_UNSUPPORTED`, including frozen variables. This selection avoids pretending analysis knows a mutable key's current contents or accepting unknown key growth. Boolean/nil/custom keys, deletion, custom hashing/equality, hash iteration, and default values remain outside the contract. Hash key/order limits remain 10,000 entries and 32 insertion orders; `keys`/`values` still require one order.

## Bounded runtime shapes

Arrays can retain a known minimum/maximum length after branches and finite appends. Integer reads use the current possible lengths, including negative indexes and missing-slot `nil`. `push`/`<<` summarize possible append positions and enforce the 10,000-slot ceiling. Slots absent on a branch are distinct from stored `nil`; a traversal only reads a slot after its runtime length guard succeeds. Indexed writes, concatenation, and active argument splats retain their exact-length requirement. Joins of different element handles remain diagnostics.

`each`/`map` accept these arrays, and `times` accepts a bounded integer range. Analysis validates up to the maximum count and joins skipped/executed states for optional steps. Generated Rust captures the receiver once and tests the runtime count before an optional invocation; map stores only actual results. Captures, fresh block locals, slot mutation, next/break/return targets, exceptions, cleanup, and backtraces use the existing contracts. Function specialization includes the guarded step pattern.

The traversed array's length range must stay unchanged throughout the body and on control/exception exits. Appending through any alias during traversal remains a located diagnostic. There is no acceptance of external arrays with an unknown length or element type, unrestricted collection growth, enumerators, `sum`, or Symbol-to-Proc.

Existing result joins still require the same object handle. For example, `values.push(3) if input` produces an array-or-nil expression and is rejected; use a conditional whose branches end in `nil` when only the mutation is needed. This restriction is independent of the now-supported length range.

## Allocation limits

Finite built-in iterator bodies may create user objects, arrays, hashes, `keys`/`values` arrays, concatenated arrays, and nested maps. Each executed site creates distinct storage; references stored in other collections preserve identity. Objects inside a `while`/`until` ancestor, including called helpers and nested iterators, remain rejected. Yielded user-method bodies keep their existing allocation boundary.

The per-compilation budget is 1,000 block-body validations and 10,000 tracked arena allocations inside bounded iterator bodies. Nested, unused, dead, and speculative checks conservatively consume these budgets. Exceeding a budget produces `E_UNSUPPORTED` at the block before Rust emission. These are analysis ceilings, not a runtime memory quota: strings and allocations outside iterator bodies retain their existing contracts. The admitted explicit allocation sites have a finite invocation bound; the arena still retains unreachable objects until program exit. Stage 22 must add reclamation before claiming sustained unbounded allocation.

## Verification

[Differential scenarios](../features/practical_collections.feature) exercise both optional lengths, empty input, aliases, independent allocations, Unicode/frozen keys, keyword copies, dispatch reuse, block exits, cleanup, and uncaught errors. Former finite allocation/count diagnostics execute their original source against CRuby. Unsupported key/shape/allocation cases require a located diagnostic and no emitted project. The allocation ceiling also failed its assertion before implementation.

Final `bin/verify` passed: RuboCop (96 files), 6 RSpec examples, 1,031 Cucumber scenarios (3,621 steps), Rust formatting, and Cargo tests (zero runtime unit/doc assertions). Workload cases also pin successful CRuby outputs. The retained release project at `target/order-batch-stage21-final/` matches CRuby with gift, ordinary input, and EOF. Guarded semantic IR serialization and local documentation links were checked separately. Performance benchmarks were not rerun; no speed or reclaimed-memory claim is made.
