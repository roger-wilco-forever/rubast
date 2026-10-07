# Rubast implementation roadmap

Recorded on 2026-10-06. This is the agreed implementation order, not a claim that the listed Ruby features already work. The current subset is documented in [README.md](../README.md) and exercised by [Cucumber](../features/).

## Starting point

The compiler supports `nil`, signed 64-bit integers, UTF-8 strings, top-level and method locals, `gets`, safe `chomp`, interpolation, `puts`, and stateless user classes. A class can be constructed without arguments; instance methods have required positional scalar arguments and an expression-sequence body with local assignment, `puts`, and last-expression returns. Construction, method results, argument evaluation order, and parameter isolation are compared with CRuby. Instance state and inheritance remain unsupported.

## Completion rule

For every stage:

1. Define accepted inputs and explicitly rejected forms.
2. Add a Cucumber scenario and run it red before implementation.
3. Implement in the owning frontend, analysis, backend, or runtime stage.
4. Compare supported execution with pinned CRuby: stdout, stderr, and exit status. Keep diagnostic codes and Ruby locations for unsupported forms.
5. Add focused RSpec checks for decisions or service wiring that acceptance tests cannot isolate.
6. Run `bin/verify` and update the documented subset and this roadmap's status.
7. Commit and push each completed stage to GitHub before beginning the next stage. Keep implementation, acceptance checks, and documentation together; report the commit and actual push/CI status.

No calendar estimates are assigned yet. Reassess estimates after object state and instance calls establish the cost of extending the implementation. Later stages may be split into smaller changes; a stage is complete only when its stated acceptance behavior works.

## First milestone: a useful stateful class

```ruby
class Greeter
  def initialize(name)
    @name = name
  end

  def greet
    puts "Hello, #{@name}!"
  end
end

Greeter.new("Ada").greet
```

### 1. Inspectable generated projects — complete (2026-10-06)

Add `emit-rust FILE -o DIR`, preserving generated Rust, a Cargo manifest, and the runtime in a chosen directory. Reuse the existing pipeline through `GeneratedProject`; share project writing with `run`. Reject nonempty destinations rather than overwriting files. Do not copy runtime build caches.

**Acceptance:** the saved project builds independently with Cargo and its binary matches both CRuby and `run`, including stdin and EOF. Invalid Ruby leaves no output project. Existing destination files are preserved. CLI usage and output errors have deliberate exit statuses.

**Delivered:** `emit-rust FILE -o DIR`, shared `build.writer`, standalone runtime source without build caches, and `E_OUTPUT` for destination errors. [Emission scenarios](../features/emit_rust.feature) cover independent execution, stdin/EOF, directories with spaces, empty/nonempty destinations, filesystem failures, emission without Cargo, and CLI misuse. `bin/verify` passed: RuboCop, 2 RSpec examples, 43 Cucumber scenarios, Rust formatting, and Cargo tests (zero runtime unit assertions).

### 2. Multi-expression method bodies — complete (2026-10-06)

Support local assignments, expression sequences, `puts` within methods, the last expression's value, and `nil` results for empty bodies. Analyze parameter-dependent operations using argument types while still checking every method for unsupported syntax.

**Acceptance:** method locals do not leak into callers; reassignment and side effects execute in order; empty methods return `nil`; the final assignment, call, or literal returns the correct value.

**Delivered:** sequence and `nil` IR forms, method-local scopes and initialization, expression-valued assignment and `puts`, and argument-specific body validation. Each assignment gets a separate Rust binding so later writes cannot change an earlier read. Argument types are captured during evaluation, before later arguments can reassign their source locals. [Method-body scenarios](../features/method_bodies.feature) cover these behaviors and diagnostics for invalid argument types and unsupported intermediate expressions in unused methods. The Greeter example now has a multi-expression body. `bin/verify` passed: RuboCop, 2 RSpec examples, 54 Cucumber scenarios, Rust formatting, and Cargo tests (zero runtime unit assertions).

### 3. Object state and constructors — planned

Replace the stateless object tag with a shared object handle. Support `@variable` reads and writes and `initialize` with required positional scalar arguments. `new` invokes the constructor and returns the object regardless of the constructor's ordinary result. Initially, fields contain supported scalar values only.

**Acceptance:** the milestone Greeter works; separate instances have separate state; aliases observe the same mutations; unassigned fields read as `nil`; constructor arguments execute once in order. Object-valued fields remain explicitly rejected.

### 4. Instance calls and `self` — planned

Support explicit `self.method` and implicit calls to another method on the current receiver. Emit separate Rust functions with receiver and arguments instead of copying method bodies into each call site. Define visibility for constructor calls before exposing explicit `initialize` calls.

**Acceptance:** nested calls use the same receiver, preserve state and evaluation order, and isolate method-local scopes. Unsupported lookup remains a diagnostic. Recursion is added only with a tested analysis strategy.

### 5. Conditions, arithmetic, and returns — planned

Add `true`, `false`, comparisons, basic integer arithmetic, `if`/`unless`, and explicit `return`, in that order. Define the supported integer range and overflow/error policy before accepting arithmetic. Preserve Ruby truthiness and expression values.

**Acceptance:** zero and empty strings are truthy; branch results, side effects, early returns, and numeric boundaries match CRuby on declared inputs. Unsupported numeric behavior is not silently wrapped or substituted.

### 6. Objects passed between methods — planned

Allow object arguments and results, then object-valued fields. Define memory ownership and cycle handling before supporting arbitrary object graphs. Keep identity when values cross calls or are assigned to another variable.

**Acceptance:** returning or passing an object preserves its identity and shared mutations. Tests cover nested references and the declared behavior or diagnostic for cycles.

### 7. Inheritance — planned

Support a single superclass, inherited method lookup, overriding, and `super`. Define constructor lookup and explicit versus forwarded `super` arguments. Continue rejecting class reopening and dynamic redefinition.

**Acceptance:** inherited and overridden methods, superclass construction, and `super` calls match CRuby, including receiver state and argument side effects.

## Language expansion

### 8. Loops — planned

Add `while`, `until`, `break`, and `next`. Preserve condition timing, truthiness, and control-expression values.

**Acceptance:** counters, condition side effects, skipped iterations, and early exits match CRuby. Test execution has a timeout so regressions cannot hang the suite.

### 9. Arrays and mutable strings — planned

Add array literals, indexing, indexed assignment, `length`, and `push`. Add string concatenation and a documented small set of mutation operations. Use shared identity for mutable built-in values.

**Acceptance:** aliases share mutations; independent objects remain independent; negative indexes, out-of-range access, Unicode, and element evaluation order match CRuby. Errors use the available Ruby error mechanism or the affected forms remain rejected until stage 12.

### 10. Symbols and hashes — planned

Add symbols, hash literals, lookup, assignment, and key-presence checks. Begin with a declared set of built-in key types. Define key equality, insertion order, and missing-key behavior.

**Acceptance:** replacement, traversal order, absent keys versus `nil` values, and aliases match CRuby. User-defined `hash`/`eql?` remain rejected initially.

### 11. Blocks and iterators — planned

Start with `each`, then `times`, `map`, and `yield` in user methods. Support block parameters and captured locals. Add block `break`, `next`, and nonlocal `return` as separate tested increments.

**Acceptance:** captured assignment, nested block scopes, iterator results, and exits reach the correct context. Unsupported control flow remains rejected until implemented; escaped blocks and `Proc` require a separate lifetime contract.

### 12. Exceptions — planned

Introduce structured runtime errors, then `raise`, `rescue`, `ensure`, `else`, and `retry`. Route supported-operation errors through Ruby exception handling. Define uncaught messages, Ruby locations, and exit statuses.

**Acceptance:** `ensure` runs on success, exceptions, and returns; nested handlers, reraising, retries, and uncaught failures match the declared CRuby contract. Accidental Rust panics do not implement Ruby errors.

### 13. Extended method arguments — planned

Add defaults, optional positional arguments, `*args`, required and optional keywords, `**kwargs`, and `&block`, in that order. Evaluate defaults at call time in method scope.

**Acceptance:** omitted arguments differ correctly from explicit `nil`; positional hashes differ from keywords; default side effects occur only when needed; invalid arity and argument kinds have Ruby-compatible errors.

### 14. Modules and the broader class model — planned

Add nested constants, `module`, `include`, `extend`, class methods, and visibility. Then add `attr_reader`, `attr_writer`, and `attr_accessor`. Implement `prepend` separately after `include` lookup is stable.

**Acceptance:** conflicting names, multiple included modules, inheritance, visibility, and `super` choose the same target as CRuby. Dynamic class modification remains outside the supported contract until stage 19.

### 15. Multiple source files — planned

Add `require_relative`, then restricted `require` on known paths. Build a source dependency graph while preserving load order, repeated loads, and circular-load behavior. Initially reject dynamically computed paths. Select real applications before claiming support for particular gems.

**Acceptance:** each required file loads once; load-time side effects and constant availability match CRuby; diagnostics refer to the correct source file. Every dependency is validated before publishing a successful build.

### 16. Practical I/O — planned

Add `print`, `warn`, standard stream objects, then basic file operations. Define encodings, EOF, and I/O errors before declaring support.

**Acceptance:** redirected streams, temporary-file reads and writes, EOF, missing files, and supported encoding behavior match CRuby. Error handling uses stage 12's runtime mechanism.

## Compiler maturity

### 17. Persistent binaries and diagnostics — planned

Add `build`, a persistent binary destination, and a release mode. Extend Ruby-to-Rust source mapping and expose normalized and semantic IR for debugging.

**Acceptance:** the binary runs without Ruby; the saved project builds independently; diagnostics identify Ruby source; retained artifacts reproduce failures. Avoid adding a compilation context until shared per-run data requires it.

### 18. Measured optimization — planned

Choose real benchmark programs and measure compilation time, startup, runtime, memory, and binary size. Add call specialization, reduced cloning, and Cargo build reuse only for observed bottlenecks.

**Acceptance:** an optimization improves a named benchmark and keeps semantic checks green. Record measurement conditions and before/after results; avoid speculative caches or optimization passes.

### 19. Selected dynamic behavior — future evaluation

Evaluate class reopening, method redefinition, `send`, `respond_to?`, `method_missing`, and selected reflection APIs one at a time. Each needs its own compatibility boundary and tests, including interactions with optimized calls.

**Acceptance:** supported changes affect subsequent lookup like CRuby; unsupported dynamic behavior remains explicit. `eval`, arbitrary dynamic loading, native extensions, threads, and `Fiber` are separate major directions with no support commitment yet.

## Next action

Begin stage 3 with differential scenarios for constructor arguments, instance-variable reads and writes, independent instances, aliases that share mutations, and unset fields returning `nil`. Keep later milestones planned until implementation and executed checks establish their behavior.
