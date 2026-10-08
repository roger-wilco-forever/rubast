# language: en
Feature: Bounded inline iterators with lexical block locals
  Scenario: Each captures outer assignments and returns the original array
    Given the Ruby source is:
      """
      values = [2, 3, 5]
      sum = 0
      returned = values.each do |value|
        sum += value
        "ignored"
      end
      returned[0] = 7
      puts sum
      puts values[0]
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Block parameters and explicit locals shadow outer bindings
    Given the Ruby source is:
      """
      value = "outer"
      scratch = "outside"
      total = 0
      [2, 3].each do |value; scratch|
        puts scratch
        scratch = value + 1
        total += scratch
      end
      puts value
      puts scratch
      puts total
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Nested blocks capture the enclosing block and method scopes
    Given the Ruby source is:
      """
      class Total
        def calculate(left, right)
          sum = 0
          left.each do |value|
            right.each do |inner|
              sum += value * inner
            end
          end
          sum
        end
      end
      puts Total.new.calculate([2, 3], [4, 5])
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Block locals start as nil on each invocation
    Given the Ruby source is:
      """
      [0, 1].each do |index|
        temporary = 7 if index == 0
        puts temporary
      end
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Read later elements after earlier iterations mutate their slots
    Given the Ruby source is:
      """
      values = [1, 2]
      values.each do |value|
        puts value
        values[1] = "updated"
      end
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Capture the receiver once even when a block reassigns its local
    Given the Ruby source is:
      """
      values = [1, 2]
      replacement = [9]
      original = values
      returned = values.each do |value|
        puts value
        values = replacement
      end
      returned[0] = 7
      puts original[0]
      puts values[0]
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Distinct element classes choose their own method targets
    Given the Ruby source is:
      """
      class First
        def label
          "first"
        end
      end
      class Second
        def label
          "second"
        end
      end
      [First.new, Second.new].each { |item| puts item.label }
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Empty iteration checks its body without changing captured state
    Given the Ruby source is:
      """
      values = []
      name = "Ada"
      returned = values.each do |value|
        name = 7
        puts value
      end
      puts name&.chomp
      returned.push("Grace")
      puts values[0]
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario Outline: Times supplies zero-based indexes and returns its original integer
    Given the Ruby source is:
      """
      count = <count>
      sum = 0
      returned = count.times do |index|
        sum += index
      end
      puts sum
      puts returned
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

    Examples:
      | count                |
      | 4                    |
      | 0                    |
      | -3                   |
      | -9223372036854775808  |

  Scenario: Iterators accept a block without parameters
    Given the Ruby source is:
      """
      count = 0
      [1, 2].each { count += 1 }
      3.times { count += 1 }
      puts count
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Map returns independent array storage with shared mutable results
    Given the Ruby source is:
      """
      values = ["Ada", "Zoë"]
      mapped = values.map do |value|
        value << "!"
      end
      mapped[0] << "?"
      puts values[0]
      puts mapped[1]
      mapped.push("Grace")
      puts values.length
      puts mapped.length
      empty = [].map { |value| value }
      puts empty.length
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Map stores each result before subsequent captured assignments
    Given the Ruby source is:
      """
      total = 0
      mapped = [2, 3].map do |value|
        total += value
      end
      puts mapped[0]
      puts mapped[1]
      puts total
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Instance blocks retain self and support ordinary returns from helper methods
    Given the Ruby source is:
      """
      class Sum
        def initialize
          @total = 0
        end
        def amount(value)
          return value * 2
        end
        def calculate(values)
          values.each { |value| @total += amount(value) }
          @total
        end
      end
      puts Sum.new.calculate([2, 3])
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Inner while exits stay inside their lexical loop
    Given the Ruby source is:
      """
      total = 0
      [2, 3].each do |value|
        while true
          total += value
          break
        end
      end
      puts total
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Method function reuse distinguishes different iterator counts
    Given the Ruby source is:
      """
      class Counter
        def count(values)
          total = 0
          values.each { total += 1 }
          total
        end
      end
      counter = Counter.new
      puts counter.count([1])
      puts counter.count([1, 2, 3])
      """
    When I emit a Rust project
    Then the emitted Rust defines 2 receiver functions
    When I build and run the emitted project
    Then stdout, stderr, and exit status match CRuby

  Scenario Outline: Reject unsupported inline block contracts before emission
    Given the Ruby source is:
      """
      <source>
      """
    When I emit a Rust project
    Then the diagnostic has code "E_UNSUPPORTED" at line 1
    And no Rust project was created

    Examples:
      | source                                                                                     |
      | [1].each { \|first, second\| puts first }                                                      |
      | [1].each { \|value = 7\| puts value }                                                          |
      | [1].each { \|*values\| puts 1 }                                                                |
      | [1].each { puts _1 }                                                                        |
      | [1].each { puts it }                                                                        |
      | [1].each(&:to_s)                                                                            |
      | [1].each(2) { puts 1 }                                                                      |
      | "Ada".each { puts 1 }                                                                      |
      | {}.each { puts 1 }                                                                          |
      | values = [1]; values.each { values.push(2) }                                                 |
      | [1].each { [] }                                                                            |
      | [1].map { {} }                                                                             |
      | class Cell; end; [1].each { Cell.new }                                                      |
      | values = [1]; values.each { values.map { puts 1 } }                                         |
      | count = if gets; 1; else; 2; end; count.times { puts 1 }                                    |
      | 1001.times { puts 1 }                                                                       |
      | 33.times { 33.times { puts 1 } }                                                            |
      | [1].each { while true; end }                                                               |
      | [].each { "Ada" + 1 }                                                                     |

  Scenario: Return from an iterator exits its defining method
    Given the Ruby source is:
      """
      class Example; def go; [1].each { return 1 }; end; end; Example.new.go
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Bare super in a block forwards method parameters despite block shadowing
    Given the Ruby source is:
      """
      class Base
        def echo(value)
          puts "base:#{value}"
        end
      end
      class Child < Base
        def echo(value)
          [1, 2].each do |value|
            puts value
            super
          end
        end
      end
      Child.new.echo("Ada")
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Retain an independently buildable batch of invoice totals
    Given I use the example "batch_totals.rb"
    When I emit a Rust project
    Then the emitted project contains its source and runtime
    When I build and run the emitted project
    Then stdout, stderr, and exit status match CRuby

  Scenario: Unknown method arguments do not imply zero captured iterations
    Given the Ruby source is:
      """
      class Average
        def calculate(values)
          total = 0
          values.each { |value| total += value }
          30 / total
        end
      end
      puts Average.new.calculate([2, 3])
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Unknown method arguments summarize changes to another array
    Given the Ruby source is:
      """
      class Collector
        def copy(values)
          buffer = []
          values.each { |value| buffer.push(value) }
          buffer[0] << "!"
          buffer
        end
      end
      values = ["Ada", "Zoë"]
      copied = Collector.new.copy(values)
      puts copied[0]
      puts copied[-1]
      puts values[0]
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Unknown iteration preserves untouched knowledge in unused methods
    Given the Ruby source is:
      """
      class Example
        def unused(values)
          name = "Ada"
          values.each { puts 1 }
          name + 1
        end
      end
      """
    When I emit a Rust project
    Then the diagnostic has code "E_UNSUPPORTED" at line 5
    And no Rust project was created

  Scenario: A user method can ignore its literal block
    Given the Ruby source is:
      """
      class Example; def each; 1; end; end; Example.new.each { puts 1 }
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Break without a value returns nil from each
    Given the Ruby source is:
      """
      [1].each { break }
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Next without a value leaves each running
    Given the Ruby source is:
      """
      [1].each { next }
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby
