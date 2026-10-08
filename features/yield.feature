Feature: Yield to literal blocks in user instance methods

  Scenario: Repeated yields return block results and update captures
    Given the Ruby source is:
      """
      class Producer
        def run(value)
          first = yield(value)
          second = yield(value + 1)
          first + second
        end
      end
      sum = 0
      puts Producer.new.run(2) { |value| sum += value; sum * 2 }
      puts sum
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Caller self and locals stay separate from the yielding receiver
    Given the Ruby source is:
      """
      class Producer
        def initialize
          @name = "producer"
        end
        def run(name)
          puts @name
          puts name
          result = yield("argument")
          puts name
          result
        end
      end
      class Caller
        def initialize
          @name = "caller"
        end
        def name
          @name
        end
        def run(producer)
          name = "outer"
          result = producer.run("inner") { |value; name| name = value; puts self.name; puts @name; name }
          puts name
          result
        end
      end
      puts Caller.new.run(Producer.new)
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Conditional yields merge captured locals and object state
    Given the Ruby source is:
      """
      class Producer
        def run(flag)
          if flag
            yield(3)
            return "early"
          else
            yield(5)
          end
          "late"
        end
      end
      total = 0
      name = "A"
      producer = Producer.new
      puts producer.run(gets&.chomp == "yes") { |value| total = value; name << "!" }
      puts total
      puts name
      """
    And standard input is:
      """
      yes
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Zero argument yield supplies nil and ignores extra block parameters
    Given the Ruby source is:
      """
      class Producer
        def run
          yield
        end
      end
      puts Producer.new.run { |value| value == nil }
      puts Producer.new.run { "constant" }
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Yield arguments evaluate once before the block captures are read
    Given the Ruby source is:
      """
      class Producer
        def run
          name = "before"
          yield(name, name = "after")
        end
      end
      name = "caller"
      puts Producer.new.run { |value| puts name; value }
      puts name
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Block locals start fresh and nested iterators capture the block parameter
    Given the Ruby source is:
      """
      class Producer
        def run
          yield(2)
          yield(3)
        end
      end
      sum = 0
      puts Producer.new.run { |value; scratch| puts scratch == nil; scratch = value; 2.times { sum += scratch }; sum }
      puts sum
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Method returns exit the yielding method and leave the caller running
    Given the Ruby source is:
      """
      class Producer
        def run(flag)
          value = yield(2)
          if flag
            return value + 10
          end
          yield(3)
        end
      end
      producer = Producer.new
      sum = 0
      puts producer.run(true) { |value| sum += value; value }
      puts sum
      puts producer.run(false) { |value| sum += value; value }
      puts sum
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Nested user blocks and lexical yield reach the correct block
    Given the Ruby source is:
      """
      class Relay
        def once(value)
          yield(value)
        end
        def run(other)
          other.once(2) { |value| yield(value + 1) }
        end
      end
      sum = 0
      puts Relay.new.run(Relay.new) { |value| sum += value; sum }
      puts sum
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Captured scalar writes participate in yielding loop invariants
    Given the Ruby source is:
      """
      class Producer
        def run
          index = 0
          while index < 3
            yield(index)
            index += 1
          end
          "done"
        end
      end
      last = -1
      puts Producer.new.run { |value| last = value; value }
      puts last
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Blocks can call helpers that return and methods with matching iterator names
    Given the Ruby source is:
      """
      class Producer
        def each(value)
          yield(value)
        end
        def helper(value)
          return value + 1
        end
      end
      producer = Producer.new
      puts producer.each(2) { |value| producer.helper(value) }
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: An ignored block is checked without executing captured effects
    Given the Ruby source is:
      """
      class Producer
        def run
          "done"
        end
      end
      sum = 0
      puts Producer.new.run { sum += 1 }
      puts sum
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Shared objects returned by yield keep their identity
    Given the Ruby source is:
      """
      class Producer
        def run
          yield
        end
      end
      values = ["A"]
      copy = Producer.new.run { values }
      copy[0] << "!"
      puts values[0]
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Missing block
    Given the Ruby source is:
      """
      class Producer; def run; yield(1); end; end
      Producer.new.run
      """
    When I emit a Rust project
    Then the diagnostic has code "E_UNSUPPORTED" at line 1
    And no Rust project was created

  Scenario: Yield at top level
    Given the Ruby source is:
      """
      yield(1)
      """
    When I emit a Rust project
    Then the diagnostic has code "E_PARSE" at line 1
    And no Rust project was created

  Scenario: A helper does not inherit its callers block
    Given the Ruby source is:
      """
      class Producer
        def run; helper; end
        def helper; yield; end
      end
      Producer.new.run { 1 }
      """
    When I emit a Rust project
    Then the diagnostic has code "E_UNSUPPORTED" at line 3
    And no Rust project was created

  Scenario: Ignored invalid block
    Given the Ruby source is:
      """
      class Producer; def run; 1; end; end
      Producer.new.run { "bad" + 1 }
      """
    When I emit a Rust project
    Then the diagnostic has code "E_UNSUPPORTED" at line 2
    And no Rust project was created

  Scenario: Nonlocal return remains unsupported
    Given the Ruby source is:
      """
      class Producer; def run; yield; end; end
      Producer.new.run { return 1 }
      """
    When I emit a Rust project
    Then the diagnostic has code "E_UNSUPPORTED" at line 2
    And no Rust project was created

  Scenario: Block break remains unsupported
    Given the Ruby source is:
      """
      class Producer; def run; yield; end; end
      Producer.new.run { break 1 }
      """
    When I emit a Rust project
    Then the diagnostic has code "E_UNSUPPORTED" at line 2
    And no Rust project was created

  Scenario: Block next remains unsupported
    Given the Ruby source is:
      """
      class Producer; def run; yield; end; end
      Producer.new.run { next 1 }
      """
    When I emit a Rust project
    Then the diagnostic has code "E_UNSUPPORTED" at line 2
    And no Rust project was created

  Scenario: Fresh arrays in a yielded body remain unsupported
    Given the Ruby source is:
      """
      class Producer; def run; yield; end; end
      Producer.new.run { [1] }
      """
    When I emit a Rust project
    Then the diagnostic has code "E_UNSUPPORTED" at line 2
    And no Rust project was created

  Scenario: Safe navigation with a block remains unsupported
    Given the Ruby source is:
      """
      class Producer; def run; yield; end; end
      Producer.new&.run { 1 }
      """
    When I emit a Rust project
    Then the diagnostic has code "E_UNSUPPORTED" at line 2
    And no Rust project was created

  Scenario: Blocks on new remain unsupported
    Given the Ruby source is:
      """
      class Producer; def initialize; yield; end; end
      Producer.new { 1 }
      """
    When I emit a Rust project
    Then the diagnostic has code "E_UNSUPPORTED" at line 2
    And no Rust project was created

  Scenario: Implicit super does not silently drop a required block
    Given the Ruby source is:
      """
      class Base; def run; yield; end; end
      class Child < Base; def run; super; end; end
      Child.new.run { 1 }
      """
    When I emit a Rust project
    Then the diagnostic has code "E_UNSUPPORTED" at line 1
    And no Rust project was created

  Scenario: Alternative yields merge captured locals and object state
    Given the Ruby source is:
      """
      class Producer
        def run(flag)
          if flag
            yield(3)
            return "early"
          else
            yield(5)
          end
          "late"
        end
      end
      total = 0
      name = "A"
      producer = Producer.new
      puts producer.run(gets&.chomp == "yes") { |value| total = value; name << "!" }
      puts total
      puts name
      """
    And standard input is:
      """
      no
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby


  Scenario: Receiver and arguments execute once in order
    Given the Ruby source is:
      """
      class Producer
        def choose(name)
          name << "R"
          self
        end
        def run(first, second)
          puts first
          puts second
          yield(2)
        end
      end
      producer = Producer.new
      trace = ""
      puts producer.choose(trace).run(trace + "A", trace << "B") { |value| puts trace; value }
      puts trace
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Implicit inherited calls yield to the callers lexical block
    Given the Ruby source is:
      """
      class Base
        def each(value)
          yield(value)
        end
      end
      class Child < Base
        def run
          value = "caller"
          each(3) { |item| puts value; item + 1 }
        end
      end
      puts Child.new.run
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Nested iterators in yielding methods call the attached block
    Given the Ruby source is:
      """
      class Producer
        def run
          3.times { |value| yield(value) }
        end
      end
      last = -1
      puts Producer.new.run { |value| last = value }
      puts last
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Yield argument effects update lexical captured fields before block reads
    Given the Ruby source is:
      """
      class Producer
        def run(other)
          yield(other.change, other.change)
        end
      end
      class Caller
        def initialize
          @value = "A"
        end
        def change
          @value << "!"
        end
        def run(producer)
          producer.run(self) { |value| puts @value; value }
        end
      end
      puts Caller.new.run(Producer.new)
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Inlined yielding returns cannot exit the callers own method
    Given the Ruby source is:
      """
      class Producer
        def run
          yield(1)
          return "producer"
        end
      end
      class Caller
        def run(producer)
          producer.run { |value| puts value }
          "caller"
        end
      end
      puts Caller.new.run(Producer.new)
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Function specialization distinguishes nested iterator counts in yielded blocks
    Given the Ruby source is:
      """
      class Producer
        def run
          yield
        end
      end
      class Caller
        def run(producer, count)
          last = -1
          producer.run { count.times { |value| last = value } }
          last
        end
      end
      caller = Caller.new
      producer = Producer.new
      puts caller.run(producer, 1)
      puts caller.run(producer, 3)
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Bare super in the supplied block uses the callers lexical method
    Given the Ruby source is:
      """
      class Producer
        def run
          yield(5)
        end
      end
      class Base
        def run(producer)
          "base"
        end
      end
      class Caller < Base
        def run(producer)
          producer.run { |producer| super }
        end
      end
      puts Caller.new.run(Producer.new)
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Known writes after yielding stay invalid even when the method is unused
    Given the Ruby source is:
      """
      class Producer
        def run
          yield
          "bad" + 1
        end
      end
      """
    When I emit a Rust project
    Then the diagnostic has code "E_UNSUPPORTED" at line 4
    And no Rust project was created

  Scenario: Joining incompatible captured scalar values does not falsely retain an integer
    Given the Ruby source is:
      """
      class Producer
        def run(flag)
          if flag
            yield(1)
          else
            yield("bad")
          end
        end
      end
      value = 0
      Producer.new.run(true) { |item| value = item }
      puts value + 1
      """
    When I emit a Rust project
    Then the diagnostic has code "E_UNSUPPORTED" at line 12
    And no Rust project was created

  Scenario: Splats in yield remain unsupported
    Given the Ruby source is:
      """
      class Producer
        def run
          yield(*[1])
        end
      end
      """
    When I emit a Rust project
    Then the diagnostic has code "E_UNSUPPORTED" at line 3
    And no Rust project was created

  Scenario: Keyword yield arguments remain unsupported
    Given the Ruby source is:
      """
      class Producer
        def run
          yield(name: "Ada")
        end
      end
      """
    When I emit a Rust project
    Then the diagnostic has code "E_UNSUPPORTED" at line 3
    And no Rust project was created

  Scenario: Wrong method arity with a block is rejected
    Given the Ruby source is:
      """
      class Producer; def run(value); yield(value); end; end
      Producer.new.run { 1 }
      """
    When I emit a Rust project
    Then the diagnostic has code "E_UNSUPPORTED" at line 2
    And no Rust project was created

  Scenario: Non-fallthrough yielded bodies remain unsupported
    Given the Ruby source is:
      """
      class Producer; def run; yield; end; end
      Producer.new.run { while true; end }
      """
    When I emit a Rust project
    Then the diagnostic has code "E_UNSUPPORTED" at line 2
    And no Rust project was created

  Scenario: A yield argument return skips the block and exits the yielding method
    Given the Ruby source is:
      """
      class Producer
        def run
          yield(if true; return "early"; else; "late"; end)
        end
      end
      total = 0
      puts Producer.new.run { total += 1 }
      puts total
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: A method argument return skips its yielding callee and the supplied block
    Given the Ruby source is:
      """
      class Producer
        def run(value)
          yield(value)
        end
        def caller
          run(if true; return "early"; else; "late"; end) { puts "unexpected" }
        end
      end
      puts Producer.new.caller
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: The invoice batch yielding example builds independently
    Given I use the example "yielding_batch.rb"
    When I emit a Rust project
    Then the emitted project contains its source and runtime
    When I build and run the emitted project
    Then stdout, stderr, and exit status match CRuby
