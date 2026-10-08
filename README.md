# Rubast

Rubast is an experimental ahead-of-time compiler from Ruby to Rust. The compiler itself is written in Ruby. It is inspired by [Spinel](https://github.com/matz/spinel), which compiles Ruby to native programs through C.

**Status:** a small Ruby subset works end to end: `nil`, booleans, signed 64-bit integers, UTF-8 strings, local variables, `gets`, safe `chomp`, interpolation, `puts`, user classes with inheritance, object references, and nested instance calls, scalar conditions, comparisons, bounded integer arithmetic, and method returns. Unsupported syntax produces a source diagnostic.

The proposed pipeline is:

```text
Ruby source → Prism (Ruby API) → semantic IR (Ruby) → generated Rust + Rust runtime → Cargo binary
```

Ruby and Prism are needed to run the compiler. Its Ruby services are assembled with `dry-system` and loaded with Zeitwerk. Acceptance behavior is specified with Cucumber; compiler components are checked with RSpec. The compiled program uses the Rust runtime linked into its binary.

The compiler requires CRuby 3.4.5 and Bundler. Building or running a generated program also requires Rust and Cargo. Dependencies are locked in `Gemfile.lock`.

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

`emit-rust` does not invoke Cargo or execute the Ruby program. The output includes `Cargo.toml`, `src/main.rs`, and the runtime source; runtime build caches are excluded. Existing nonempty destinations are rejected with `E_OUTPUT`. Compiler and output errors exit with status 2; invalid command usage exits with status 64. `run` continues to build and execute in a temporary directory that is removed afterward.

User classes support `Class.new` with required positional scalar or object arguments passed to `initialize`, or no arguments when no initializer is defined. Instance methods accept required positional scalar or object arguments. Instance variables hold `nil`, booleans, integers, strings, or object handles; unset fields read as `nil`. Object aliases share mutations, while separate instances have independent state. `new` returns the object regardless of the initializer's ordinary result. Method bodies support expression sequences, local assignment, and `puts`. The final expression's value is returned; empty bodies and built-in `puts` return `nil`. Methods can call helpers using `self.method` or an implicit receiver, including methods defined later in the same class. `self` may also be assigned to a method local for alias calls. Implicit user methods take precedence over built-in `gets` and `puts`. Generated Rust shares receiver functions when resolved nested calls agree; object-dependent lookup emits separate variants when needed. Functions receive runtime, receiver, and supported value arguments. See [the class example](examples/greeter.rb):

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

Classes must be defined before use. Empty classes are supported. A class may name one previously defined user class as its superclass; inherited method and constructor lookup follows this chain, and overrides apply to calls on the actual receiver, including helpers called by an inherited method. `super(arguments)` supplies explicit arguments, `super()` supplies none, and bare `super` forwards the current values of the enclosing method's required positional parameters without reevaluating caller expressions. Lookup starts above the class defining that method, even when it is inherited by a further subclass. Superclass methods use the same object and fields. With no user initializer, construction and initializer `super()` use the default no-argument initializer returning `nil`. See [inheritance scenarios](features/inheritance.feature) and [shipping pricing](examples/workloads/shipping.rb).

Reopening classes or existing Ruby constants, explicit inheritance from built-in classes, computed superclasses, explicit calls to private `initialize`, instance variables outside instance methods, singleton methods, top-level `self` or `return`, and optional/keyword/block parameters are unsupported. `super` without a user ancestor target is rejected except for the default initializer; blocks and splatted/keyword arguments remain unsupported. Recursive calls, attribute/index assignment syntax, and unknown helper lookup remain unsupported. Methods may receive and return objects, including `self` and freshly constructed instances. Assignments, calls, and fields preserve shared identity. Object printing and interpolation remain unsupported. Supported operations on parameters, such as `name&.chomp`, are checked using the argument and field types at each call. Every method is checked for unsupported syntax and known invalid operations even if unused. Lookup on unknown parameter or field types is deferred until an actual call; all reachable calls are validated before emission. Integer receivers for `chomp` remain unsupported. Unsupported forms retain `E_UNSUPPORTED` and a Ruby location.

Boolean values support printing, interpolation, and scalar equality (`==`, `!=`). Scalar `!` uses Ruby truthiness: only `nil` and `false` are false; zero and empty strings are true. Ordering (`<`, `<=`, `>`, `>=`) requires proven integers. Integer `+`, `-`, `*`, `/`, `%`, unary `+`, and unary `-` are supported when analysis proves every possible result fits `i64`. Division rounds down and modulo follows the divisor's sign, including negative operands. Overflow produces `E_INTEGER_RANGE` before emission; a divisor that may be zero produces `E_UNSUPPORTED`. There is no wrapping, arbitrary-precision arithmetic, or accepted runtime division error yet.

`if`, `unless`, `elsif`, their statement modifiers, and parenthesized expression sequences preserve selected-branch effects and expression values. A missing branch returns `nil`; locals assigned only in an untaken branch remain `nil`. Method `return` accepts no value or one supported scalar or object value and exits the current method, including from a branch within an argument expression. The [number-label example](examples/number_label.rb) combines comparisons, arithmetic, conditions, and early returns:

```sh
bundle exec ruby bin/rubast run examples/number_label.rb
# below:-4
# equal
# above:18
```

Analysis joins both branches and all method return paths, without narrowing types from conditions. A later operation must be valid for every joined type and integer range, even if a literal condition selects one branch. Existing objects' fields may change in branches. Object joins require the same proven handle on every continuing path: choosing different objects or joining an object with `nil` or a scalar in a local, field, or method result remains unsupported. Conditions require scalar values. Both branches and code after `return` are still checked for unsupported semantics. Logical `&&`/`||`/`and`/`or`, floats, exponentiation, bitwise arithmetic, loops, and safe navigation on object receivers remain unsupported. Default-level Prism warnings, such as a string literal in a condition, are retained and printed with Ruby source locations before program execution. Warning compatibility targets CRuby's default verbosity.

Object handles are indices into a per-program arena. Object-valued fields can form self references and mutual cycles; the arena retains all allocations until program exit, including unreachable objects. There is no tracing collector, early reclamation, or finalizer support. Built-in object `==`/`!=` compare identity and `!` returns false; user-defined operators take precedence, and default `!=` negates a user-defined `==` result with Ruby truthiness. Recursive method calls remain unsupported even when different objects are involved. Integer/string `==` or `!=` with an object on the right receives `E_UNSUPPORTED`: Ruby can delegate that comparison to the object, and delegated primitive equality is not implemented yet.

The [linked-name example](examples/linked_names.rb) passes objects, returns `self`, and follows a two-object cycle while preserving mutations:

```sh
bundle exec ruby bin/rubast emit-rust examples/linked_names.rb -o target/linked-names
cargo build --release --manifest-path target/linked-names/Cargo.toml
target/linked-names/target/release/rubast_program
# Grace
# Zoë
# true
```

Run the complete local checks with `bin/verify` (RuboCop, RSpec, Cucumber, Rust formatting, and Cargo tests). GitHub Actions runs the same checks on pushes and pull requests. Cucumber compares supported programs with CRuby and checks diagnostics for unsupported programs. The CLI exposes `run` and `emit-rust`; a separate `build` command and the broader language subset remain planned. See [the implementation roadmap](docs/roadmap.md) for the agreed sequence and acceptance criteria.

For application-shaped examples, see the [workload corpus and blocker table](examples/README.md): invoice payments and shipping policies currently compile; streaming logs, shopping-cart aggregation, notification configuration, guarded unit pricing, and class-owned definition registries expose planned features and analysis limits. Every example has an executable CRuby reference; unsupported examples intentionally remain rejected by Rubast.

See [the architecture and implementation plan](docs/architecture.md), [proposed technology stack](docs/technology-stack.md), and [contributor and agent development guide](docs/development.md). Documentation and Cucumber scenarios are written in English.

## Preliminary benchmarks

The [synthetic baseline](docs/benchmarks.md) compares CRuby with emitted release binaries on arithmetic, conditions, method calls, instance fields, and strings. It records process execution time, peak RSS, separate generation/build costs, and raw samples. These measurements establish whether the current AOT approach improves repeated process runs and where further work is justified.

```sh
python3 benchmarks/synthetic.py
# generated Ruby, Cargo projects, and raw measurements: target/synthetic-benchmark/
```

The runner requires Python 3 and Linux with GNU `/usr/bin/time`, in addition to the compiler toolchain. The output directory must not exist. Each workload's output, errors, and exit status must match CRuby before timing. Compiler checks should run separately from benchmarks to avoid competing load. See the report for measurement conditions and the limits of startup-heavy, unrolled workloads.

No license has been selected yet.
