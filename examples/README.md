# Example programs

Each file is a standalone Ruby program. Run it independently rather than loading all examples into one Ruby process. Examples and reference outputs target the pinned CRuby version in `.ruby-version`.

The small examples at the root demonstrate supported constructs: [interactive input](hello_user.rb), [instance calls](greeter.rb), [conditions and arithmetic](number_label.rb), and [object references and cycles](linked_names.rb).

## Realistic workload corpus

The programs under `workloads/` describe small application tasks. They intentionally include useful Ruby outside the current subset. All six run successfully on CRuby with the documented inputs; five currently fail Rubast compilation. These failures are progress indicators, not claims of support. Money values use integer cents.

Observed after stage 6 on 2026-10-07:

| Program | Task | Rubast result | First blocker | Additional work needed |
| --- | --- | --- | --- | --- |
| [invoice.rb](workloads/invoice.rb) | Customer, one invoice line, rejected/accepted payment, quantity update through an alias | Matches CRuby | None on the supplied fixture | Multiple lines would need collections; no general billing or validation contract is claimed |
| [shipping.rb](workloads/shipping.rb) | Standard/express pricing with an inherited constructor and overridden calculation | `E_UNSUPPORTED`, line 13 | Subclass `ClassNode` | Inherited lookup and forwarded `super` (stage 7) |
| [log_summary.rb](workloads/log_summary.rb) | Read status lines until EOF and count successful/failed entries | `E_UNSUPPORTED`, line 5 | `WhileNode` | Loops, `+=`, and a range/overflow policy for input-dependent counters (stage 8 and numeric contract) |
| [shopping_cart.rb](workloads/shopping_cart.rb) | Store line-item objects and aggregate their subtotals | `E_UNSUPPORTED`, line 16 | `ArrayNode` | Array storage/append, `Array#sum`, symbols, and Symbol-to-Proc block conversion (stages 9–11; each needs a supported-call contract) |
| [notification.rb](workloads/notification.rb) | Select email or SMS from stdin, then call the chosen channel | `E_UNSUPPORTED`, line 25 | Join of different object handles in a conditional | Object unions and receiver lookup after a join; outside the current stage-6 contract |
| [unit_pricing.rb](workloads/unit_pricing.rb) | Divide a subtotal by quantity and return a message for an invalid quantity | `E_UNSUPPORTED`, line 11 | Division is rejected for zero even though an earlier guard returns | Predicate/range narrowing or proven unreachable-path handling; conservative analysis currently checks the division path |

The first diagnostic can hide subsequent blockers. For example, accepting array syntax would not make Symbol-to-Proc aggregation work automatically. The notification and unit-pricing examples exercise analysis limits even though their syntax already normalizes successfully. Keep these programs intact when implementing support; do not remove useful constructs merely to turn a row green.

## Run and inspect

The invoice currently compiles and matches its Ruby reference:

```sh
ruby examples/workloads/invoice.rb
bundle exec ruby bin/rubast run examples/workloads/invoice.rb
```

An unsupported example remains runnable as ordinary Ruby:

```sh
ruby examples/workloads/shipping.rb
# standard:5200
# express:5700
bundle exec ruby bin/rubast run examples/workloads/shipping.rb
# E_UNSUPPORTED; exit status 2
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

## Track progress

[The Cucumber corpus](../features/realistic_examples.feature) checks the invoice against CRuby and pins reference outputs for every program. Currently unsupported cases assert the diagnostic code, Ruby line, and absence of an emitted project. Their tag allows focused checks:

```sh
bundle exec cucumber --publish-quiet features/realistic_examples.feature
bundle exec cucumber --publish-quiet features/realistic_examples.feature --tags @unsupported_examples
```

The suite is expected to pass while the five Ruby programs still fail Rubast compilation. When support is implemented, replace that case's diagnostic assertions with emitted execution and stdout/stderr/exit-status comparison, retain its CRuby reference output, remove its unsupported tag, and update this table. A changed first diagnostic should prompt investigation of the next blocker. Before declaring support, run `bin/verify`.

This corpus supplements the agreed roadmap; it does not reorder stages or complete them. The files remain self-contained while multiple-source compilation is planned, so the one-class-per-file lint rule is exempted only for this workload directory.
