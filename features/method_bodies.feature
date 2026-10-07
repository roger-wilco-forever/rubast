# language: en
Feature: Preserve expression sequences in instance methods
  Scenario: Print intermediate values and return the last expression
    Given the Ruby source is:
      """
      class Greeter
        def greet(name)
          message = "Hello, #{name}!"
          puts message
          name = "inside"
          message = "#{message} Again."
          message
        end
      end
      name = "outside"
      message = "caller"
      puts Greeter.new.greet("Zoë")
      puts Greeter.new.greet("Ada")
      puts "#{name}:#{message}"
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Return assignments and isolate reassigned parameters
    Given the Ruby source is:
      """
      class Echo
        def value(input)
          input = "#{input}!"
          output = input
        end
      end
      input = "Ada"
      puts Echo.new.value(input)
      puts input
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Return nil from empty methods and puts
    Given the Ruby source is:
      """
      class Empty
        def nothing
        end
        def explicit_nil
          nil
        end
        def print
          puts "printed"
        end
      end
      puts "empty:#{Empty.new.nothing}"
      puts "nil:#{Empty.new.explicit_nil}"
      puts "result:#{Empty.new.print}"
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Read a local as nil while initializing it
    Given the Ruby source is:
      """
      class Empty
        def value
          input = input
          puts "before:#{input}"
          input = 42
          input
        end
      end
      puts Empty.new.value
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Validate operations using the argument types at each call
    Given the Ruby source is:
      """
      class Cleaner
        def clean(input)
          result = input&.chomp
          puts "clean:#{result}"
          result
        end
      end
      puts Cleaner.new.clean("Ada\n")
      puts Cleaner.new.clean(nil)
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Preserve reads before later assignments in interpolation
    Given the Ruby source is:
      """
      class Echo
        def value(input)
          "#{input}:#{input = "changed"}:#{input}"
        end
      end
      puts Echo.new.value("original")
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Run each method and argument exactly once in order
    Given the Ruby source is:
      """
      class Reader
        def read(label)
          puts label
          value = gets&.chomp
          puts "read:#{value}"
          value
        end
      end
      class Pair
        def join(first, second)
          puts "joining"
          "#{second}:#{first}:#{first}"
        end
      end
      puts Pair.new.join(Reader.new.read("first"), Reader.new.read("second"))
      """
    And standard input is:
      """
      Ada
      Zoë
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Keep argument types from the time each argument is evaluated
    Given the Ruby source is:
      """
      class Cleaner
        def first(first, second)
          first&.chomp
        end
      end
      input = "Ada\n"
      puts Cleaner.new.first(input, input = 42)
      puts input
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Reject an invalid earlier argument despite later reassignment
    Given the Ruby source is:
      """
      class Cleaner
        def first(first, second)
          first&.chomp
        end
      end
      input = 42
      puts Cleaner.new.first(input, input = "Ada")
      """
    When I run Rubast
    Then the diagnostic has code "E_UNSUPPORTED" at line 3

  Scenario: Reject a parameter operation with an unsupported argument type
    Given the Ruby source is:
      """
      class Cleaner
        def clean(input)
          input&.chomp
        end
      end
      puts Cleaner.new.clean(42)
      """
    When I run Rubast
    Then the diagnostic has code "E_UNSUPPORTED" at line 3

  Scenario: Validate intermediate expressions in unused methods
    Given the Ruby source is:
      """
      class Hidden
        def value
          puts "before"
          unknown
          42
        end
      end
      puts "outside"
      """
    When I run Rubast
    Then the diagnostic has code "E_UNSUPPORTED" at line 4
