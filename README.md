# Rubast

Rubast is an experimental ahead-of-time compiler from Ruby to Rust. The compiler itself is written in Ruby. It is inspired by [Spinel](https://github.com/matz/spinel), which compiles Ruby to native programs through C.

**Status:** a small Ruby subset works end to end: `nil`, booleans, signed 64-bit integers, UTF-8 strings, local variables, `gets`, safe `chomp`, interpolation, scalar `puts`/`print`/`warn`/`p`, standard streams, text files, user classes and modules with nested constants, class methods, static composition, visibility, attributes, object references, and nested calls, scalar conditions, comparisons, bounded integer arithmetic, method returns, `while`/`until` loops, arrays, mutable strings, symbols, hashes, bounded inline `each`/`times`/`map` blocks, and literal blocks passed to user instance methods with `yield`. Unsupported syntax produces a source diagnostic.

The pipeline is:

```text
Ruby source files → Prism (Ruby API) → normalized IR → semantic IR → generated Rust + Rust runtime → Cargo binary
```

Ruby and Prism are needed to run the compiler. Its Ruby services are assembled with `dry-system` and loaded with Zeitwerk. Acceptance behavior is specified with Cucumber; compiler components are checked with RSpec. The compiled program uses the Rust runtime linked into its binary.

The compiler requires CRuby 3.4.5 and Bundler. Compiling a program also requires Rust and Cargo; the finished binary runs without Ruby, Rust, Cargo, or the original Ruby source files. Dependencies are locked in `Gemfile.lock`.

```sh
bundle install
printf 'puts 42\n' > example.rb
bundle exec ruby bin/rubast run example.rb
# 42
```

The [interactive greeting example](examples/hello_user.rb) prompts for a name and prints an interpolated greeting:

```console
$ bundle exec ruby bin/rubast run examples/hello_user.rb
What is your name?
Ada
Hello, Ada!
```

The prompt is flushed before the program waits for input. An EOF produces `Hello, !`, matching CRuby for `gets&.chomp`. The current input reader expects valid UTF-8.

To keep and inspect the generated Rust, emit a standalone Cargo project into a new or empty directory:

```sh
bundle exec ruby bin/rubast emit-rust examples/greeter.rb -o target/greeter
# generated source: target/greeter/src/main.rs
cargo build --manifest-path target/greeter/Cargo.toml
target/greeter/target/debug/rubast_program
```

`emit-rust` does not invoke Cargo or execute the Ruby program. The output includes `Cargo.toml`, `src/main.rs`, and the runtime source; runtime build caches are excluded. Existing nonempty destinations are rejected with `E_OUTPUT`. Compiler and output errors exit with status 2; invalid command usage exits with status 64. `run` builds and executes in a temporary directory that is removed afterward unless `--keep-project DIR` is supplied.

To build a persistent binary without executing it:

```sh
bundle exec ruby bin/rubast build examples/workloads/multi_file_quote.rb \
  -o target/quote --release --keep-project target/quote-build
target/quote
```

`build` requires `-o BIN`; its destination must not exist, including dangling symlinks. Parent directories are created as needed. `--release` selects Cargo's optimized release profile for `build` or `run`; debug is the default. `--keep-project DIR` retains a standalone Cargo project, its source map, and Cargo artifacts on success or build failure. The project directory must be new or empty, and it must be separate from the binary destination, including through directory symlinks. Existing files are never deliberately overwritten. Unsupported Ruby fails before writing artifacts. Without retention, intermediate projects are temporary.

Inspect either compiler IR stage without Cargo or program execution:

```sh
bundle exec ruby bin/rubast dump-ir examples/workloads/multi_file_quote.rb --stage normalized
bundle exec ruby bin/rubast dump-ir examples/workloads/multi_file_quote.rb --stage semantic
```

`dump-ir` defaults to semantic IR. Normalized IR includes expanded static source dependencies before semantic validation, so it remains available for syntax that normalizes but is semantically unsupported. Dumps are versioned JSON node graphs with `$ref` references preserving shared and cyclic types. Every emitted project also includes `source-map.json`; Cargo errors on mapped generated lines report the Ruby path, line, and column while retaining Rust's original error text. Runtime/compiler infrastructure errors retain their own locations. The map describes the exact emitted source and must be regenerated after edits or formatting. See [compiler artifacts](docs/compiler-artifacts.md) for the formats and reproduction commands.

Multiple Ruby files support `require_relative "path"` and restricted `require "./path"`, `require "../path"`, or an absolute literal path. Loading is restricted to unconditional file-level statements, local assignments, and direct `puts`/`p` arguments. Paths must be literal UTF-8 strings with a `.rb` filename extension or no filename extension (which adds `.rb`). Dependencies load in source order with independent file-local scopes, shared constants/object state, defining lexical namespaces, and their own frozen-string pragmas and warnings. Repeated and circular requires return `false`; a completed first load returns `true`. Symlink aliases share one loaded-file identity, and `require_relative` resolves from the requiring file's real directory. The command-line entry is not initially a loaded feature, matching CRuby.

Source dependencies are resolved and validated during compilation and embedded in the generated Rust. Explicit relative `require` paths use the compiler's working directory; the emitted binary needs no Ruby source files and can run from another directory. Missing dependencies produce `E_LOAD` at their require site; parse/semantic errors retain the dependency's path and Ruby location. Computed paths, conditional/method/block/namespace-body loading, `load`, `autoload`, load-path/gem lookup, native extensions, and mutable loaded-feature state remain unsupported. No gem compatibility is claimed. See [loading scenarios](features/source_loading.feature) and [the multi-file quote application](examples/workloads/multi_file_quote.rb).

User methods with loader names retain ordinary instance/singleton lookup, module host dispatch, and lexical constants. Loading restrictions apply to the built-in Kernel APIs.

Text I/O supports implicit `print` with one or more scalar arguments, and `puts`/`warn` with zero or more scalar arguments. Arguments run left to right before output starts and retain shared string identity. Print adds no separators or newline; puts and warn add a newline only when each value lacks one. Warn writes to stderr at default verbosity. These calls return nil. One-argument `p` prints and returns nil, booleans, integers, UTF-8 strings, or static symbols; string and symbol inspection use pinned CRuby escaping. Standard stream globals `$stdin`, `$stdout`, `$stderr` and constants `STDIN`, `STDOUT`, `STDERR` preserve identity through locals, fields, constants, and method arguments. Streams support zero-argument gets/read/flush, scalar print/puts, and write with one or more scalars. Gets returns the next newline-delimited line or nil at EOF; read returns remaining text, including an empty string at EOF. Write returns the UTF-8 byte count; flush returns the stream. Output is flushed before waiting for input.

`File.read(path)` reads a whole UTF-8 text file at execution time; `File.write(path, scalar)` creates or truncates a file and returns bytes written. Paths are string expressions, relative to the running program's working directory or absolute. Text preserves LF, CRLF, NUL, and Unicode. These runtime data files are distinct from embedded Ruby source dependencies. Wrong stream directions, null-byte paths, and selected Linux filesystem errors use the existing Ruby exception/rescue/ensure/cause/backtrace flow. Rescue supports direct built-in errno classes such as `Errno::ENOENT` and `SystemCallError`. Tests compare redirected stdout/stderr, missing paths, directories, and buffered/direct ENOSPC writes with CRuby.

The text contract targets Linux and valid UTF-8 input at default Ruby separators and verbosity. Invalid external byte sequences raise `Encoding::InvalidByteSequenceError` instead of a Rust panic; CRuby compatibility is not claimed for those inputs. Stream reassignment, close/reopen, File.open handles/blocks, offsets/length limits, modes, encoding/transcoding options, custom conversions, collection/object output/inspection, zero-argument print, broader p arities, safe stream calls, and explicit SystemCallError/errno construction remain diagnostics. Other operating systems and untested device/descriptor errors need a separate compatibility contract. See [I/O scenarios](features/practical_io.feature) and [receipt export](examples/workloads/text_report.rb).

Paths are normalized before resolving Ruby extensions, preserving terminal dot/slash aliases and the literal hidden filename `.rb`.

User classes support `Class.new` with supported arguments passed to `initialize`, or no arguments when no initializer is defined. Instance methods accept required and optional positional arguments, named `*args`, required and optional keywords, named `**kwargs`, and named `&block`. Instance variables hold `nil`, booleans, integers, strings, or object handles; unset fields read as `nil`. Object aliases share mutations, while separate instances have independent state. `new` returns the object regardless of the initializer's ordinary result. Method bodies support expression sequences, local assignment, and `puts`. The final expression's value is returned; empty bodies and built-in `puts` return `nil`. Methods can call helpers using `self.method` or an implicit receiver, including methods defined later in the same class. `self` may also be assigned to a method local for alias calls. Implicit user methods take precedence over built-in `gets` and `puts`. Generated Rust shares receiver functions when resolved nested calls agree; object-dependent lookup emits separate variants when needed. Functions receive runtime, receiver, and supported value arguments. See [the class example](examples/greeter.rb):

Stage 19 supports unconditional reopening of user classes/modules and replacement of instance/class methods, including aliases and qualified namespace names. Existing objects and class state retain identity; subsequent calls see new definitions. Emitted function keys include definition spans and nested dispatch versions, preserving earlier calls and invalidating affected later specializations.

Literal `send(:method, ...)`/`send("method", ...)` now supports existing literal/forwarded blocks and selected method_missing fallback, bypassing private/protected visibility. Missing or inaccessible user calls reach an inherited/composed user hook with their original arguments and block. `respond_to?` queries literal names with a scalar include-private flag and invokes user respond_to_missing? hooks for missing/excluded methods. Native method visibility comes from pinned metadata; native availability does not imply compilation support. Parsed identifiers and runtime reflective field writes preserve CRuby's distinct fresh-string hook behavior. Literal instance_variable_get/set read/write shared user instance and namespace fields. User overrides retain ordinary lookup.

Conditional definition changes, namespace mutation callbacks, computed names, invalid field names, unsupported native send targets, initialize/native construction through send, scalar/safe reflective calls, public_send, __send__, default missing-method errors, Method objects/enumeration, and eval/define_method remain diagnostics. See [the complete contract](docs/selected-dynamic.md), [execution checks](features/selected_dynamic.feature), and [the registry example](examples/workloads/dynamic_registry.rb).

```ruby
class Greeter
  def initialize(name)
    @name = name
  end

  def greet
    message = self.message
    puts message
    message
  end

  def message
    "Hello, #{name}!"
  end

  def name
    @name&.chomp
  end
end
Greeter.new("Ada").greet
```

Classes must be defined before use. Empty classes are supported. A class may name one previously defined user class as its superclass; inherited method and constructor lookup follows this chain, and overrides apply to calls on the actual receiver, including helpers called by an inherited method. `super(arguments)` supplies explicit arguments, `super()` supplies none, and bare `super` forwards the current values of its positional, rest, keyword, and keyword-rest parameters without reevaluating caller expressions. Bare and explicit `super` forward the current literal block; `&nil` suppresses it and an explicit block replaces it. Lookup starts above the class defining that method, even when it is inherited by a further subclass. Superclass methods use the same object and fields. With no user initializer, construction and initializer `super()` use the default no-argument initializer returning `nil`. See [inheritance scenarios](features/inheritance.feature) and [shipping pricing](examples/workloads/shipping.rb).

Class and module declarations execute their bodies once in source order, with isolated locals and a class/module object as `self`. Constants support lexical, inherited, qualified, and absolute (`::`) lookup; aliases retain shared object/collection identity. Qualified declarations retain their actual lexical nesting. Class methods (`def self.name` or declarations inside `class << self`) inherit while keeping the actual class receiver and its own instance-variable state. Class objects may be passed, returned, aliased, and used for `new`; an explicitly defined class method named `new` takes precedence.

Static `include` adds module instance methods, `extend` adds them to the current class/module object, and `extend self` is supported for modules. `prepend` runs module methods before the class's own methods. Argument order, repeated composition, nested dependencies, and inherited lookup follow the declared CRuby scenarios; `super` advances from the resolved ancestor occurrence, including a module that is both included and prepended. Module methods retain their defining lexical constants and may call host helpers, resolved on each actual receiver. Composition is restricted to direct class/module-body calls on that body's class/module object; changing an already composed module, instance extension, dynamic mutation, and composition callbacks remain diagnostics.

`public`, `protected`, `private`, named visibility changes, and `private_class_method`/`public_class_method` govern lookup and retain Ruby declaration return values. Private native/user `new` follows the same declared access rules. Private methods allow implicit or literal `self` receivers; protected methods allow receivers related to the declaring owner from a related method context. Calls violating visibility receive `E_UNSUPPORTED` before emission. `attr_reader`, `attr_writer`, and `attr_accessor` accept static Symbol/String names and use the same shared fields, lookup, visibility, and argument checks as methods. Setter assignment captures receiver and right-hand side once and returns the assigned value. `class << self` currently accepts method, visibility, and attribute declarations; eigenclass body expressions/state remain diagnostics. See [namespace scenarios](features/namespaces.feature), [module composition](features/modules.feature), [prepend](features/prepend.feature), [visibility and attributes](features/visibility.feature), [boundaries](features/class_model_boundaries.feature), and [modular quotes](examples/workloads/modular_quote.rb).

Reopening classes or existing Ruby constants, explicit inheritance from built-in classes, computed superclasses, explicit calls to `initialize`, instance variables outside supported class/module bodies or methods, and top-level `self` or `return` are unsupported. `super` without a user ancestor target is rejected except for the default initializer. Recursive calls, compound attribute assignment, user index assignment, and unknown helper lookup remain unsupported. Methods may receive and return objects, including `self` and freshly constructed instances. Assignments, calls, and fields preserve shared identity. Object printing and interpolation remain unsupported. Supported operations on parameters, such as `name&.chomp`, are checked using the argument and field types at each call. Every method is checked for unsupported syntax and known invalid operations even if unused. Lookup on unknown parameter or field types is deferred until an actual call; all reachable calls are validated before emission. Integer receivers for `chomp` remain unsupported. Unsupported forms retain `E_UNSUPPORTED` and a Ruby location.

Defaults run only for omitted arguments, at call time in method scope, after caller arguments have run. Explicit `nil` remains a supplied value. Required trailing positional parameters bind from the end; rest arrays and keyword-rest hashes have independent storage while retaining element aliases. `*array` and `**hash` copy their current slots before later argument effects. Multiple splats/keyword groups preserve evaluation order; the last duplicate keyword value wins. Positional hashes remain positional; a nonempty keyword group becomes a final positional hash only when the method declares no keyword parameters. Empty `**{}` and `**nil` contribute no argument. Active splats require a proven exact array length or a single known hash key order. Invalid method arity, missing/unknown keywords, and supported statically known invalid `**`/`&` conversions raise Ruby-compatible runtime errors before defaults or the body execute.

Named block parameters hold `nil` when omitted or a supplied literal block. They support truthiness, comparison with nil, `.call`, and forwarding to user instance methods, constructors, and `super`. Block calls and yield accept the supported positional/keyword splats and preserve the existing zero/one literal-block parameter contract. Captures, lexical self, `next`, original receiving-call `break`, nonlocal `return`, and ensure retain their Ruby boundaries. A constructor's ordinary initializer return produces its object; a break from its supplied block can replace that result. Missing yield raises `LocalJumpError`; calling an omitted block raises `NoMethodError`.

Anonymous parameters/forwarding, `...`, `**nil` parameters, parameter destructuring, custom `to_a`/`to_hash`/`to_proc`, Symbol-to-Proc, block forwarding into built-in iterators, escaped/stored/returned blocks, broader `Proc` APIs, and extended literal-block parameters remain diagnostics. Explicit fresh object/collection allocations are allowed in bounded built-in iterators but retain ordinary-loop/yield restrictions; implicit rest/keyword packs retain the collection and bounded-analysis ceilings. See [argument scenarios](features/method_arguments.feature), [boundary checks](features/method_argument_boundaries.feature), and [configurable quotes](examples/configurable_quotes.rb).

`nil?` preserves receiver evaluation and supports declared values. One-argument `p` prints and returns supported scalar values, including strings and static symbols; collection and user-object inspection remain unsupported. [Registry scenarios](features/class_registry.feature) cover class-owned state, subclass fallback, clear/add, collection aliases, and the unchanged supplied source.

Boolean values support printing, interpolation, and scalar equality (`==`, `!=`). Scalar `!` uses Ruby truthiness: only `nil` and `false` are false; zero and empty strings are true. Ordering (`<`, `<=`, `>`, `>=`) requires proven integers. Integer `+`, `-`, `*`, `/`, `%`, unary `+`, and unary `-` are supported when analysis proves every possible result fits `i64`. Division rounds down and modulo follows the divisor's sign, including negative operands. Overflow produces `E_INTEGER_RANGE` before emission; a zero divisor raises `ZeroDivisionError` at runtime. Nonzero divisor subranges must still prove that results fit `i64`. There is no wrapping or arbitrary-precision arithmetic.

`if`, `unless`, `elsif`, their statement modifiers, and parenthesized expression sequences preserve selected-branch effects and expression values. A missing branch returns `nil`; locals assigned only in an untaken branch remain `nil`. Method `return` accepts no value or one supported scalar or object value and exits the current method, including from a branch within an argument expression. The [number-label example](examples/number_label.rb) combines comparisons, arithmetic, conditions, and early returns:

```sh
bundle exec ruby bin/rubast run examples/number_label.rb
# below:-4
# equal
# above:18
```

Analysis joins both branches and all method return paths. A `nil?` predicate with a proven nil/non-nil receiver selects the continuing branch for analysis while still checking the inactive branch and preserving runtime evaluation; other conditions do not narrow types. A later operation must be valid for every joined type and integer range, even if a literal condition selects one branch. Existing objects' fields may change in branches. Object joins require the same proven handle on every continuing path: choosing different objects or joining an object with `nil` or a scalar in a local, field, or method result remains unsupported. Conditions require scalar values. Both branches and code after `return` are still checked for unsupported semantics. Logical `&&`/`||`/`and`/`or`, floats, exponentiation, bitwise arithmetic and safe navigation on object receivers remain unsupported. Default-level Prism warnings, such as a string literal in a condition, are retained and printed with Ruby source locations before program execution. Warning compatibility targets CRuby's default verbosity.

`while` and `until`, statement modifiers, and `begin ... end while/until` preserve condition timing and Ruby truthiness. Normal termination returns `nil`; `break` returns its supplied scalar or existing object value, or `nil` when omitted. `next` evaluates and discards its value, skips the rest of the body, and still checks a post-test condition. Nested exits target the innermost loop; method `return` still exits its defining method. Plain `begin ... end` groups expressions without exception handlers. Local and instance-variable compound arithmetic assignment, such as `count += 1`, captures the old value before evaluating its right operand.

Loop analysis checks an invariant for locals and all tracked object fields, with integer widening and a maximum of 16 passes. Direct local or instance-variable comparisons against an integer literal using `<`, `<=`, `>`, or `>=` narrow loop-entry and exit ranges, allowing proven-safe bounded counters. This narrowing is specific to loop guards; ordinary `if` branches still use the conservative contract above. Operations must remain valid on every iteration. Fresh user-object allocations inside while/until loops, different object-handle joins, `redo`, `for`, and `break`/`next` in a loop predicate remain diagnostics. Input-dependent unbounded counters such as the log-summary workload receive `E_INTEGER_RANGE` because analysis cannot prove all iterations stay within `i64`; there is no wrapping or accepted runtime overflow. See [loop scenarios](features/loops.feature) and [the bounded counter](examples/bounded_counter.rb). Acceptance execution has a 30-second timeout that kills the entire program process group.

Arrays support literals, one-integer `[]` reads, indexed assignment, `length`, `push` with zero or more arguments, `<<` with one argument, and `!`, plus `+` and structural `==`/`!=` for bounded acyclic arrays of supported scalar/nested-array values. Concatenation copies slots into independent storage while retaining element aliases. Custom element equality and cyclic array comparisons remain diagnostics. Elements are evaluated once from left to right. Arrays share storage through locals, arguments, returns, and fields, including nested arrays and cycles. Negative indexes count from the current end; out-of-range reads return `nil`; nonnegative indexed writes extend with `nil` gaps and return the assigned value. The receiver and arguments are captured before the operation, including side effects that change the array length. Analysis tracks at most 10,000 slots. Reads require a proven integer index and a bounded length range; indexed writes require an exact length and a single proven index. `length`, push/append, and each/map can retain joined length ranges. Growing shapes across while/until iterations, fresh arrays inside those loops, slicing, compound indexed assignment, array printing/interpolation, and joins of different element handles remain diagnostics.

Strings share mutable UTF-8 buffers through aliases. `+` returns a new string; `<<`, one-argument `concat`, `replace`, and `clear` mutate the receiver and return it. `dup` and zero-argument `chomp` return independent mutable copies. `chomp!` returns the original string when a line ending was removed, otherwise `nil`. `length` counts Unicode code points; `bytesize` counts UTF-8 bytes. String arguments must be proven strings; integer code-point append, string indexed writes, and other mutation APIs remain unsupported. Frozen literals, including aliases and array elements from `# frozen_string_literal: true`, raise `FrozenError` on mutation; use `dup` to obtain a mutable copy. Negative indexed writes beyond the array start raise `IndexError`. [Collection scenarios](features/collections.feature) and [the shared-name example](examples/shared_collections.rb) compare these behaviors with CRuby.

Symbols support static literals, scalar output/interpolation, equality/inequality, negation, and scalar arguments/results. Names are immutable UTF-8; interpolated symbols and symbol conversion APIs remain unsupported.

Hashes support literals, `[]`, indexed assignment, `key?`, `length`, `keys`, `values`, and `!`. Insertion keys must be a direct String literal or a single proven Symbol/Integer value. Runtime String expressions are also accepted for lookup/key presence, with conservatively joined results; computed String insertion, boolean, `nil`, custom, and dynamic multi-value keys remain diagnostics. Replacement keeps the original insertion position, missing reads return `nil`, and `key?` distinguishes absence from a stored `nil`. Hashes share arena identity, including nested arrays, mutable strings, user objects, and cycles. `keys` and `values` return independent arrays whose mutable elements retain shared references. Analysis tracks up to 10,000 literal entries/distinct keys and 32 alternative insertion orders. Branches join presence, values, and lengths; `keys`/`values` require one proven order. Hash literals and `keys`/`values` allocations inside while/until loops are rejected; existing keys can mutate. Hash equality/output, defaults, splats, `fetch`, deletion, block traversal, and custom `hash`/`eql?` are unsupported. String keys compare contents, retain their first insertion position, and copy/freeze mutable inputs; `keys` exposes frozen key references. See [practical collections](docs/practical-collections.md) for the selected key and allocation boundaries. The [hash scenarios](features/hashes.feature) and [definition store](examples/definition_store.rb) compare these behaviors with CRuby.

Inline literal blocks are supported for `Array#each`, `Array#map`, and `Integer#times` without call arguments. Blocks accept zero or one ordinary positional parameter and explicit block locals (`|item; scratch|`). Captured assignment updates its enclosing binding; parameters and block locals shadow outer names and start fresh on every invocation. Nested blocks retain lexical lookup and instance `self`; ordinary helper returns and inherited `super` still use their defining method context. Each captures its receiver once, reads an element immediately before invoking the body, and returns the original array. Times requires a bounded integer count range, yields zero-based indexes, runs no body for a nonpositive count, and returns the original integer. Map returns independent array storage with shared mutable results; empty iterators check unsupported body semantics without applying its effects.

Analysis expands known invocations in order and Rust emits a body per step. The per-compilation limit is 1,000 block-body validations, including unused-method checks, nested blocks, and loop solver passes. Array length can be a known range and must stay unchanged throughout iteration; existing slots and referenced objects/strings can mutate. Finite built-in iterator bodies may allocate fresh objects/arrays/hashes and nested maps, with a 10,000-allocation analysis budget. Optional steps test the runtime count and join skipped/executed captures; maps retain only actual results. Allocation under a while/until ancestor remains rejected. Destructuring/multiple/default/rest/implicit parameters, enumerators, safe iterator navigation, `&` conversion, bodies with no fallthrough or supported exit remain unsupported. Break/next belonging to an inner ordinary loop keep that loop's target. Function reuse includes iterator family, the guarded step pattern, and nested resolved calls. See [iterator scenarios](features/iterators.feature) and [batch invoice totals](examples/batch_totals.rb). These initial iterators do not implement `Array#sum` or Symbol-to-Proc conversion.

User instance methods accept literal blocks and `yield` with ordinary positional arguments. Blocks retain the caller's locals, `self`, instance fields, implicit helper lookup, and lexical `super`; the yielding method has independent locals and its own receiver. All yield arguments run once, in order, before the block; a zero-argument yield supplies `nil`, a one-parameter block receives the first argument, and additional arguments still execute. Conditional/repeated yields join captured state across branches, early method returns, and loop invariants. An ignored block is checked without applying its effects. Rust inlines calls with blocks and uses a labeled method boundary so the method's `return` resumes its caller. Function specialization includes the inlined block's syntax and resolved nested calls. The block-parameter, recursion, and 1,000-validation limits apply; yielded bodies retain their fresh-allocation restriction; bodies need a fallthrough or supported block-exit path. A yield without a supplied block raises `LocalJumpError`; unused methods retain an unknown yield result until called. Constructor blocks, named `&block`, and user-method/super forwarding use stage 13's scoped literal-block contract. Safe block calls and escaped blocks remain unsupported. See [yield scenarios](features/yield.feature) and [invoice batch traversal](examples/yielding_batch.rb).

`break` in a literal block returns zero or one value (`nil` when omitted) from the receiving iterator or user method. It skips remaining block expressions, later iterator invocations, and the yielding method's remainder while leaving the caller running. Nested blocks keep their own receiving targets; nested lexical `yield` can carry an exit through intervening calls and loops to its original receiving method. Changes before exit and normal completion join captured bindings and arena state; unreachable expressions still receive semantic checks without applying their effects. Empty iterators and ignored blocks discard checked exit effects. Arrays retain the unchanged-length rule on exit paths too. Existing result joins still require one shared object handle: a conditional scalar break from each/map conflicts with its possible normal array result and remains `E_UNSUPPORTED`, while an unconditional scalar break can return that scalar. Different object-handle and object/scalar joins remain diagnostics. Multiple break values remain unsupported. See [block-break scenarios](features/block_break.feature) and [first large invoice](examples/first_large_invoice.rb).

`next` in a literal block evaluates zero or one value (`nil` when omitted), skips the remaining body, and returns that value from the current block invocation. Each/times ignore the value and continue; map stores it in the matching result slot; yield receives it and the user method continues. Analysis joins next states with ordinary body completion, preserving captured writes and arena mutations before the next invocation. Rust uses a distinct labeled body boundary for each invocation; nested iterator, loop, and lexical yield targets remain separate. Empty and ignored blocks discard checked effects, and unreachable next expressions keep their semantic checks without changing results. Traversed array lengths, allocation/count limits, object-result joins, and multiple next values keep their existing diagnostics. See [block-next scenarios](features/block_next.feature) and [invoice labels](examples/invoice_labels.rb).

`return` in a literal block evaluates zero or one value (`nil` when omitted) and exits the method in which the block was defined. It crosses intervening iterators, ordinary loops, and lexical `yield` calls, skipping later expressions and leaving that method’s caller running. Returns from called helpers and blocks declared in yielding methods retain their own defining method. Return paths join captured bindings and arena mutations with normal method completion; snapshots exclude intervening block locals and callee captures. Empty/ignored/dead blocks and loop-analysis trials discard checked return effects while retaining semantic diagnostics. The existing Rust function return or inline method label supplies the lexical boundary. Top-level block returns, multiple values, escaped blocks, incompatible object-result joins, changing traversed lengths, and fresh object/collection values in unbounded bodies remain diagnostics. See [block-return scenarios](features/block_return.feature) and [invoice search](examples/invoice_search.rb). Stage 11 is complete for this bounded literal-block contract; escaped `Proc` values, extended literal-block parameters, Symbol-to-Proc conversion, and `Array#sum` require separate contracts.

`begin`/`rescue`/`else`/`ensure`, rescue modifiers, and implicit method/block handlers are supported. `raise`/`fail` accept no arguments (reraising the current exception), a string, an exception value, or a built-in exception class with an optional string message. Supported classes are `Exception`, `StandardError`, `RuntimeError`, `ArgumentError`, `TypeError`, `IndexError`, `ZeroDivisionError`, `FrozenError`, `RangeError`, `IOError`, `NameError`, `NoMethodError`, and `LocalJumpError`; their `new`, `message`, and `to_s` preserve shared string messages. Rescue clauses select the first matching class or superclass; a bare rescue catches `StandardError`. Else runs only after normal body completion. Ensure runs on success, exceptions, method/nonlocal returns, and loop/block exits; a new exit from ensure replaces the pending exit without replacing an already evaluated return value. Supported division, array-index, and frozen-string errors use these handlers.

`retry` restarts its own protected body from a rescue clause. The same begin's ensure waits until retry finishes; nested cleanup crossed by retry still runs. Analysis joins retry states for at most 16 passes, refining direct integer-literal conditional guards inside retry regions; unstable state growth remains a diagnostic. Retry cannot target a rescue outside its literal block. Existing allocation, traversal, integer-range, and object-result-join ceilings remain. Custom exception subclasses, computed/splat rescue classes, backtrace/keyword raise arguments, and broader exception APIs remain unsupported. Uncaught exceptions retain their first Ruby backtrace, message, cause chain, stderr formatting, and exit status 1; ArgumentError/TypeError/NoMethodError source snippets use pinned CRuby's `error_highlight`. Ruby exits cross generated `Result` closures so cleanup runs; Rust panics do not implement language exceptions. The text I/O contract above adds checked stream and selected filesystem faults. See [exception scenarios](features/exceptions.feature) and [recoverable price quotes](examples/recoverable_quote.rb).

Object, array, and hash handles are indices into a per-program arena. Object-valued fields can form self references and mutual cycles; the arena retains all allocations until program exit, including unreachable objects. There is no tracing collector, early reclamation, or finalizer support. Built-in object `==`/`!=` compare identity and `!` returns false; user-defined operators take precedence, and default `!=` negates a user-defined `==` result with Ruby truthiness. Recursive method calls remain unsupported even when different objects are involved. Integer/string `==` or `!=` with an object on the right receives `E_UNSUPPORTED`: Ruby can delegate that comparison to the object, and delegated primitive equality is not implemented yet.

The [linked-name example](examples/linked_names.rb) passes objects, returns `self`, and follows a two-object cycle while preserving mutations:

```sh
bundle exec ruby bin/rubast emit-rust examples/linked_names.rb -o target/linked-names
cargo build --release --manifest-path target/linked-names/Cargo.toml
target/linked-names/target/release/rubast_program
# Grace
# Zoë
# true
```

Run the complete local checks with `bin/verify` (RuboCop, RSpec, Cucumber, Rust formatting, and Cargo tests). GitHub Actions runs the same checks on pushes and pull requests. Cucumber compares supported programs with CRuby and checks diagnostics for unsupported programs. The CLI exposes `run`, `build`, `emit-rust`, and `dump-ir`; selected dynamic language behavior remains planned. See [the implementation roadmap](docs/roadmap.md) for the agreed sequence and acceptance criteria.

For application-shaped examples, see the [workload corpus and blocker table](examples/README.md): invoice payments, shipping policies, guarded unit pricing, the unchanged class-owned registry, modular quotes, and UTF-8 receipt export currently compile; the new bounded order/log batches also compile. Original streaming logs, shopping-cart aggregation, and notification configuration still expose analysis limits and planned features. Every example has an executable CRuby reference; unsupported examples intentionally remain rejected by Rubast.

See [the architecture and implementation plan](docs/architecture.md), [proposed technology stack](docs/technology-stack.md), and [contributor and agent development guide](docs/development.md). Documentation and Cucumber scenarios are written in English.

## Benchmarks

The [synthetic baseline](docs/benchmarks.md) compares CRuby with emitted release binaries on arithmetic, conditions, method calls, instance fields, and strings. It records process execution time, peak RSS, separate generation/build costs, and raw samples. These measurements establish whether the current AOT approach improves repeated process runs and where further work is justified.

```sh
python3 benchmarks/synthetic.py
# generated Ruby, Cargo projects, and raw measurements: target/synthetic-benchmark/
```

The runner requires Python 3 and Linux with GNU `/usr/bin/time`, in addition to the compiler toolchain. The output directory must not exist. Each workload's output, errors, and exit status must match CRuby before timing. Compiler checks should run separately from benchmarks to avoid competing load. See the report for measurement conditions and the limits of startup-heavy, unrolled workloads.

The [stage-18 application benchmark](docs/practical-benchmarks.md) measures one million quote calculations, invoice summaries, and receipt labels, with a separate startup control. It records fresh generation/release builds, binary size, peak process RSS, and paired baseline/optimized timings. A targeted interpolation change removes intermediate String copies while preserving frozen/shared values. Those recorded sustained runs were slower than CRuby; startup and process-memory benefits remain distinct from throughput.

The [stage-20 profile-guided measurement](docs/profile-guided-performance.md) refreshes the stage-19 baseline. Inlining the runtime frame push improves paired quote/invoice medians by 3.3%/4.3%; those workloads remain slower than CRuby. Receipt has a 1.2% negative median change in the same window. The report records all timings, RSS, build costs, and executable CPU profiles, including sampling limits and unchanged memory retention.

```sh
python3 benchmarks/practical.py --output target/practical-current
```

No license has been selected yet.
