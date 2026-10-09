# Selected dynamic behavior

Stage 19 implements selected metaprogramming within Rubast's bounded AOT subset. Each supported operation uses existing value, argument, block, exception, and object-identity rules. [Execution scenarios](../features/selected_dynamic.feature) compare stdout, stderr, and exit status with pinned CRuby; [send scenarios](../features/static_send.feature) retain its earlier compatibility checks.

## Supported contracts

| Operation | Contract |
| --- | --- |
| Reopen a class/module | An unconditional declaration reuses a previously defined user namespace, including aliases and qualified names. Kind must match; an explicit superclass must match the existing superclass. |
| Replace a method | Direct instance, class, eigenclass, and static attribute definitions can replace existing methods. Calls validated afterward see the replacement. Earlier calls keep their earlier resolved definition. |
| send | Literal UTF-8 Symbol/String selectors call existing user methods or selected method_missing implementations. Private/protected access is bypassed. Supported literal and forwarded blocks, argument defaults, splats, keywords, super, and block exits retain ordinary call behavior. |
| method_missing | A missing user call, or inaccessible user method, reaches the concrete receiver's inherited/composed user hook with a Symbol name followed by the original arguments and block. Native methods are not mistaken for missing public methods. |
| respond_to? | Literal Symbol/String names query user/native instance or namespace methods. Public methods return true without execution; protected/private methods require a truthy scalar include-private argument. The default is false. User-defined respond_to? overrides retain ordinary lookup. |
| respond_to_missing? | For missing or excluded methods, the inherited/composed user hook receives a Symbol name and the appropriate include-private value. Existing identifiers convert the flag/result to Ruby booleans. Fresh string identifiers preserve pinned CRuby's raw flag and hook result. |
| instance_variable_get | A literal UTF-8 Symbol/String name with a valid @identifier reads a user instance or class/module object's shared field; an unset field returns nil. |
| instance_variable_set | The same name contract writes a supported value and returns it. Receiver and value execute once in Ruby order; aliases and class instance state remain shared. User overrides retain ordinary lookup. |

Reopening preserves constants, class instance fields, ancestor composition, existing instances, and class/module aliases. Each namespace body has fresh locals and a fresh public default visibility. Replacing a definition records its new visibility normally. Existing constants still cannot be reassigned. Executed body values and error locations remain observable; reopening through an alias retains the written namespace name in body backtraces.

Definitions are versioned by their Ruby body spans in emitted function keys and nested dispatch signatures. This also invalidates specialized inherited callers when a helper changes, while leaving already-emitted earlier calls intact. Block calls continue to inline validated bodies. Every source definition receives the unused-body check even if a later definition replaces it; unsupported earlier syntax is not discarded.

## Identifier and native-method metadata

Prism normalization records literal symbols and parsed Ruby identifiers separately from string literals. Analysis starts with the entry file's identifiers and adds required-file identifiers when that file loads. Static attribute definitions also add their method and field names. All such state belongs to the fresh validation session.

This distinction matters for CRuby 3.4's respond_to? hook path. For a string without an existing static identifier, CRuby can pass the original flag and return the hook result unchanged. Creating a dynamic Symbol for that hook does not by itself promote the name to a static method identifier; repeated queries retain the same behavior. Parsed symbols in later unused methods already exist before entry-file execution. Identifiers from required files exist after loading, so later specialized calls can differ. [Ruby's implementation](https://docs.ruby-lang.org/en/3.4/Object.html#method-i-respond_to-3F) and the differential cases establish this boundary.

A reflective field write promotes its literal identifier globally during execution, including writes on another object or conditional paths. Reading an unset field does not promote it. Runtime keeps this finite set separately from object fields; affected string hook queries choose the appropriate flag/result path at runtime. Ordinary field writes need no additional tracking because their names already occur in parsed source.

The committed [native metadata](../lib/rubast/native_methods.json) contains the pinned Object/Class/Module visibility tables and startup symbol classification. Regenerate it with:

```sh
bin/generate-native-methods
```

The generator snapshots identifiers and methods before loading its JSON serializer in a separate Ruby process without inherited RUBYOPT/BUNDLE_GEMFILE, avoiding compiler/test extensions becoming native APIs. Runtime binaries need no Ruby metadata or source files. Reflection can report that a native method exists even when calling it is outside Rubast's supported subset.

String names that reach a hook and collide with pre-existing non-method native identifiers are diagnostics unless the name also has a known parsed identifier. This conservatively avoids assumptions about foreign startup symbol state. Custom startup monkey patches and require wrappers need a separate compatibility contract.

## Explicit boundaries

The following fail before Rust emission with a Ruby location:

- Conditional/loop namespace changes and conditional visibility, attribute, or composition declarations. Direct declaration assignments remain supported.
- Reopening built-in namespaces, class/module kind changes, superclass changes, computed/reassigned constants, and namespace mutation callbacks such as method_added, singleton_method_added, and inherited.
- Computed selectors, selector splats, scalar receivers, safe reflective calls, built-in construction/initialize through send, and unsupported native send targets.
- Missing calls without a supported user hook, recursive fallback, and super into the built-in method_missing implementation. No default NoMethodError presentation is added.
- Reflection arities outside the table's contract, computed/invalid field names, custom include-private objects, and blocks on native reflection APIs.
- public_send, __send__, method/Method objects, method/field enumeration, define_method, class_eval/module_eval/instance_eval, eval, and broader dynamic mutation/loading.

Existing bounded integer arithmetic, loops, collection shapes, allocation restrictions, block lifetime, object-result joins, and exception limits continue to apply. Stage 19 is a completed selection of contracts, not full Ruby metaprogramming or gem compatibility. Arbitrary eval/loading, native extensions, threads, and Fiber remain separate directions.

See [the combined registry example](../examples/workloads/dynamic_registry.rb) for a runnable application-style example.
