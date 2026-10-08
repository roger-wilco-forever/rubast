# language: en
Feature: Stateless user classes
  Scenario: Construct objects and return instance method values
    Given the Ruby source is:
      """
      class Greeter
        def greet(name)
          "Hello, #{name}!"
        end
        def number
          42
        end
      end
      greeter = Greeter.new
      alias_greeter = greeter
      puts alias_greeter.greet("Zoë")
      puts Greeter.new.number
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Resolve methods by receiver class and preserve return types
    Given the Ruby source is:
      """
      class Echo
        def value(input)
          input
        end
      end
      class Answer
        def value
          42
        end
      end
      object = Echo.new
      puts object.value("Ada")&.chomp
      puts object.value(7)
      object = Answer.new
      puts object.value
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Evaluate arguments once in order and isolate parameters
    Given the Ruby source is:
      """
      class Pair
        def join(first, second)
          "#{second}:#{first}:#{first}"
        end
      end
      first = "outside"
      puts Pair.new.join(gets&.chomp, gets&.chomp)
      puts first
      """
    And standard input is:
      """
      Ada
      Zoë
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Execute method calls used as statements and input expressions
    Given the Ruby source is:
      """
      class Reader
        def read
          gets
        end
      end
      Reader.new.read
      puts "#{Reader.new.read&.chomp}:#{Reader.new.read&.chomp}"
      """
    And standard input is:
      """
      discard
      Ada
      Zoë
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario Outline: Reject unsupported class semantics before emission
    Given the Ruby source is:
      """
      <source>
      """
    When I run Rubast
    Then the diagnostic has code "E_UNSUPPORTED" at line 1

    Examples:
      | source                                                                         |
      | class Child < Object; def name; "child"; end; end                              |
      | class Stateful; def initialize; "init"; end; end; Stateful.new.initialize      |
      | class Singleton; def self.value; 42; end; end                                  |
      | class Duplicate; def value; 1; end; def value; 2; end; end                     |
      | class Reopened; def value; 1; end; end; class Reopened; def other; 2; end; end |
      | class String; def value; 1; end; end                                           |
      | class Greeter; def greet(name); name; end; end; puts Greeter.new.missing       |
      | class Greeter; def greet(name); name; end; end; puts Greeter.new               |
      | class Greeter; def greet(name); name; end; end; puts "#{Greeter.new}"          |
      | puts Future.new.value; class Future; def value; 1; end; end                    |
      | class Hidden; def value; unknown; end; end                                     |

  Scenario Outline: Accepted extended argument fixtures preserve Ruby execution
    Given the Ruby source is:
      """
      <source>
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

    Examples:
      | source |
      | class Default; def value(input = "default"); input; end; end |
      | class Keyword; def value(input:); input; end; end |
      | class Greeter; def greet(name); name; end; end; puts Greeter.new.greet |
      | class Greeter; def greet(name); name; end; end; puts Greeter.new("Ada") |
