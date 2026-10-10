# Example programs

Each entry file is an independent Ruby program. Run it separately rather than loading all examples into one Ruby process. The quote_app directory contains dependencies for multi_file_quote.rb. Examples and reference outputs target the pinned CRuby version in `.ruby-version`.

The small examples at the root demonstrate supported constructs: [interactive input](hello_user.rb), [instance calls](greeter.rb), [conditions and arithmetic](number_label.rb), [object references and cycles](linked_names.rb), [bounded loops](bounded_counter.rb), [shared arrays and mutable strings](shared_collections.rb), [ordered definition storage](definition_store.rb), [batch invoice totals](batch_totals.rb), [user-method invoice batch traversal](yielding_batch.rb), [first large invoice with an early block exit](first_large_invoice.rb), [invoice labels with block next values](invoice_labels.rb), [invoice search with a nonlocal block return](invoice_search.rb), and [recoverable price quotes with retry and cleanup](recoverable_quote.rb), and [configurable quotes with defaults, rest, keywords, and forwarded callbacks](configurable_quotes.rb).

## Realistic workload corpus

The entry programs under `workloads/` describe small application tasks. They intentionally include useful Ruby outside the current subset. The original ten run successfully on CRuby with the documented inputs; three currently fail Rubast compilation. Two additional bounded batch fixtures exercise stage 21. These failures are progress indicators, not claims of support. Money values use integer cents.

Observed after completion of stage 16 on 2026-10-09:

| Program | Task | Rubast result | First blocker | Additional work needed |
| --- | --- | --- | --- | --- |
| [invoice.rb](workloads/invoice.rb) | Customer, one invoice line, rejected/accepted payment, quantity update through an alias | Matches CRuby | None on the supplied fixture | Multiple lines would need collections; no general billing or validation contract is claimed |
| [shipping.rb](workloads/shipping.rb) | Standard/express pricing with an inherited constructor and overridden calculation | Matches CRuby | None on the supplied fixture | Built-in superclasses remain outside the subset |
| [log_summary.rb](workloads/log_summary.rb) | Read status lines until EOF and count successful/failed entries | `E_INTEGER_RANGE`, line 7 | Unbounded integer growth across loop iterations | Loops and `+=` now normalize; accepting this unchanged program still requires a sound range policy or Ruby-compatible large integers |
| [shopping_cart.rb](workloads/shopping_cart.rb) | Store line-item objects and aggregate their subtotals | `E_UNSUPPORTED`, line 25 | Array#sum aggregation | Literal Symbol callbacks work with each/map/times and selected user methods; Array#sum still needs an aggregation contract; the original source remains unchanged |
| [notification.rb](workloads/notification.rb) | Select email or SMS from stdin, then call the chosen channel | `E_UNSUPPORTED`, line 25 | Join of different object handles in a conditional | Object unions and receiver lookup after a join; outside the current stage-6 contract |
| [unit_pricing.rb](workloads/unit_pricing.rb) | Divide a subtotal by quantity and return a message for an invalid quantity | Matches CRuby | None on the supplied fixture | Possible zero division is a checked runtime error; nonzero results still require the existing `i64` proof |
| [class_definitions.rb](workloads/class_definitions.rb) | A class-owned definition registry populated during class evaluation, with subclass fallback | Matches CRuby | None on the unchanged supplied fixture | Additional acceptance cases cover inherited class receivers, fallback, clear/add, and nested collection aliases |
| [modular_quote.rb](workloads/modular_quote.rb) | Nested shop namespaces, tax helpers, prepended loyalty discount, accessors, inherited class factory, and callback | Matches CRuby | None on the supplied fixture | Static namespace composition only; dynamic modifications remain outside the subset |
| [multi_file_quote.rb](workloads/multi_file_quote.rb) | The same quote behavior split into namespaced dependency files | Matches CRuby and the single-file fixture | None on the supplied fixture | Static file-level loading; reopening and dynamic loading remain outside the subset |
| [text_report.rb](workloads/text_report.rb) | Read a customer, export a UTF-8 receipt, report bytes to stderr, and echo the saved file with cleanup | Matches CRuby with a customer or EOF | None on the supplied fixtures | Whole-file text I/O only; broader file handles, modes, and encodings remain unsupported |

The first diagnostic can hide subsequent blockers. For example, accepting array syntax would not make Symbol-to-Proc aggregation work automatically. The notification example exercises object-result joins even though its syntax already normalizes successfully. Keep these programs intact when implementing support; do not remove useful constructs merely to turn a row green.

The registry preserves the supplied Ruby source. `@defs` is an instance variable of each class object, not a shared `@@` variable. `Child.defs` explicitly falls back to `Base.defs`; inherited class methods must retain the actual class receiver. The supplied fixture only calls `Base.defs` and prints `true`. [Additional registry scenarios](../features/class_registry.feature) now execute subclass fallback, add/clear with independent child state, and retained nested aliases. The supplied source remains unchanged.

## Run and inspect

The invoice currently compiles and matches its Ruby reference:

```sh
ruby examples/workloads/invoice.rb
bundle exec ruby bin/rubast run examples/workloads/invoice.rb
```

Shipping now compiles and matches its reference:

```sh
ruby examples/workloads/shipping.rb
# standard:5200
# express:5700
bundle exec ruby bin/rubast run examples/workloads/shipping.rb
# standard:5200
# express:5700
```

Input fixtures:

```sh
printf 'ok\nerror\nok\n' | ruby examples/workloads/log_summary.rb
# successful:2 failed:1
ruby examples/workloads/log_summary.rb </dev/null
# successful:0 failed:0
printf 'email\n' | ruby examples/workloads/notification.rb
# email:Ada
printf 'sms\n' | ruby examples/workloads/notification.rb
# sms:Ada
```

The remaining examples need no input. Shopping-cart output is `total:4900 cents`. Unit pricing prints `3333`, then `quantity must be at least 1`; CRuby does not divide by zero because the guard returns first.

```sh
ruby examples/workloads/class_definitions.rb
# true
bundle exec ruby bin/rubast run examples/workloads/class_definitions.rb
# true
```

Modular quotes combine the stage 14 features in one application fixture:

```sh
bundle exec ruby bin/rubast run examples/workloads/modular_quote.rb
# Ada: 1270
# 1220
# 550
bundle exec ruby bin/rubast emit-rust examples/workloads/modular_quote.rb -o target/modular-quote-stage14
cargo build --release --manifest-path target/modular-quote-stage14/Cargo.toml
target/modular-quote-stage14/target/release/rubast_program
```

## Track progress

The multi-file quote entry requires preferred_quote, which requires quote, which requires shop. Qualified class declarations keep the namespace shared without reopening it; modules retain the lexical tax constant from shop.rb. Its output matches the unchanged modular_quote.rb fixture:

```sh
bundle exec ruby bin/rubast run examples/workloads/multi_file_quote.rb
bundle exec ruby bin/rubast emit-rust examples/workloads/multi_file_quote.rb -o target/multi-file-quote-stage15
cargo build --release --manifest-path target/multi-file-quote-stage15/Cargo.toml
target/multi-file-quote-stage15/target/release/rubast_program
```

[Loading scenarios](../features/source_loading.feature) compare file order, cycles, aliases, scope, warnings, and errors with CRuby, and independently build/run a project after deleting its Ruby source files.

[The Cucumber corpus](../features/realistic_examples.feature) checks invoice and shipping execution against CRuby and pins reference outputs for every program. Currently unsupported cases assert the diagnostic code, Ruby line, and absence of an emitted project. Their tag allows focused checks:

```sh
bundle exec cucumber --publish-quiet features/realistic_examples.feature
bundle exec cucumber --publish-quiet features/realistic_examples.feature --tags @unsupported_examples
```

The suite is expected to pass while three Ruby programs still fail Rubast compilation. When support is implemented, replace that case's diagnostic assertions with emitted execution and stdout/stderr/exit-status comparison, retain its CRuby reference output, remove its unsupported tag, and update this table. A changed first diagnostic should prompt investigation of the next blocker. Before declaring support, run `bin/verify`.

This corpus supplements the agreed roadmap; it does not reorder stages or complete them. Original fixtures remain self-contained and unchanged. The one-class-per-file lint exemption applies only to workload entry files; the multi-file application's qualified class declarations retain their actual lexical nesting through a narrowly scoped lint exemption.

Receipt export writes `receipt.txt` in the running program's working directory. Use a scratch directory to inspect its output without replacing a local file:

```sh
bundle exec ruby bin/rubast emit-rust examples/workloads/text_report.rb -o target/text-report-stage16
cargo build --release --manifest-path target/text-report-stage16/Cargo.toml
mkdir -p target/receipt-demo
(cd target/receipt-demo && printf 'Zoë\n' | ../text-report-stage16/target/release/rubast_program)
# stdout: Customer: Receipt for Zoë / Total: 1250 (two lines)
# stderr: Saved 29 bytes to receipt.txt
```


## Practical collection batches (stage 21)

[order_batch.rb](workloads/order_batch.rb) creates independent line items and nested note arrays under literal iteration, then totals a bounded, runtime-dependent array of charges. With `gift` input it prints `tea:3:packed!`, `coffee:2:packed`, and `lines:3 total:3350 cents`; other input or EOF omits the gift charge (`lines:2 total:3150 cents`).

[log_batch.rb](workloads/log_batch.rb) reads at most three lines and filters `ok`/`error` entries. It uses runtime String hash lookup and bounded array traversal. Input `ok\nerror\nok\n` prints accepted/rejected/accepted and `processed:3 successful:2 failed:1`; EOF prints `processed:0 successful:0 failed:0`. Unknown statuses are ignored. [Collection acceptance scenarios](../features/practical_collections.feature) compare both programs with CRuby; the order example also builds a retained Rust project.

These bounded batches supplement the unchanged original streaming log and shopping-cart programs. They do not establish unbounded counters, Symbol-to-Proc aggregation, dynamic keys, or traversal growth; [the selected contract](../docs/practical-collections.md) records those limits.

## Reclaimed method batches (stage 22)

[memory_batch.rb](workloads/memory_batch.rb) creates 200 discarded instance/hash/array cycles inside ordinary method calls, allowing automatic collection after method temporaries leave scope. It prints `19900`, then forces collection with zero-argument GC.start and prints `true`. [Differential scenarios](../features/garbage_collection.feature) also retain live aliases and pending block exits across explicit collection. The [memory contract](../docs/memory-management.md) separates compiled finite Ruby from the native sustained-allocation experiment.

## Literal callback batch (stage 23.1)

[callback_batch.rb](workloads/callback_batch.rb) calculates inherited/overridden subtotals with map(&:subtotal), marks shared line objects through each(&:pack), and collects garbage inside the callback. It prints `packed/packed` and `total:3350 cents`. [Callback scenarios](../features/symbol_to_proc.feature) compare execution and errors with CRuby; [the contract](../docs/symbol-callbacks.md) keeps retained Proc/lambda values and Array#sum outside this completed checkpoint.
