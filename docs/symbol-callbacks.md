# Literal Symbol callbacks (stage 23.1)

Direct literal block passes such as `items.map(&:subtotal)` now work for supported callbacks. This is the first completed part of stage 23; first-class Proc/lambda values and retained closures are still planned. The [packing batch](../examples/workloads/callback_batch.rb) maps polymorphic subtotals, mutates labels through each, and runs GC.start inside its callback. It prints `packed/packed` and `total:3350 cents` under both engines.

## Selected contract

Array#each, Array#map, and Integer#times retain their existing bounded shape and iteration rules. A literal Symbol callback receives exactly one positional argument: the method receiver. Its selector invokes a public supported user or native method with no additional arguments. User methods retain inheritance, include/prepend, overrides, default arguments, normal method returns, and the existing method_missing selection. Private/protected targets without a supported hook remain diagnostics, including protected calls from a method on the same class. Callback values are not captured from lexical self.

User methods, constructors, literal send, and explicit/forwarded super may receive the callback. Existing named `&block` parameters can call or forward it while the receiving call is active. Yield/call must supply exactly one positional argument and no keywords. Receiver and call arguments run once in their ordinary order before callback invocation. Callback changes affect subsequent invocations and shared aliases. Unused callbacks and empty iterators perform no dispatch; unknown native selectors on these paths do not create a call that Ruby would not make. Their method bodies still receive existing detached checks.

Map produces independent array storage with shared result references; each/times keep their receiver result. Optional iterator steps remain guarded by the actual runtime count. All existing recursion, result-join, traversal-mutation, allocation, integer-range, and body-validation limits apply.

Computed Symbol expressions, custom to_proc conversion, explicit Symbol#to_proc values, Proc/lambda creation, escaping/storing/returning callbacks, general enumerators, unsupported native selectors, safe navigation, and extra/missing callback arguments remain `E_UNSUPPORTED` before Rust emission. Literal Symbol conversion does not add Array#sum: the unchanged shopping-cart fixture now has an aggregation blocker.

## Owning stages and error frames

The frontend preserves its existing BlockPass/SymbolLiteral representation. [Analysis](../app/analysis/symbol_blocks.rb) constructs an ordinary bounded block with a synthetic receiver binding and SymbolCall body, then resolves it with explicit public visibility. Super uses the same conversion. The validated SymbolInvoke wrapper carries the resolved call and result type. It participates in method specialization, semantic IR dumps, and Ruby source mapping.

The [backend](../app/backend/symbol_blocks.rb) reuses block/iterator emission and ordinary dispatch. Symbol callbacks have no Ruby block-body frame. It temporarily takes the receiving call-site frame, uses it for callback dispatch and native argument errors, and restores it before propagating Outcome/Flow. User/native methods keep their own error frames. No closure environment, persistent runtime Proc object, generated root stack, or dependency is added. Existing handles root values across collection as before.

## Evidence and remaining work

The first 18 new differential cases failed before implementation; ten unsupported shapes retained their diagnostics. [Execution and boundary scenarios](../features/symbol_to_proc.feature) exercise public lookup, aliases, GC, optional lengths, constructors, super, named forwarding, evaluation order, empty/ignored callbacks, hooks, rescue/ensure, and exact uncaught backtraces. The old ignored Symbol-boundary source executes unchanged. The complete local gate and checkpoint status are recorded in [the roadmap](roadmap.md).

Next define shared mutable capture storage and its heap edges for Proc/lambda values. Acceptance must include a returned counter after its factory exits, sibling closures sharing a binding, lexical self, roots/cycles during GC, arity errors, and local versus nonlocal return/break. Retained named blocks must preserve their defining/receiving lifetimes. Those semantics are not supplied by this static callback selection. Performance and memory benchmarks were not rerun.
