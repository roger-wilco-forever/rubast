Feature: Nonlocal return from literal blocks

  Scenario: Each returns from its defining method and leaves the caller running
    Given the Ruby source is:
      """
      class Finder
        def run
          [1, 2, 3].each { |value| puts value; return value if value == 2 }
          puts "unexpected"
          0
        end
      end
      puts Finder.new.run
      puts "after"
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Map returns a scalar instead of partial mapped storage
    Given the Ruby source is:
      """
      class Finder
        def run
          [1, 2].map { |value| puts value; return "found" }
          "unexpected"
        end
      end
      puts Finder.new.run
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Return without a value returns nil from its method
    Given the Ruby source is:
      """
      class Finder
        def run; 2.times { return }; "unexpected"; end
      end
      puts Finder.new.run == nil
      puts "after"
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Nested iterators return through both receivers
    Given the Ruby source is:
      """
      class Finder
        def run
          3.times do |outer|
            2.times { |inner| puts "#{outer}:#{inner}"; return outer + inner if inner == 1 }
            puts "unexpected"
          end
          9
        end
      end
      puts Finder.new.run
      puts "after"
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Return crosses an ordinary loop without confusing its exits
    Given the Ruby source is:
      """
      class Finder
        def run
          2.times do
            index = 0
            while index < 2
              index += 1
              next if index == 1
              return index
            end
          end
          9
        end
      end
      puts Finder.new.run
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Yield returns from the lexical caller and skips the producer remainder
    Given the Ruby source is:
      """
      class Producer
        def run; puts "before"; yield(7); puts "unexpected producer"; 0; end
      end
      class Finder
        def run(other)
          other.run { |value| return value + 1 }
          puts "unexpected caller"
          0
        end
      end
      puts Finder.new.run(Producer.new)
      puts "after"
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Nested lexical yields return through intervening method invocations
    Given the Ruby source is:
      """
      class Relay
        def once; yield(2); puts "unexpected inner"; 0; end
        def run(other); other.once { |value| yield(value + 1) }; puts "unexpected outer"; 0; end
      end
      class Finder
        def run(relay, other); relay.run(other) { |value| return value + 10 }; 0; end
      end
      puts Finder.new.run(Relay.new, Relay.new)
      puts "after"
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: A block declared in an inline yielding method returns only from that method
    Given the Ruby source is:
      """
      class Producer
        def run; 2.times { return "producer" }; yield; "unexpected"; end
      end
      class Finder
        def run(other); puts other.run { puts "unused" }; "caller"; end
      end
      puts Finder.new.run(Producer.new)
      puts "after"
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Helper methods have their own return target
    Given the Ruby source is:
      """
      class Finder
        def helper; 1.times { return 7 }; 0; end
        def run; 2.times { puts helper }; "caller"; end
      end
      puts Finder.new.run
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Return values perform side effects once and preserve string aliases
    Given the Ruby source is:
      """
      class Finder
        def run(trace); 2.times { return(trace << "!") }; "unexpected"; end
      end
      trace = "A"
      result = Finder.new.run(trace)
      result << "?"
      puts trace
      puts result
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Returned objects keep their shared identity
    Given the Ruby source is:
      """
      class Item
        def initialize; @value = 1; end
        def change; @value = 7; end
        def value; @value; end
      end
      class Finder
        def run(item); [1].each { return item }; item; end
      end
      item = Item.new
      result = Finder.new.run(item)
      result.change
      puts item.value
      puts result == item
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Return and normal completion join object fields
    Given the Ruby source is:
      """
      class Finder
        def initialize; @value = 0; end
        def run(flag)
          1.times { @value = 1; return "early" if flag }
          @value = 2
          "normal"
        end
        def value; @value; end
      end
      finder = Finder.new
      puts finder.run(gets)
      puts finder.value
      """
    And standard input is:
      """
      yes
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: A callee return joins mutations of the enclosing block capture
    Given the Ruby source is:
      """
      class Producer
        def run(flag)
          1.times { yield; return "early" if flag }
          "normal"
        end
      end
      last = 0
      puts Producer.new.run(gets) { last = 7 }
      puts last
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Empty iterators discard checked return effects and results
    Given the Ruby source is:
      """
      class Finder
        def run
          0.times { return gets }
          [].each { return "unused" }
          [].map { return "unused" }
          7
        end
      end
      puts Finder.new.run
      puts gets&.chomp
      """
    And standard input is:
      """
      first
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Ignored user blocks discard their checked returns
    Given the Ruby source is:
      """
      class Producer; def run; "producer"; end; end
      class Finder
        def run(other); puts other.run { return gets }; 7; end
      end
      puts Finder.new.run(Producer.new)
      puts gets&.chomp
      """
    And standard input is:
      """
      first
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: False loop bodies discard checked nonlocal returns
    Given the Ruby source is:
      """
      class Producer
        def run; while false; yield; end; "producer"; end
      end
      class Finder
        def run(other); puts other.run { return gets }; 7; end
      end
      puts Finder.new.run(Producer.new)
      puts gets&.chomp
      """
    And standard input is:
      """
      first
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Dead returns cannot change the method result or field state
    Given the Ruby source is:
      """
      class Finder
        def initialize; @value = 0; end
        def run; 1.times { @value = 1; return 7; @value = 9; return "unused" }; 0; end
        def value; @value; end
      end
      finder = Finder.new
      puts finder.run
      puts finder.value
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Return while evaluating next skips both block boundaries
    Given the Ruby source is:
      """
      class Producer; def run; yield; "unexpected"; end; end
      class Finder
        def run(other); other.run { next(if true; return 7; else; 0; end) }; 0; end
      end
      puts Finder.new.run(Producer.new)
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Return in a yielding loop predicate exits the lexical caller
    Given the Ruby source is:
      """
      class Producer; def run; while yield; puts "unexpected"; end; "normal"; end; end
      class Finder; def run(other); other.run { return 7 }; 0; end; end
      puts Finder.new.run(Producer.new)
      puts "after"
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Loop trials preserve only reachable nonlocal return states
    Given the Ruby source is:
      """
      class Producer
        def run
          index = 0
          while index < 3
            yield(index)
            index += 1
          end
          "normal"
        end
      end
      class Finder
        def run(other)
          other.run { |value| @last = value; return "found" if value == 1 }
          "missing"
        end
        def last; @last; end
      end
      finder = Finder.new
      puts finder.run(Producer.new)
      puts finder.last
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Inner method returns leave the outer nonlocal return available
    Given the Ruby source is:
      """
      class Producer
        def inner; yield; return "inner"; end
        def run(other); puts other.inner { yield }; "outer"; end
      end
      class Finder
        def run(other, inner); other.run(inner) { return "found" }; "missing"; end
      end
      puts Finder.new.run(Producer.new, Producer.new)
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Known invalid expressions after return remain checked
    Given the Ruby source is:
      """
      class Finder; def run; 1.times { return 7; "bad" + 1 }; end; end
      """
    When I emit a Rust project
    Then the diagnostic has code "E_UNSUPPORTED" at line 1
    And no Rust project was created

  Scenario: Return without a defining method remains unsupported
    Given the Ruby source is:
      """
      1.times { return 7 }
      """
    When I emit a Rust project
    Then the diagnostic has code "E_UNSUPPORTED" at line 1
    And no Rust project was created

  Scenario: Multiple return values remain unsupported
    Given the Ruby source is:
      """
      class Finder; def run; 1.times { return 1, 2 }; end; end
      """
    When I emit a Rust project
    Then the diagnostic has code "E_UNSUPPORTED" at line 1
    And no Rust project was created

  Scenario: Different object return handles still require an unsupported join
    Given the Ruby source is:
      """
      class Item; end
      class Finder
        def run(first, second)
          1.times { return first if gets }
          second
        end
      end
      Finder.new.run(Item.new, Item.new)
      """
    When I emit a Rust project
    Then the diagnostic has code "E_UNSUPPORTED" at line 8
    And no Rust project was created

  Scenario: Growing a traversed array remains unsupported on return paths
    Given the Ruby source is:
      """
      class Finder
        def run(values)
          values.each { values.push(3); return 7 }
          0
        end
      end
      Finder.new.run([1, 2])
      """
    When I emit a Rust project
    Then the diagnostic has code "E_UNSUPPORTED" at line 3
    And no Rust project was created

  Scenario: Fresh arrays in a return value remain unsupported inside a block
    Given the Ruby source is:
      """
      class Finder; def run; 1.times { return [1] }; end; end
      """
    When I emit a Rust project
    Then the diagnostic has code "E_UNSUPPORTED" at line 1
    And no Rust project was created

  Scenario: A dead return cannot make an infinite block body acceptable
    Given the Ruby source is:
      """
      class Finder; def run; 1.times { while true; end; return 7 }; end; end
      """
    When I emit a Rust project
    Then the diagnostic has code "E_UNSUPPORTED" at line 1
    And no Rust project was created

  Scenario: Break next and return keep their distinct targets
    Given the Ruby source is:
      """
      class Finder
        def run
          3.times do |index|
            next if index == 0
            puts 2.times { break 8 }
            return index
          end
          0
        end
      end
      puts Finder.new.run
      puts "after"
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: A possible captured zero uses runtime division checks
    Given the Ruby source is:
      """
      class Producer
        def run(flag)
          1.times { yield(0); return 7 if flag }
          yield(5)
          9
        end
      end
      total = 5
      Producer.new.run(gets) { |value| total = value }
      puts 30 / total
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Return snapshots exclude intervening block parameters and callee captures
    Given the Ruby source is:
      """
      class Producer
        def once(value); yield(value); 0; end
        def run(other); other.once(2) { |value; scratch| scratch = value; yield(scratch) }; 0; end
      end
      class Finder
        def run(other, inner, flag)
          other.run(inner) { |value; scratch| scratch = value; return scratch if flag }
          7
        end
      end
      puts Finder.new.run(Producer.new, Producer.new, gets)
      puts "after"
      """
    And standard input is:
      """
      yes
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Return keeps inherited lexical super and the concrete receiver
    Given the Ruby source is:
      """
      class Base
        def value(number); number + 10; end
      end
      class Child < Base
        def value(number); 1.times { |number| return super }; 0; end
      end
      puts Child.new.value(7)
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Return value evaluation can break its receiving method instead
    Given the Ruby source is:
      """
      class Relay
        def once; yield; "inner"; end
        def run(other); other.once { return yield }; "outer"; end
      end
      puts Relay.new.run(Relay.new) { break "found" }
      puts "after"
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: The invoice search example builds independently
    Given I use the example "invoice_search.rb"
    When I emit a Rust project
    Then the emitted project contains its source and runtime
    When I build and run the emitted project
    Then stdout, stderr, and exit status match CRuby
