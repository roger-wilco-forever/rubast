Feature: Next from literal blocks

  Scenario: Each ignores next values and continues all invocations
    Given the Ruby source is:
      """
      values = [1, 2, 3]
      last = 0
      returned = values.each { |value| puts value; last = value; next "ignored"; puts "unexpected" }
      puts returned.length
      puts last
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Times skips only the current body and preserves its receiver result
    Given the Ruby source is:
      """
      last = -1
      puts 4.times { |index| last = index; if index == 1; next 9; end; puts index }
      puts last
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Map keeps conditional next values in element order
    Given the Ruby source is:
      """
      values = [1, 2, 3].map { |value| if value == 2; next 99; end; value + 10 }
      puts values[0]
      puts values[1]
      puts values[2]
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Next without a value becomes nil in map
    Given the Ruby source is:
      """
      values = [1, 2].map { next; puts "unexpected" }
      puts values[0] == nil
      puts values[1] == nil
      puts values.length
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Next updates captures before later block invocations
    Given the Ruby source is:
      """
      last = 0
      result = [2, 3].map { |value| last = value; next last; last = 99 }
      puts result[0]
      puts result[1]
      puts last
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Block locals are fresh after next
    Given the Ruby source is:
      """
      values = [2, 3].map { |value; scratch| puts scratch == nil; scratch = value; next scratch }
      puts values[0]
      puts values[1]
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Empty iterators check next without applying its value effects
    Given the Ruby source is:
      """
      last = 0
      puts [].map { last = 1; next gets }.length
      puts 0.times { last = 2; next gets }
      puts last
      puts gets&.chomp
      """
    And standard input is:
      """
      first
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Nested iterator next targets only the innermost invocation
    Given the Ruby source is:
      """
      puts 2.times { |outer| puts 3.times { |inner| if inner == 1; next; end; puts "#{outer}:#{inner}" }; puts "outer" }
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Ordinary loop next and block next keep distinct targets
    Given the Ruby source is:
      """
      returned = 2.times do |outer|
        index = 0
        while index < 2
          index += 1
          next if index == 1
          puts "inner:#{index}"
        end
        next "ignored" if outer == 0
        puts "outer:#{outer}"
      end
      puts returned
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Yield receives each next value and the method continues
    Given the Ruby source is:
      """
      class Producer
        def run
          first = yield(2)
          puts "between"
          second = yield(3)
          first + second
        end
      end
      last = 0
      puts Producer.new.run { |value| last = value; next value + 10; puts "unexpected" }
      puts last
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Conditional next can return from a block while another path breaks its method
    Given the Ruby source is:
      """
      class Producer
        def run
          puts yield(1)
          puts yield(2)
          puts "unexpected"
          "normal"
        end
      end
      puts Producer.new.run { |value| if value == 1; next "continued"; end; break "found" }
      puts "after"
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Next with no value returns nil to yield
    Given the Ruby source is:
      """
      class Producer
        def run
          puts yield
          "normal"
        end
      end
      puts Producer.new.run { next }
      puts "after"
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Nested lexical yields keep their own next invocation result
    Given the Ruby source is:
      """
      class Relay
        def once(value)
          result = yield(value)
          puts "inner continues"
          result + 1
        end
        def run(other)
          other.once(2) { |value| yield(value + 1) }
        end
      end
      puts Relay.new.run(Relay.new) { |value| next value + 10 }
      puts "after"
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Yielding loop trials retain only reachable next states
    Given the Ruby source is:
      """
      class Producer
        def run
          index = 0
          while index < 3
            puts yield(index)
            index += 1
          end
          "normal"
        end
      end
      last = -1
      puts Producer.new.run { |value| last = value; next value + 10 }
      puts last
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Next in a yielding loop predicate supplies its condition value
    Given the Ruby source is:
      """
      class Producer
        def run
          while yield(1)
            puts "unexpected"
          end
          "normal"
        end
      end
      last = 0
      puts Producer.new.run { |value| last = value; next false }
      puts last
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Ignored blocks discard checked next effects
    Given the Ruby source is:
      """
      class Producer
        def run; "normal"; end
      end
      last = 0
      puts Producer.new.run { last = 9; next "unused" }
      puts last
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Unknown receiver checks defer next values until the actual call
    Given the Ruby source is:
      """
      class Producer
        def run; yield(2); end
      end
      class Caller
        def run(other)
          other.run { |value| next value + 1 }
        end
      end
      puts Caller.new.run(Producer.new)
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Object next results preserve aliases in mapped storage
    Given the Ruby source is:
      """
      class Item
        def initialize; @name = "A"; end
        def change; @name << "!"; end
        def name; @name; end
      end
      item = Item.new
      values = [1, 2].map { next item }
      values[0].change
      puts values[1].name
      puts values[0] == item
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Next values evaluate their side effects exactly once
    Given the Ruby source is:
      """
      trace = "A"
      values = [1, 2].map { next(trace << "!") }
      puts trace
      puts values[0]
      puts values[1]
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Unreachable next expressions cannot replace the first value or state
    Given the Ruby source is:
      """
      last = 0
      values = [1, 2].map { last = 1; next 7; last = 9; next "unused" }
      puts values[0]
      puts values[1]
      puts last
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: A break taken while evaluating next does not require a next result
    Given the Ruby source is:
      """
      class Relay
        def once
          yield
          "inner"
        end
        def run(other)
          other.once { next yield }
          "outer"
        end
      end
      puts Relay.new.run(Relay.new) { break "found" }
      puts "after"
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Known invalid operations after next remain checked
    Given the Ruby source is:
      """
      1.times { next 7; "bad" + 1 }
      """
    When I emit a Rust project
    Then the diagnostic has code "E_UNSUPPORTED" at line 1
    And no Rust project was created

  Scenario: Captured zero on a next path raises a runtime division error
    Given the Ruby source is:
      """
      total = 5
      2.times { |value| if value == 1; total = 0; next 7; end; total = 5 }
      puts 30 / total
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Growing traversed arrays stays unsupported on next paths
    Given the Ruby source is:
      """
      values = [1, 2]; values.each { values.push(3); next }
      """
    When I emit a Rust project
    Then the diagnostic has code "E_UNSUPPORTED" at line 1
    And no Rust project was created

  Scenario: Multiple next values remain unsupported
    Given the Ruby source is:
      """
      1.times { next 1, 2 }
      """
    When I emit a Rust project
    Then the diagnostic has code "E_UNSUPPORTED" at line 1
    And no Rust project was created

  Scenario: Finite iterators accept fresh arrays in next values
    Given the Ruby source is:
      """
      1.times { next [1] }
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Different object next results require unsupported joins
    Given the Ruby source is:
      """
      class Item; end
      first = Item.new
      second = Item.new
      [1, 2].map { |value| if value == 1; next first; end; second }
      """
    When I emit a Rust project
    Then the diagnostic has code "E_UNSUPPORTED" at line 4
    And no Rust project was created

  Scenario: Unreachable next cannot make an infinite body acceptable
    Given the Ruby source is:
      """
      1.times { while true; end; next 7 }
      """
    When I emit a Rust project
    Then the diagnostic has code "E_UNSUPPORTED" at line 1
    And no Rust project was created

  Scenario: Nonlocal return exits the defining method
    Given the Ruby source is:
      """
      class Caller; def run; 1.times { return 7 }; end; end
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: The invoice label example builds independently
    Given I use the example "invoice_labels.rb"
    When I emit a Rust project
    Then the emitted project contains its source and runtime
    When I build and run the emitted project
    Then stdout, stderr, and exit status match CRuby
