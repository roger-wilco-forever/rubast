Feature: Static class model boundaries
  Class semantics are supported only within the declared static subset.

  Scenario: Included constants participate in class and qualified lookup
    Given the Ruby source is:
      """
      module Rules
        VALUE = 7
      end
      class Choice
        include Rules
        def value; VALUE; end
      end
      puts Choice::VALUE
      puts Choice.new.value
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Module aliases retain namespace identity
    Given the Ruby source is:
      """
      module Rules
        VALUE = 7
      end
      Alias = Rules
      class Choice
        include Alias
      end
      puts Alias::VALUE
      puts Choice::VALUE
      puts Alias == Rules
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Class method constructors preserve receiver evaluation order
    Given the Ruby source is:
      """
      class Item
        attr_reader :value
        def initialize(value); @value = value; end
      end
      class Factory
        def initialize; @trace = ""; end
        def klass; @trace << "receiver"; Item; end
        def number; @trace << ":argument"; 7; end
        def trace; @trace; end
      end
      factory = Factory.new
      puts factory.klass.new(factory.number).value
      puts factory.trace
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Aliased constructors accept literal and forwarded blocks
    Given the Ruby source is:
      """
      class Choice
        attr_reader :value
        def initialize(number, &callback); @value = callback.call(number); end
      end
      class Factory
        def value(klass, &callback); klass.new(7, &callback); end
      end
      klass = Choice
      puts klass.new(7) { |number| number + 1 }.value
      puts Factory.new.value(klass) { |number| number + 2 }.value
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Class method overriding new retains user dispatch
    Given the Ruby source is:
      """
      class Choice
        def self.new(number); number + 1; end
      end
      klass = Choice
      puts Choice.new(7)
      puts klass.new(9)
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Visibility can make inherited class methods public again
    Given the Ruby source is:
      """
      class Base
        def self.value; 7; end
        private_class_method :value
      end
      class Choice < Base
        public_class_method :value
      end
      puts Choice.value
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Native accessor argument errors retain caller frames inside methods
    Given the Ruby source is:
      """
      class Choice
        attr_reader :value
      end
      class Caller
        def value(item); item.value(7); end
      end
      Caller.new.value(Choice.new)
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Native accessor argument errors retain caller frames with literal blocks
    Given the Ruby source is:
      """
      class Choice
        attr_reader :value
      end
      Choice.new.value(7) { puts "wrong" }
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Array equality responds to mutation across repeated calls
    Given the Ruby source is:
      """
      class Choice
        def equal(left, right); left == right; end
      end
      left = ["a"]
      right = ["a"]
      item = Choice.new
      puts item.equal(left, right)
      right[0] << "b"
      puts item.equal(left, right)
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Qualified constants do not fall back to root constants
    Given the Ruby source is:
      """
      VALUE = 7
      module Rules; end
      puts Rules::VALUE
      """
    When I emit a Rust project
    Then the diagnostic has code "E_UNSUPPORTED" at line 3
    And no Rust project was created

  Scenario: Module construction remains unsupported
    Given the Ruby source is:
      """
      module Rules; end
      Rules.new
      """
    When I emit a Rust project
    Then the diagnostic has code "E_UNSUPPORTED" at line 2
    And no Rust project was created

  Scenario: Constant reassignment remains unsupported
    Given the Ruby source is:
      """
      VALUE = 7
      VALUE = 9
      """
    When I emit a Rust project
    Then the diagnostic has code "E_UNSUPPORTED" at line 2
    And no Rust project was created

  Scenario: Dynamic class composition remains unsupported
    Given the Ruby source is:
      """
      module Rules; end
      class Choice; def value; include Rules; end; end
      """
    When I emit a Rust project
    Then the diagnostic has code "E_UNSUPPORTED" at line 2
    And no Rust project was created

  Scenario: Singleton class bodies reject eigenclass state
    Given the Ruby source is:
      """
      class Choice
        class << self
          @value = 7
        end
      end
      """
    When I emit a Rust project
    Then the diagnostic has code "E_UNSUPPORTED" at line 3
    And no Rust project was created

  Scenario: Module hooks remain unsupported
    Given the Ruby source is:
      """
      module Rules; def self.included(klass); puts "hook"; end; end
      class Choice; include Rules; end
      """
    When I emit a Rust project
    Then the diagnostic has code "E_UNSUPPORTED" at line 2
    And no Rust project was created

  Scenario: Cyclic module inclusion remains unsupported
    Given the Ruby source is:
      """
      module Rules; include self; end
      """
    When I emit a Rust project
    Then the diagnostic has code "E_UNSUPPORTED" at line 1
    And no Rust project was created

  Scenario: Cyclic array equality remains unsupported
    Given the Ruby source is:
      """
      values = []
      values.push(values)
      puts(values == values)
      """
    When I emit a Rust project
    Then the diagnostic has code "E_UNSUPPORTED" at line 3
    And no Rust project was created

  Scenario: Custom element equality remains unsupported
    Given the Ruby source is:
      """
      class Choice; def ==(other); true; end; end
      puts([Choice.new] == [Choice.new])
      """
    When I emit a Rust project
    Then the diagnostic has code "E_UNSUPPORTED" at line 2
    And no Rust project was created

  Scenario: Collection p inspection remains unsupported
    Given the Ruby source is:
      """
      p([7])
      """
    When I emit a Rust project
    Then the diagnostic has code "E_UNSUPPORTED" at line 1
    And no Rust project was created

  Scenario: Dynamic accessor names remain unsupported
    Given the Ruby source is:
      """
      class Choice; name = :value; attr_reader(name); end
      """
    When I emit a Rust project
    Then the diagnostic has code "E_UNSUPPORTED" at line 1
    And no Rust project was created


  Scenario: Native initializer argument errors retain Class new frames
    Given the Ruby source is:
      """
      class Choice
        attr_reader :initialize
      end
      Choice.new(7)
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Native initializer argument errors retain Class new frames with blocks
    Given the Ruby source is:
      """
      class Choice
        attr_reader :initialize
      end
      Choice.new(7) { puts "wrong" }
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Modular quotes combine host helpers attributes and inherited class method construction
    Given I use the example "workloads/modular_quote.rb"
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby
