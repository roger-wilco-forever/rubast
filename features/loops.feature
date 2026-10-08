# language: en
Feature: Preserve loop timing, state, and control values
  Scenario: Build and run the retained bounded-counter example
    Given I use the example "bounded_counter.rb"
    When I emit a Rust project
    Then the emitted project contains its source and runtime
    When I build and run the emitted project
    Then stdout, stderr, and exit status match CRuby

  Scenario: Count with while and until using guarded integer ranges
    Given the Ruby source is:
      """
      count = 0
      result = while count < 1000
        count += 1
      end
      puts count
      puts result
      until count <= 997
        count -= 1
      end
      puts count
      puts count + 1
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Read until EOF and preserve condition assignments
    Given the Ruby source is:
      """
      line = "before"
      result = while (line = gets)
        puts line&.chomp
      end
      puts line
      puts result
      """
    And standard input is:
      """
      Ada
      Zoë
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: An empty input executes no loop body
    Given the Ruby source is:
      """
      value = "before"
      while gets
        value = "body"
      end
      puts value
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Break returns a value and next evaluates its value before skipping
    Given the Ruby source is:
      """
      count = 0
      result = while count < 5
        count += 1
        next puts("skip") if count == 2
        break "done:#{count}" if count == 3
        puts count
      end
      puts result
      puts count
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Nested exits target the innermost loop
    Given the Ruby source is:
      """
      outer = 0
      while outer < 3
        outer += 1
        inner = 0
        result = until inner >= 2
          inner += 1
          next if inner == 1
          break "inner"
        end
        puts "#{outer}:#{inner}:#{result}"
        next
        puts "unreachable"
      end
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Modifier loops test before the first iteration
    Given the Ruby source is:
      """
      puts "never" while false
      puts "never" until true
      count = 0
      count += 1 while count < 3
      puts count
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Begin modifier loops run once before testing even after next
    Given the Ruby source is:
      """
      count = 0
      begin
        count += 1
        puts count
        next puts("next")
        puts "unreachable"
      end while false
      begin
        puts "once"
      end until true
      puts count
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Zero and empty strings remain truthy loop conditions
    Given the Ruby source is:
      """
      puts(while 0
        break "zero"
      end)
      puts(while ""
        break "empty"
      end)
      puts(until nil
        break "nil"
      end)
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Post-test counters recheck the guard after next and preserve the first iteration
    Given the Ruby source is:
      """
      count = 0
      begin
        count += 1
        next
      end while count < 1000
      puts count
      count = 5
      begin
        count += 1
      end while count < 3
      puts count
      begin
        count -= 1
        next
      end until count <= 0
      puts count
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Compound assignment captures the old receiver before its argument writes
    Given the Ruby source is:
      """
      count = 1
      puts(count += (count = 2))
      puts count
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: A break can return an existing object without losing its identity
    Given the Ruby source is:
      """
      class Cell
        def store(value)
          @value = value
        end
        def text
          @value
        end
      end
      cell = Cell.new
      returned = while true
        break cell
      end
      returned.store("Ada")
      puts cell.text
      puts returned == cell
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: A method return from the condition exits before the loop body
    Given the Ruby source is:
      """
      class Reader
        def read
          while (if gets; return "returned"; end)
            puts "unreachable"
          end
          "eof"
        end
      end
      puts Reader.new.read
      """
    And standard input is:
      """
      line
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Loop-carried fields retain aliases and method-local return targets
    Given the Ruby source is:
      """
      class Counter
        def initialize
          @count = 0
        end
        def run
          alias_self = self
          while @count < 3
            @count += 1
            puts alias_self.value
          end
          @count
        end
        def value
          @count
        end
        def read
          while gets
            return "returned"
          end
          "eof"
        end
      end
      counter = Counter.new
      puts counter.run
      puts counter.value
      puts counter.read
      """
    And standard input is:
      """
      line
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Ignore unreachable writes and exits after break
    Given the Ruby source is:
      """
      class Cell
        def initialize
          @value = "Ada"
        end
        def run
          while true
            break @value
            @value = 42
            break 42
          end
          @value&.chomp
        end
      end
      puts Cell.new.run
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Do not merge state from a body with a false literal condition
    Given the Ruby source is:
      """
      value = "Ada"
      while false
        value = 42
      end
      puts value&.chomp
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Break in an argument prevents later evaluation
    Given the Ruby source is:
      """
      puts(while true
        puts(if true
          break "done"
        else
          "unused"
        end)
        puts "unreachable"
      end)
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario Outline: Reject unsafe or unsupported loop behavior before emission
    Given the Ruby source is:
      """
      <source>
      """
    When I emit a Rust project
    Then the diagnostic has code "<code>" at line 1
    And no Rust project was created

    Examples:
      | source                                                                                                  | code            |
      | value = 0; while gets; value += 1; end                                                                  | E_INTEGER_RANGE |
      | value = 9223372036854775807; while value <= 9223372036854775807; value += 1; end                          | E_INTEGER_RANGE |
      | value = 0; while value < 2; value = "bad"; end                                                          | E_UNSUPPORTED   |
      | value = "Ada"; while gets; value = 42; puts value&.chomp; end                                           | E_UNSUPPORTED   |
      | class Cell; end; while gets; Cell.new; end                                                              | E_UNSUPPORTED   |
      | while false; missing; end                                                                              | E_UNSUPPORTED   |
      | while true; break; missing; end                                                                        | E_UNSUPPORTED   |
      | while true; break 1, 2; end                                                                            | E_UNSUPPORTED   |
      | while true; next 1, 2; end                                                                             | E_UNSUPPORTED   |
      | while gets; redo; end                                                                                  | E_UNSUPPORTED   |
      | while (if gets; break; end); end                                                                       | E_UNSUPPORTED   |
      | begin; puts 1; rescue; puts 2; end while false                                                          | E_UNSUPPORTED   |

  Scenario: Recheck a method's field types on later iterations
    Given the Ruby source is:
      """
      class Cell
        def initialize
          @value = "Ada"
        end
        def change
          puts @value&.chomp
          @value = 42
        end
      end
      cell = Cell.new
      while gets
        cell.change
      end
      """
    When I emit a Rust project
    Then the diagnostic has code "E_UNSUPPORTED" at line 6
    And no Rust project was created
