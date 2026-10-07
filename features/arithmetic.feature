# language: en
Feature: Preserve scalar comparisons and bounded integer arithmetic
  Scenario: Print booleans and compare supported scalars
    Given the Ruby source is:
      """
      puts true
      puts false
      puts "#{true}:#{false}"
      puts 1 == 1
      puts 1 != 2
      puts 1 == "1"
      puts nil == false
      puts true == true
      puts "Zoë" == "Zoë"
      puts "Ada" != "Zoë"
      puts 1 < 2
      puts 2 <= 2
      puts 3 > 2
      puts 3 >= 3
      puts !false
      puts !nil
      puts !0
      puts !""
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Evaluate operands once from left to right
    Given the Ruby source is:
      """
      class Number
        def first
          puts "first"
          3
        end
        def second
          puts "second"
          4
        end
      end
      number = Number.new
      puts number.first + number.second
      value = 2
      puts value + (value = 4)
      puts value
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Validate arithmetic using actual method arguments and field values
    Given the Ruby source is:
      """
      class Number
        def initialize(value)
          @value = value
        end
        def add(value)
          @value = @value + value
        end
        def negate
          -@value
        end
      end
      number = Number.new(7)
      puts number.add(3)
      puts number.negate
      puts number.add(-4)
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Preserve user-defined operator lookup
    Given the Ruby source is:
      """
      class Offset
        def +(value)
          value - 1
        end
      end
      puts Offset.new + 7
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Build the number-label example as an independent project
    Given I use the example "number_label.rb"
    When I emit a Rust project
    Then the emitted project contains its source and runtime
    When I build and run the emitted project
    Then stdout, stderr, and exit status match CRuby

  Scenario Outline: Match integer operators and signed boundaries
    Given the Ruby source is:
      """
      puts <expression>
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

    Examples:
      | expression                |
      | 7 + 5                     |
      | 7 - 12                    |
      | -7 * 5                    |
      | 7 / 3                     |
      | -7 / 3                    |
      | 7 / -3                    |
      | -7 / -3                   |
      | 7 % 3                     |
      | -7 % 3                    |
      | 7 % -3                    |
      | -7 % -3                   |
      | 9223372036854775806 + 1   |
      | -9223372036854775807 - 1  |
      | -9223372036854775808 / 1  |
      | -9223372036854775808 % -1 |
      | -(9223372036854775807)    |
      | +(42)                     |

  Scenario Outline: Reject unsupported or unrepresentable arithmetic before emission
    Given the Ruby source is:
      """
      <source>
      """
    When I emit a Rust project
    Then the diagnostic has code "<code>" at line 1
    And no Rust project was created

    Examples:
      | source                                                                        | code            |
      | puts 9223372036854775807 + 1                                                  | E_INTEGER_RANGE |
      | puts -9223372036854775808 - 1                                                 | E_INTEGER_RANGE |
      | puts 9223372036854775807 * 2                                                  | E_INTEGER_RANGE |
      | puts -(-9223372036854775808)                                                  | E_INTEGER_RANGE |
      | puts -9223372036854775808 / -1                                                | E_INTEGER_RANGE |
      | puts 1 / 0                                                                    | E_UNSUPPORTED   |
      | puts 1 % 0                                                                    | E_UNSUPPORTED   |
      | puts "Ada" + "Zoë"                                                            | E_UNSUPPORTED   |
      | puts true + 1                                                                 | E_UNSUPPORTED   |
      | puts nil < 1                                                                  | E_UNSUPPORTED   |
      | puts 2 ** 3                                                                   | E_UNSUPPORTED   |
      | class Number; def add(value); value + 1; end; end; puts Number.new.add("Ada") | E_UNSUPPORTED   |
