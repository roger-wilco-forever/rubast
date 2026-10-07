# language: en
Feature: Call methods on the current instance
  Scenario: Call later-defined helpers through self and implicit receivers
    Given the Ruby source is:
      """
      class Greeter
        def initialize(name)
          store(name)
        end
        def greet
          puts self.message
          message
        end
        def message
          "Hello, #{name}!"
        end
        def name
          @name
        end
        def store(name)
          @name = name
        end
      end
      greeter = Greeter.new("Zoë")
      puts greeter.greet
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Keep nested method locals isolated and preserve scalar return types
    Given the Ruby source is:
      """
      class Cleaner
        def clean(value)
          local = "outer"
          result = self.echo(value)&.chomp
          puts local
          puts result
          echo(42)
        end
        def echo(value)
          local = "inner"
          puts local
          value
        end
      end
      local = "caller"
      puts Cleaner.new.clean("Ada\n")
      puts local
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Capture nested arguments before the next argument changes a field
    Given the Ruby source is:
      """
      class Cell
        def initialize(value)
          @value = value
        end
        def change
          first(value, self.store(42))
        end
        def first(first, second)
          first&.chomp
        end
        def value
          @value
        end
        def store(value)
          @value = value
        end
      end
      cell = Cell.new("Ada\n")
      puts cell.change
      puts cell.value
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Evaluate nested input arguments once in order
    Given the Ruby source is:
      """
      class Reader
        def read
          self.join(line, line)
        end
        def line
          gets&.chomp
        end
        def join(first, second)
          "#{second}:#{first}:#{first}"
        end
      end
      puts Reader.new.read
      """
    And standard input is:
      """
      Ada
      Zoë
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Preserve the current receiver when self is assigned to a local
    Given the Ruby source is:
      """
      class Cell
        def change(value)
          object = self
          object.store(value)
          self.value
        end
        def store(value)
          @value = value
        end
        def value
          @value
        end
      end
      first = Cell.new
      second = Cell.new
      puts first.change("Ada")
      puts second.change("Zoë")
      puts first.value
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Restore self after calls on another class
    Given the Ruby source is:
      """
      class Echo
        def value(input)
          input
        end
      end
      class Name
        def initialize(name)
          @name = name
        end
        def text
          other = Echo.new
          puts other.value("other")
          self.name
        end
        def name
          @name
        end
      end
      puts Name.new("Ada").text
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Resolve implicit user methods before built-in gets and puts
    Given the Ruby source is:
      """
      class Named
        def value
          puts(gets)
        end
        def gets
          "Ada"
        end
        def puts(value)
          "custom:#{value}"
        end
      end
      puts Named.new.value
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Reuse generated receiver functions across argument and field types
    Given the Ruby source is:
      """
      class Cell
        def store(value)
          @value = value
        end
        def value
          @value
        end
      end
      cell = Cell.new
      cell.store("Ada")
      puts cell.value
      cell.store(42)
      puts cell.value
      """
    When I emit a Rust project
    Then the emitted project contains its source and runtime
    And the emitted Rust defines 2 receiver functions
    When I build and run the emitted project
    Then stdout, stderr, and exit status match CRuby

  Scenario: Reject invalid nested operations using the actual argument type
    Given the Ruby source is:
      """
      class Cleaner
        def clean(value)
          self.chomp(value)
        end
        def chomp(value)
          value&.chomp
        end
      end
      puts Cleaner.new.clean(42)
      """
    When I run Rubast
    Then the diagnostic has code "E_UNSUPPORTED" at line 6

  Scenario: Report the Ruby location of an indirect recursive call
    Given the Ruby source is:
      """
      class Bad
        def first
          self.second
        end
        def second
          first
        end
      end
      """
    When I emit a Rust project
    Then the diagnostic has code "E_UNSUPPORTED" at line 6
    And no Rust project was created

  Scenario Outline: Diagnose unsupported lookup and recursive methods before emission
    Given the Ruby source is:
      """
      <source>
      """
    When I emit a Rust project
    Then the diagnostic has code "E_UNSUPPORTED" at line 1
    And no Rust project was created

    Examples:
      | source                                                                                                     |
      | class Bad; def value; missing; end; end                                                                    |
      | class Bad; def value; self.missing; end; end                                                               |
      | class Bad; def value; self.helper; end; def helper(input); input; end; end                                 |
      | class Bad; def value; value; end; end                                                                      |
      | class Bad; def first; self.second; end; def second; first; end; end                                        |
      | class Bad; def initialize; Bad.new; end; end                                                               |
      | class Bad; def initialize; end; def value; initialize; end; end                                            |
      | class Bad; def initialize; end; def value; self.initialize; end; end                                       |
      | class Bad; def value; self; end; end                                                                       |
      | class Bad; def value; @value = self; end; end                                                              |
      | class Bad; def value; 42; end; end; puts self.value                                                        |
      | class Bad; def value=(input); 42; end; def change; "#{self.value = "Ada"}"; end; end; puts Bad.new.change  |
      | class Bad; def []=(index, input); 42; end; def change; "#{self[0] = "Ada"}"; end; end; puts Bad.new.change |
