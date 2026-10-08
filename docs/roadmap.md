# Rubast implementation roadmap

Recorded on 2026-10-06. This is the agreed implementation order, not a claim that the listed Ruby features already work. The current subset is documented in [README.md](../README.md) and exercised by [Cucumber](../features/).

## Starting point

The compiler supports `nil`, booleans, signed 64-bit integers, UTF-8 strings, locals, `gets`, safe string `chomp`, interpolation, `puts`, and user classes with constructors and scalar/object instance state. Instance methods support expression sequences, nested calls, scalar conditions, proven-safe arithmetic, and scalar/object returns. Arguments and fields can hold object handles; aliases, nested references, and cycles retain shared mutations. The runtime retains arena allocations until exit. Generated functions are shared when resolved nested lookup agrees and specialized when object-dependent targets differ. Empty classes, single inheritance from previously defined user classes, inherited constructors, overriding, and explicit/forwarded `super` are supported. `while`/`until`, pre/post-test modifiers, `break`, `next`, plain `begin`, and local/instance compound arithmetic assignment are supported with rechecked loop invariants and direct integer-literal guard bounds. Recursion, fresh user objects inside loops, general dynamic dispatch, and joins of different object handles remain unsupported.

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

The [realistic workload corpus](../examples/README.md) supplies application-shaped reference programs and observed blockers. Use shipping pricing for stage 7, streaming log summaries for stage 8, and cart aggregation for collection/block work. Notification selection and guarded unit pricing track object-join and predicate-narrowing limits outside the current contract. These examples supplement the stage sequence without declaring new support or reordering implementation.

The [class-owned definition registry](../examples/workloads/class_definitions.rb), added on 2026-10-08, preserves a supplied Ruby program and its `true` reference output. Its first blocker is a class method; later requirements span arrays, symbols/hashes, class-body evaluation, class-instance state, inherited class-method lookup, `nil?`, and `p`. Track its class semantics in stage 14 and its `p` output in stage 16; collection support alone cannot complete the example. The supplied fixture does not exercise `Child.defs` or `clear`; add cases for class receiver identity and shared nested references before declaring full support.

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

### 3. Object state and constructors — complete (2026-10-07)

Replace the stateless object tag with a shared object handle. Support `@variable` reads and writes and `initialize` with required positional scalar arguments. `new` invokes the constructor and returns the object regardless of the constructor's ordinary result. Initially, fields contain supported scalar values only.

**Acceptance:** the milestone Greeter works; separate instances have separate state; aliases observe the same mutations; unassigned fields read as `nil`; constructor arguments execute once in order. Object-valued fields remain explicitly rejected.

**Delivered:** constructor invocation, scalar instance-variable reads and writes, and shared object handles backed by per-runtime field maps. Analysis shares field types across aliases and captures read types before later writes; generated temporaries preserve receiver, argument, read, and call-result evaluation order. Explicit calls to private `initialize`, wrong constructor arity, object-valued fields, and top-level instance variables remain diagnostics. Objects are retained until runtime teardown; arbitrary object graphs and reclamation remain later work. The [Greeter example](../examples/greeter.rb) now meets the first milestone. [Object-state scenarios](../features/object_state.feature) cover these behaviors, nested constructor/receiver context, and invalid operations after an alias changes a field type. `bin/verify` passed: RuboCop, 2 RSpec examples, 69 Cucumber scenarios, Rust formatting, and Cargo tests (zero runtime unit assertions).

### 4. Instance calls and `self` — complete (2026-10-07)

Support explicit `self.method` and implicit calls to another method on the current receiver. Emit separate Rust functions with receiver and arguments instead of copying method bodies into each call site. Define visibility for constructor calls before exposing explicit `initialize` calls.

**Acceptance:** nested calls use the same receiver, preserve state and evaluation order, and isolate method-local scopes. Unsupported lookup remains a diagnostic. Recursion is added only with a tested analysis strategy.

**Delivered:** `self` IR, explicit and implicit current-receiver calls, and local aliases of `self`. Methods in a class are registered before their bodies are checked, allowing later-defined helpers. Implicit user methods shadow built-in `gets` and `puts`. Analysis still checks actual argument and field types at every call; Rust emits one function per called class/method with runtime, receiver, and scalar arguments. This fixed lookup relies on scalar arguments/fields; object-dependent dispatch remains later work. Direct and indirect recursive methods receive `E_UNSUPPORTED` at the Ruby call location, including in unused methods. `initialize` remains constructor-only; explicit/implicit calls to it are still rejected. Attribute/index assignment syntax is rejected because its expression result differs from an ordinary method call. The [Greeter example](../examples/greeter.rb) uses explicit and implicit helpers. [Instance-call scenarios](../features/instance_calls.feature) cover receiver state, local isolation, input order, type changes, generated-function reuse, and diagnostics before output is written. `bin/verify` passed: RuboCop, 2 RSpec examples, 92 Cucumber scenarios, Rust formatting, and Cargo tests (zero runtime unit assertions).

### 5. Conditions, arithmetic, and returns — complete (2026-10-07)

Add `true`, `false`, comparisons, basic integer arithmetic, `if`/`unless`, and explicit `return`, in that order. Define the supported integer range and overflow/error policy before accepting arithmetic. Preserve Ruby truthiness and expression values.

**Acceptance:** zero and empty strings are truthy; branch results, side effects, early returns, and numeric boundaries match CRuby on declared inputs. Unsupported numeric behavior is not silently wrapped or substituted.

**Delivered:** boolean values, scalar equality and negation, integer ordering, and `+`, `-`, `*`, `/`, `%`, and unary signs. Integer intervals prove results fit `i64`; overflow is `E_INTEGER_RANGE`, while possible zero division and unsupported operand types are `E_UNSUPPORTED` before emission. Rust uses `i128` intermediates, floor division, and modulo with the divisor's sign. `if`/`unless`, `elsif`, modifiers, parenthesized sequences, and scalar method `return` preserve values and side effects. Analysis joins local/field state across branches and method exits; unreachable writes do not change caller-visible state, but unsupported unreachable code still fails. Generated mutable local bindings use captured reads to preserve earlier values. Both branches are analyzed without predicate narrowing; conditional object choices and object conditions remain rejected. Prism parse results now carry default-level warnings into program IR for runtime reproduction at CRuby's default verbosity. [Arithmetic scenarios](../features/arithmetic.feature) and [control-flow scenarios](../features/control_flow.feature) cover boundaries, signed division/modulo, user-defined operators, aliases, branch effects, and early returns. The [number-label example](../examples/number_label.rb) builds independently. `bin/verify` passed: RuboCop, 2 RSpec examples, 149 Cucumber scenarios, Rust formatting, and Cargo tests (zero runtime unit assertions).

### 6. Objects passed between methods — complete (2026-10-07)

Allow object arguments and results, then object-valued fields. Define memory ownership and cycle handling before supporting arbitrary object graphs. Keep identity when values cross calls or are assigned to another variable.

**Acceptance:** returning or passing an object preserves its identity and shared mutations. Tests cover nested references and the declared behavior or diagnostic for cycles.

**Delivered:** object arguments, constructor arguments, implicit/explicit object returns, and object-valued fields. Built-in identity equality/inequality and negation preserve Ruby behavior; user overrides take precedence. Default `!=` delegates to overridden `==` and negates its truthiness without reevaluating the receiver or arguments. Analysis snapshots all tracked objects at branch/return boundaries, preserving nested mutations, returned aliases, and unreachable-write handling through cycles. Generic parameter/field lookup is deferred during unused-method checking and resolved for every actual call before emission. Rust functions are shared by class/method plus resolved nested-call signature; changed argument/field classes create variants without hashing cyclic type graphs. The existing indexed arena supports self references and mutual cycles and releases all entries at runtime teardown; unreachable allocations are not reclaimed early. Different object-handle joins, object/scalar joins, object conditions, printing/interpolation, safe object navigation, recursive methods, and integer/string equality with an object on the right remain diagnostics. The latter would require Ruby-compatible delegated primitive comparison. [Object-reference scenarios](../features/object_references.feature) and [the linked-name example](../examples/linked_names.rb) execute these contracts against CRuby. `bin/verify` passed: RuboCop, 2 RSpec examples, 184 Cucumber scenarios (645 steps), Rust formatting, and Cargo tests (zero runtime unit assertions). The retained example also built and ran independently in release mode.

### 7. Inheritance — complete (2026-10-07)

Support a single superclass, inherited method lookup, overriding, and `super`. Define constructor lookup and explicit versus forwarded `super` arguments. Continue rejecting class reopening and dynamic redefinition.

**Acceptance:** inherited and overridden methods, superclass construction, and `super` calls match CRuby, including receiver state and argument side effects.

**Delivered:** a superclass reference in class IR, empty classes, inherited method/constructor lookup, overrides on the actual receiver, and lexical-owner lookup for `super` through gaps and multiple ancestors. Bare `super` forwards current required positional parameter values; explicit arguments execute once in order, and `super()` supplies no arguments. The default no-argument initializer returns `nil`; constructors and superclass calls retain the same object and fields. Super calls lower to existing resolved method-call IR and Rust receiver functions; function specialization continues to distinguish nested targets without a runtime lookup table. Recursive calls are checked by concrete receiver, method owner, and name so valid superclass chains are accepted. Built-in/computed superclasses, reopening/redefinition, missing non-initializer targets, wrong arity, explicit `initialize`, splats, keywords, and blocks remain diagnostics before emission. [Inheritance scenarios](../features/inheritance.feature) exercise these contracts, including object arguments/results and inherited equality. [Shipping pricing](../examples/workloads/shipping.rb) now matches CRuby and its corpus scenario compares execution rather than expecting rejection. `bin/verify` passed: RuboCop, 2 RSpec examples, 222 Cucumber scenarios (797 steps), Rust formatting, and Cargo tests (zero runtime unit assertions). The retained shipping project also built and ran independently in release mode.

## Language expansion

### 8. Loops — complete (2026-10-08)

Add `while`, `until`, `break`, and `next`. Preserve condition timing, truthiness, and control-expression values.

**Acceptance:** counters, condition side effects, skipped iterations, and early exits match CRuby. Test execution has a timeout so regressions cannot hang the suite.

**Delivered:** `while`/`until`, pre-test statement modifiers, post-test `begin` modifiers, plain expression grouping, `break` values, `next` with evaluated/discarded values, and local/instance compound arithmetic assignment. Rust emits labeled loops and body blocks so nested exits, post-test conditions after `next`, and method returns reach the correct context. Analysis computes loop invariants for locals and all tracked fields, compares object references without traversing cycles, widens integer intervals, and narrows direct local/instance reads compared with integer literals through `<`, `<=`, `>`, and `>=`. Post-test headers include the unguarded first iteration. The solver rejects after 16 passes; unsupported syntax and unreachable expressions remain checked. Ordinary conditional narrowing is unchanged. Fresh user-object allocations inside loops, changing object-handle joins, `redo`, `for`, and predicate `break`/`next` remain diagnostics. Input-dependent unbounded counters still fail with `E_INTEGER_RANGE`; the log-summary corpus now records that next blocker at line 7 rather than a syntax error at line 5. Acceptance execution kills the entire program process group after 30 seconds, with focused runner checks for stream capture and orphaned output pipes. [Loop scenarios](../features/loops.feature) and [the bounded counter](../examples/bounded_counter.rb) execute the declared contract against CRuby. `bin/verify` passed: RuboCop, 4 RSpec examples, 253 Cucumber scenarios (910 steps), Rust formatting, and Cargo tests (zero runtime unit assertions). The retained counter project also built and ran independently in release mode.

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

An early [synthetic baseline](benchmarks.md) measures the current stage-5 subset before optimization. It does not complete this milestone or change the implementation order.

Choose real benchmark programs and measure compilation time, startup, runtime, memory, and binary size. Add call specialization, reduced cloning, and Cargo build reuse only for observed bottlenecks.

**Acceptance:** an optimization improves a named benchmark and keeps semantic checks green. Record measurement conditions and before/after results; avoid speculative caches or optimization passes.

### 19. Selected dynamic behavior — future evaluation

Evaluate class reopening, method redefinition, `send`, `respond_to?`, `method_missing`, and selected reflection APIs one at a time. Each needs its own compatibility boundary and tests, including interactions with optimized calls.

**Acceptance:** supported changes affect subsequent lookup like CRuby; unsupported dynamic behavior remains explicit. `eval`, arbitrary dynamic loading, native extensions, threads, and `Fiber` are separate major directions with no support commitment yet.

## Next action

Begin stage 9 with array literals, indexed reads/writes, `length`, and `push`, then string concatenation and a small declared mutation API. Define shared storage, aliasing, cycles, frozen-string behavior, negative indexes, and error boundaries before expanding validation. Preserve evaluation order and class/object reference behavior. Array aggregation and Symbol-to-Proc conversion in the cart remain separate supported-call contracts for later work; do not claim the whole cart works after accepting its array literal.
