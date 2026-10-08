Feature: Static method visibility and attributes
  Visibility and generated attributes preserve Ruby behavior.

  Scenario: Private calls allow implicit and literal self receivers
    Given the Ruby source is:
      """
      class Choice
        private
        def hidden; 7; end
        public
        def value; hidden + self.hidden; end
      end
      puts Choice.new.value
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Named visibility affects inherited methods
    Given the Ruby source is:
      """
      class Base
        def hidden; 7; end
      end
      class Choice < Base
        private :hidden
        def value; hidden; end
      end
      puts Choice.new.value
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Protected calls accept related receivers in related method contexts
    Given the Ruby source is:
      """
      class Choice
        def initialize(value); @value = value; end
        protected
        def hidden; @value; end
        public
        def value(other); other.hidden + hidden; end
      end
      left = Choice.new(7)
      right = Choice.new(9)
      puts left.value(right)
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Module method visibility survives include
    Given the Ruby source is:
      """
      module Rules
        private
        def hidden; 7; end
        public
        def value; hidden; end
      end
      class Choice
        include Rules
      end
      puts Choice.new.value
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Private class methods use literal self and implicit receivers
    Given the Ruby source is:
      """
      class Choice
        def self.hidden; 7; end
        private_class_method :hidden
        def self.value; hidden + self.hidden; end
      end
      puts Choice.value
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Class body default visibility does not change explicit singleton methods
    Given the Ruby source is:
      """
      class Choice
        private
        def self.value; 7; end
      end
      puts Choice.value
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Singleton body visibility changes singleton methods
    Given the Ruby source is:
      """
      class Choice
        class << self
          private
          def hidden; 7; end
          public
          def value; hidden; end
        end
      end
      puts Choice.value
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Visibility declaration wrappers return method names
    Given the Ruby source is:
      """
      class Choice
        private def hidden; 7; end
        def value; hidden; end
      end
      puts Choice.new.value
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Readers writers and accessors preserve nil values and shared storage
    Given the Ruby source is:
      """
      class Choice
        attr_reader :name
        attr_writer :name
        attr_accessor :value
        def initialize(name); @name = name; end
      end
      item = Choice.new("Ada")
      puts item.name
      puts item.value
      item.name = "Roger"
      item.value = 7
      puts item.name
      puts item.value
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Setter assignment returns the right hand side rather than method return
    Given the Ruby source is:
      """
      class Choice
        attr_reader :value
        def value=(number); @value = number; 99; end
      end
      item = Choice.new
      puts(item.value = 7)
      puts item.value
      puts item.value=(9)
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Setter receiver and right hand side run once in source order
    Given the Ruby source is:
      """
      class Choice
        attr_accessor :value
      end
      class Factory
        def initialize; @item = Choice.new; @trace = ""; end
        def item; @trace << "receiver"; @item; end
        def number; @trace << ":argument"; 7; end
        def trace; @trace; end
      end
      factory = Factory.new
      puts(factory.item.value = factory.number)
      puts factory.trace
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Accessor visibility follows the current declaration default
    Given the Ruby source is:
      """
      class Choice
        private
        attr_accessor :value
        public
        def store(number); self.value = number; end
        def read; value; end
      end
      item = Choice.new
      puts item.store(7)
      puts item.read
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Singleton accessors use class object fields and inheritance
    Given the Ruby source is:
      """
      class Base
        class << self
          attr_accessor :value
        end
        self.value = 7
      end
      class Choice < Base
      end
      puts Base.value
      puts Choice.value
      Choice.value = 9
      puts Choice.value
      puts Base.value
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Accessor declarations return Ruby arrays of symbol names
    Given the Ruby source is:
      """
      class Choice
        names = attr_accessor(:value, :name)
        puts names.length
        puts names[0]
        puts names[1]
        puts names[3]
      end
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Inherited accessor dispatch can continue with super
    Given the Ruby source is:
      """
      class Base
        attr_accessor :value
      end
      class Choice < Base
        def value; super + 1; end
      end
      item = Choice.new
      item.value = 7
      puts item.value
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Accessor argument errors retain native Ruby call locations
    Given the Ruby source is:
      """
      class Choice
        attr_accessor :value
      end
      Choice.new.value(7)
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Multiple accessor arguments retain native Ruby call locations
    Given the Ruby source is:
      """
      class Choice
        attr_accessor :value
      end
      Choice.new.value(7, 9)
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Private methods reject ordinary explicit receivers
    Given the Ruby source is:
      """
      class Choice; private; def hidden; 7; end; end; Choice.new.hidden
      """
    When I emit a Rust project
    Then the diagnostic has code "E_UNSUPPORTED" at line 1
    And no Rust project was created

  Scenario: Private methods reject self aliases
    Given the Ruby source is:
      """
      class Choice; private; def hidden; 7; end; public; def value; other = self; other.hidden; end; end; Choice.new.value
      """
    When I emit a Rust project
    Then the diagnostic has code "E_UNSUPPORTED" at line 1
    And no Rust project was created

  Scenario: Protected methods reject unrelated top level callers
    Given the Ruby source is:
      """
      class Choice; protected; def hidden; 7; end; end; Choice.new.hidden
      """
    When I emit a Rust project
    Then the diagnostic has code "E_UNSUPPORTED" at line 1
    And no Rust project was created

  Scenario: Private class methods reject outside calls
    Given the Ruby source is:
      """
      class Choice; def self.hidden; 7; end; private_class_method :hidden; end; Choice.hidden
      """
    When I emit a Rust project
    Then the diagnostic has code "E_UNSUPPORTED" at line 1
    And no Rust project was created

  Scenario: Private inherited accessors reject outside calls
    Given the Ruby source is:
      """
      class Choice; private; attr_reader :value; end; Choice.new.value
      """
    When I emit a Rust project
    Then the diagnostic has code "E_UNSUPPORTED" at line 1
    And no Rust project was created

