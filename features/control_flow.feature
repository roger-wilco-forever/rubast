# language: en
Feature: Preserve conditional values and method returns
  Scenario: Use Ruby truthiness with if, unless, elsif, and modifiers
    Given the Ruby source is:
      """
      if 0
        puts "zero is truthy"
      end
      if ""
        puts "empty string is truthy"
      end
      if false
        puts "wrong"
      elsif nil
        puts "wrong again"
      else
        puts "else"
      end
      unless false
        puts "unless"
      else
        puts "wrong unless"
      end
      puts "modifier" if true
      puts "unless modifier" unless nil
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Evaluate only the selected branch and preserve its expression value
    Given the Ruby source is:
      """
      value = if gets&.chomp == "Ada"
        puts "selected"
        gets&.chomp
      else
        puts "not selected"
        gets&.chomp
      end
      puts value
      puts gets&.chomp
      missing = if false
        "wrong"
      end
      puts "missing:#{missing}"
      """
    And standard input is:
      """
      Ada
      Zoë
      final
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Keep conditional assignments visible and untaken locals nil
    Given the Ruby source is:
      """
      value = "before"
      if false
        value = "wrong"
        hidden = 42
      else
        value = "after"
      end
      puts value
      puts "hidden:#{hidden}"
      value = if true
        3
      else
        5
      end
      puts value * 2
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Merge scalar field changes without losing object aliases
    Given the Ruby source is:
      """
      class Cell
        def initialize(value)
          @value = value
        end
        def choose(flag)
          if flag
            @value = "Ada\n"
          else
            @value = nil
          end
          @value&.chomp
        end
        def value
          @value
        end
      end
      cell = Cell.new("before")
      alias_cell = cell
      puts cell.choose(true)
      puts "#{alias_cell.value}"
      puts cell.choose(false)
      puts "#{alias_cell.value}"
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Evaluate a condition once and preserve earlier reads before conditional writes
    Given the Ruby source is:
      """
      value = "before"
      puts "#{value}:#{if gets&.chomp == "yes"; value = "after"; else; value = "other"; end}:#{value}"
      puts gets&.chomp
      """
    And standard input is:
      """
      yes
      final
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Return from the current method and preserve the caller's execution
    Given the Ruby source is:
      """
      class Choice
        def pick(flag)
          puts "start"
          if flag
            return self.echo("early")
          end
          puts "late"
          "ordinary"
        end
        def echo(value)
          return value
          puts "unreachable helper"
        end
        def empty
          return
          puts "unreachable empty"
        end
      end
      choice = Choice.new
      puts choice.pick(true)
      puts choice.pick(false)
      puts "empty:#{choice.empty}"
      puts "caller continues"
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Keep return-valued branches inside assignment and arguments
    Given the Ruby source is:
      """
      class Choice
        def pick(flag)
          value = if flag
            return 7
          else
            3
          end
          self.echo(value + 1)
        end
        def echo(value)
          value
        end
        def argument(flag)
          self.echo(if flag; return "early argument"; else; "ordinary argument"; end)
        end
      end
      choice = Choice.new
      puts choice.pick(true)
      puts choice.pick(false)
      puts choice.argument(true)
      puts choice.argument(false)
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Preserve field effects before returns and ignore later writes
    Given the Ruby source is:
      """
      class Cell
        def initialize
          @value = "before"
          return 42
          @value = false
        end
        def change(flag)
          if flag
            @value = "early"
            return @value
          end
          @value = "late"
          @value
        end
        def value
          @value&.chomp
        end
      end
      cell = Cell.new
      puts cell.value
      puts cell.change(true)
      puts cell.value
      puts cell.change(false)
      puts cell.value
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Merge all possible return values for bounded caller arithmetic
    Given the Ruby source is:
      """
      class Choice
        def pick(flag)
          if flag
            return -3
          else
            return 5
          end
          42
        end
      end
      choice = Choice.new
      puts choice.pick(true) * 2
      puts choice.pick(false) + 1
      """
    When I emit a Rust project
    Then the emitted project contains its source and runtime
    When I build and run the emitted project
    Then stdout, stderr, and exit status match CRuby

  Scenario: Return from argument and operand evaluation before later state changes
    Given the Ruby source is:
      """
      class Cell
        def initialize
          @value = "before"
        end
        def argument(flag)
          self.store(if flag; return 7; else; "ordinary"; end)
          @value = "after argument"
        end
        def operand(flag)
          3 + (if flag; return 8; else; 4; end)
          @value = "after operand"
        end
        def store(value)
          @value = value
        end
        def value
          @value&.chomp
        end
      end
      cell = Cell.new
      puts cell.argument(true)
      puts cell.value
      puts cell.argument(false)
      puts cell.value
      puts cell.operand(true)
      puts cell.value
      puts cell.operand(false)
      puts cell.value
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Store boolean fields and use them as conditions
    Given the Ruby source is:
      """
      class Flag
        def initialize(value)
          @enabled = value
        end
        def choose
          if @enabled
            "enabled"
          else
            "disabled"
          end
        end
        def value
          @enabled == true
        end
      end
      puts Flag.new(true).choose
      puts Flag.new(false).choose
      puts Flag.new(false).value
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Reject an operation if a possible branch leaves an invalid field type
    Given the Ruby source is:
      """
      class Cell
        def choose(flag)
          if flag
            @value = "Ada"
          else
            @value = 42
          end
          @value&.chomp
        end
      end
      puts Cell.new.choose(true)
      """
    When I emit a Rust project
    Then the diagnostic has code "E_UNSUPPORTED" at line 8
    And no Rust project was created

  Scenario Outline: Reject unsupported flow and unsafe joins before emission
    Given the Ruby source is:
      """
      <source>
      """
    When I emit a Rust project
    Then the diagnostic has code "<code>" at line 1
    And no Rust project was created

    Examples:
      | source                                                                              | code            |
      | return 42                                                                           | E_UNSUPPORTED   |
      | class Choice; def pick; return 1, 2; end; end                                       | E_UNSUPPORTED   |
      | class Choice; def pick; return 42; unknown; end; end                                | E_UNSUPPORTED   |
      | if false; unknown; else; puts 42; end                                               | E_UNSUPPORTED   |
      | value = if true; "Ada"; else; 42; end; puts value&.chomp                            | E_UNSUPPORTED   |
      | value = if true; 1; else; 0; end; puts 42 / value                                   | E_UNSUPPORTED   |
      | value = if true; 9223372036854775807; else; 0; end; puts value + 1                  | E_INTEGER_RANGE |
      | class Cell; def value; 42; end; end; cell = Cell.new; if true; cell = Cell.new; end | E_UNSUPPORTED   |
      | if true; puts 42; else; puts 2.5; end                                               | E_UNSUPPORTED   |
      | class Cell; def value; 42; end; end; if Cell.new; puts 42; end                      | E_UNSUPPORTED   |
