# language: en
Feature: Preserve namespaces and class object semantics

  Scenario: Nested constants preserve lexical and absolute lookup
    Given the Ruby source is:
      """
      ROOT = 7
      module Pricing
        RATE = 10
        class Quote
          def value; RATE + ::ROOT; end
        end
      end
      puts Pricing::Quote.new.value
      puts Pricing::RATE
      puts ROOT
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Class bodies execute once with their own locals and class object fields
    Given the Ruby source is:
      """
      value = "outside"
      class Choice
        value = "inside"
        puts value
        @value = 7
        def self.value; @value; end
      end
      puts value
      puts Choice.value
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Class aliases preserve constructor identity and class receiver state
    Given the Ruby source is:
      """
      class Choice
        @value = 7
        def initialize(value); @value = value; end
        def value; @value; end
        def self.value; @value; end
      end
      alias_class = Choice
      puts alias_class == Choice
      puts alias_class.new(9).value
      puts alias_class.value
      puts Choice.value
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Qualified declarations preserve their actual lexical nesting
    Given the Ruby source is:
      """
      ROOT = 1
      module Outer
        ROOT = 7
        class Nested
          def value; ROOT; end
        end
      end
      class Outer::Qualified
        def value; ROOT; end
      end
      puts Outer::Nested.new.value
      puts Outer::Qualified.new.value
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Lexical constants outrank inherited constants
    Given the Ruby source is:
      """
      class Base
        VALUE = 9
      end
      module Outer
        VALUE = 7
        class Child < Base
          def value; VALUE; end
        end
      end
      puts Outer::Child.new.value
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Inherited constants resolve through qualified paths
    Given the Ruby source is:
      """
      class Base
        VALUE = 7
      end
      class Child < Base
        def value; VALUE; end
      end
      puts Child::VALUE
      puts Child.new.value
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Constant aliases retain shared collection storage
    Given the Ruby source is:
      """
      VALUES = [7]
      alias_values = VALUES
      alias_values[0] = 9
      puts VALUES[0]
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Class body calls observe definition and effect order
    Given the Ruby source is:
      """
      class Choice
        puts "before"
        def self.build(value); puts value; value + 1; end
        @value = build(7)
        puts "after"
        def self.value; @value; end
      end
      puts Choice.value
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Inherited class methods keep per class instance variable state
    Given the Ruby source is:
      """
      class Base
        @value = 7
        def self.value; @value; end
        def self.store(value); @value = value; end
      end
      class Child < Base; end
      puts Child.value == nil
      Child.store(9)
      puts Child.value
      puts Base.value
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Class method super starts above its defining owner
    Given the Ruby source is:
      """
      class Base
        def self.value(number); number + 1; end
      end
      class Child < Base
        def self.value(number = 7); super(number + 1); end
      end
      class Leaf < Child; end
      puts Leaf.value
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Class method literal blocks retain normal argument and exit semantics
    Given the Ruby source is:
      """
      class Choice
        def self.value(number = 7, &callback); callback.call(number); end
      end
      puts Choice.value { |number| number + 10 }
      puts Choice.value { break 9 }
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Singleton class declarations define class methods with isolated locals
    Given the Ruby source is:
      """
      class Choice
        @value = 7
        class << self
          def value; @value; end
          def store(value); @value = value; end
        end
      end
      Choice.store(9)
      puts Choice.value
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Class method errors preserve Ruby singleton method frames
    Given the Ruby source is:
      """
      class Choice
        def self.value; raise "broken"; end
      end
      Choice.value
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Namespace body errors preserve nested class and module frames
    Given the Ruby source is:
      """
      module Outer
        class Choice
          raise "broken"
        end
      end
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby
