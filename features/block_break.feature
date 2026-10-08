Feature: Break from literal blocks

  Scenario: Each stops immediately and returns its unconditional break value
    Given the Ruby source is:
      """
      total = 0
      puts [2, 3].each { |value| total += value; break "found"; total = 99 }
      puts total
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Times returns a conditional break value and leaves its caller running
    Given the Ruby source is:
      """
      last = -1
      result = 5.times do |index|
        puts index
        last = index
        if index == 2
          break "found"
        end
      end
      puts result
      puts last
      puts "after"
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Map returns a break value rather than partial mapped storage
    Given the Ruby source is:
      """
      total = 0
      puts [2, 3].map { |value| total = value; break "stop" }
      puts total
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Empty iterators check breaks without applying their effects
    Given the Ruby source is:
      """
      total = 0
      values = [].each { total = 1; break gets }
      puts values.length
      puts 0.times { total = 2; break gets }
      puts [].map { total = 3; break gets }.length
      puts total
      puts gets&.chomp
      """
    And standard input is:
      """
      first
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Each can conditionally break with its original shared receiver
    Given the Ruby source is:
      """
      values = [1, 2, 3]
      result = values.each do |value|
        puts value
        if value == 2
          break values
        end
      end
      result[0] = 9
      puts values[0]
      puts result.length
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Inner iterator breaks do not stop an outer iterator
    Given the Ruby source is:
      """
      puts 2.times { |outer| puts 3.times { |inner| puts "#{outer}:#{inner}"; break 7 }; puts "outer" }
      puts "after"
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Ordinary loop breaks keep their own target inside a block
    Given the Ruby source is:
      """
      puts 3.times { |index| inner = while true; break index; end; puts inner; if index == 1; break 9; end }
      puts "after"
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: An object break result preserves identity and field writes
    Given the Ruby source is:
      """
      class Item
        def initialize; @value = 1; end
        def set; @value = 2; self; end
        def value; @value; end
      end
      item = Item.new
      result = [item].each { |value| break value.set }
      puts result == item
      puts item.value
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Breaking a yielded block skips the method remainder
    Given the Ruby source is:
      """
      class Producer
        def run
          yield(2)
          puts "unexpected"
          "normal"
        end
      end
      total = 0
      puts Producer.new.run { |value| total += value; break "found"; total = 99 }
      puts total
      puts "after"
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Conditional block breaks stop a yielding method loop
    Given the Ruby source is:
      """
      class Producer
        def run
          index = 0
          while index < 3
            yield(index)
            puts "continued"
            index += 1
          end
          "normal"
        end
      end
      last = -1
      puts Producer.new.run { |value| last = value; if value == 1; break "found"; end }
      puts last
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Breaks crossing nested lexical yield exit the original receiving method
    Given the Ruby source is:
      """
      class Relay
        def once(value)
          yield(value)
          puts "unexpected inner"
          "inner"
        end
        def run(other)
          other.once(2) { |value| yield(value + 1) }
          puts "unexpected outer"
          "outer"
        end
      end
      puts Relay.new.run(Relay.new) { |value| break value }
      puts "after"
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Breaks in nested user blocks remain local to the inner method
    Given the Ruby source is:
      """
      class Producer
        def inner(value)
          yield(value)
        end
        def run(value)
          yield(value)
          puts "continued"
          "normal"
        end
      end
      producer = Producer.new
      puts producer.run(2) { |outer| puts producer.inner(3) { |inner| break inner }; outer }
      puts "after"
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: An ignored block can contain a break without changing the method result
    Given the Ruby source is:
      """
      class Producer
        def run; "normal"; end
      end
      total = 0
      puts Producer.new.run { total = 5; break "unused" }
      puts total
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Unknown receiver checking defers break results until actual calls
    Given the Ruby source is:
      """
      class Producer
        def run; yield(2); 99; end
      end
      class Caller
        def run(other)
          other.run { |value| break value + 1 }
        end
      end
      puts Caller.new.run(Producer.new)
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Breaking block results do not exit the callers own method
    Given the Ruby source is:
      """
      class Producer
        def run; yield; "normal"; end
      end
      class Caller
        def run(producer)
          puts producer.run { break "found" }
          "caller"
        end
      end
      puts Caller.new.run(Producer.new)
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Unreachable breaks do not replace the first break state or value
    Given the Ruby source is:
      """
      last = 0
      puts 2.times { last = 1; break 7; last = 2; break "unused" }
      puts last
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Break arguments preserve their side effects and result evaluation order
    Given the Ruby source is:
      """
      trace = "A"
      puts 2.times { break(trace << "!") }
      puts trace
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Break with no value returns nil from a yielding method
    Given the Ruby source is:
      """
      class Producer
        def run; yield; "normal"; end
      end
      puts Producer.new.run { break } == nil
      puts "after"
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Zero iteration loops do not keep speculative block exits
    Given the Ruby source is:
      """
      class Producer
        def run
          index = 0
          while index < 0
            yield(1)
          end
          "normal"
        end
      end
      total = 0
      puts Producer.new.run { total = 5; break 9 }
      puts total
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Post test yielding loops preserve block exits from their first iteration
    Given the Ruby source is:
      """
      class Producer
        def run
          begin
            yield(1)
          end while false
          "normal"
        end
      end
      puts Producer.new.run { break "found" }
      puts "after"
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Breaks from a yielded block inside an iterator exit the yielding method
    Given the Ruby source is:
      """
      class Producer
        def run
          3.times { |index| yield(index); puts "unexpected" }
          "normal"
        end
      end
      puts Producer.new.run { |value| break value }
      puts "after"
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Conditional scalar breaks from each require an unsupported result join
    Given the Ruby source is:
      """
      values = [1, 2]; values.each { |value| if value == 1; break 7; end }
      """
    When I emit a Rust project
    Then the diagnostic has code "E_UNSUPPORTED" at line 1
    And no Rust project was created

  Scenario: Conditional scalar breaks from map require an unsupported result join
    Given the Ruby source is:
      """
      [1, 2].map { |value| if value == 1; break 7; end; value }
      """
    When I emit a Rust project
    Then the diagnostic has code "E_UNSUPPORTED" at line 1
    And no Rust project was created

  Scenario: Known invalid expressions after break remain checked
    Given the Ruby source is:
      """
      1.times { break 7; "bad" + 1 }
      """
    When I emit a Rust project
    Then the diagnostic has code "E_UNSUPPORTED" at line 1
    And no Rust project was created

  Scenario: Captured possible zero values on break paths cannot silently pass division checks
    Given the Ruby source is:
      """
      total = 5
      2.times { |value| if value == 1; total = 0; break 7; end; total = 5 }
      puts 30 / total
      """
    When I emit a Rust project
    Then the diagnostic has code "E_UNSUPPORTED" at line 3
    And no Rust project was created

  Scenario: Different object break results remain unsupported
    Given the Ruby source is:
      """
      class Item; end
      first = Item.new
      second = Item.new
      2.times { |value| if value == 1; break first; end; break second }
      """
    When I emit a Rust project
    Then the diagnostic has code "E_UNSUPPORTED" at line 4
    And no Rust project was created

  Scenario: Next continues a times block
    Given the Ruby source is:
      """
      1.times { next 7 }
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Nonlocal returns from a block remain unsupported
    Given the Ruby source is:
      """
      class Caller; def run; 1.times { return 7 }; end; end
      """
    When I emit a Rust project
    Then the diagnostic has code "E_UNSUPPORTED" at line 1
    And no Rust project was created

  Scenario: Unreachable breaks do not accept non-fallthrough bodies
    Given the Ruby source is:
      """
      1.times { while true; end; break 7 }
      """
    When I emit a Rust project
    Then the diagnostic has code "E_UNSUPPORTED" at line 1
    And no Rust project was created

  Scenario: Conditional breaks across a nested lexical yield merge only receiving caller captures
    Given the Ruby source is:
      """
      class Relay
        def once(value)
          yield(value)
          "inner"
        end
        def run(other)
          other.once(2) { |value| yield(value) }
          "outer"
        end
      end
      last = 0
      puts Relay.new.run(Relay.new) { |value| last = value; if value == 2; break "found"; end }
      puts last
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Recursive receiving methods remain unsupported even with nested blocks
    Given the Ruby source is:
      """
      class Producer
        def run(value)
          yield(value)
          "normal"
        end
      end
      producer = Producer.new
      producer.run(2) { |outer| producer.run(3) { |inner| break inner }; outer }
      """
    When I emit a Rust project
    Then the diagnostic has code "E_UNSUPPORTED" at line 8
    And no Rust project was created

  Scenario: Break from a block in a yielding loop predicate exits the receiving method
    Given the Ruby source is:
      """
      class Producer
        def run
          while yield(1)
            puts "unexpected body"
          end
          "normal"
        end
      end
      puts Producer.new.run { break "found" }
      puts "after"
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Break with multiple values remains unsupported
    Given the Ruby source is:
      """
      1.times { break 1, 2 }
      """
    When I emit a Rust project
    Then the diagnostic has code "E_UNSUPPORTED" at line 1
    And no Rust project was created

  Scenario: The first large invoice example builds independently
    Given I use the example "first_large_invoice.rb"
    When I emit a Rust project
    Then the emitted project contains its source and runtime
    When I build and run the emitted project
    Then stdout, stderr, and exit status match CRuby

  Scenario: Growing an iterated array remains unsupported on a block break path
    Given the Ruby source is:
      """
      values = [1, 2]
      values.each { |value| if value == 1; values.push(3); break values; end }
      puts values.length
      """
    When I emit a Rust project
    Then the diagnostic has code "E_UNSUPPORTED" at line 2
    And no Rust project was created
