# language: en
Feature: Preserve constructor behavior and instance state
  Scenario: Construct a greeting object and ignore the initializer result
    Given the Ruby source is:
      """
      class Greeter
        def initialize(name)
          puts "initializing:#{name}"
          @name = name
          42
        end
        def greet
          puts "Hello, #{@name}!"
        end
      end
      Greeter.new("Zoë").greet
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Keep instances independent and preserve mutations through aliases
    Given the Ruby source is:
      """
      class Name
        def initialize(name)
          @name = name
        end
        def rename(name)
          @name = name
        end
        def name
          @name
        end
      end
      first = Name.new("Ada")
      second = Name.new("Zoë")
      alias_first = first
      puts alias_first.rename("Grace")
      puts first.name
      puts second.name
      first = second
      first.rename("Lin")
      puts second.name
      puts alias_first.name
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Read unset fields as nil and replace their value types
    Given the Ruby source is:
      """
      class Cell
        def value
          @value
        end
        def store(value)
          @value = value
        end
        def clean
          @value&.chomp
        end
      end
      cell = Cell.new
      puts "unset:#{cell.value}"
      puts "clean:#{cell.clean}"
      puts cell.store(42)
      puts cell.value
      cell.store("Ada\n")
      puts cell.clean
      cell.store(nil)
      puts "nil:#{cell.value}"
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Evaluate constructor arguments once in order
    Given the Ruby source is:
      """
      class Pair
        def initialize(first, second)
          puts "constructing"
          @first = first
          @second = second
        end
        def text
          "#{@second}:#{@first}:#{@first}"
        end
      end
      puts Pair.new(gets&.chomp, gets&.chomp).text
      """
    And standard input is:
      """
      Ada
      Zoë
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Capture field reads before later mutation in interpolation
    Given the Ruby source is:
      """
      class Name
        def initialize(name)
          @name = name
        end
        def change
          "#{@name}:#{@name = "changed"}:#{@name}"
        end
      end
      object = Name.new("original")
      puts object.change
      puts object.change
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Capture method results before a later argument mutates the object
    Given the Ruby source is:
      """
      class Cell
        def initialize(value)
          @value = value
        end
        def value
          @value
        end
        def store(value)
          @value = value
        end
      end
      class Cleaner
        def first(first, second)
          first&.chomp
        end
      end
      cell = Cell.new("Ada\n")
      puts Cleaner.new.first(cell.value, cell.store(42))
      puts cell.value
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Restore receiver state after a nested constructor and method call
    Given the Ruby source is:
      """
      class Leaf
        def initialize(value)
          @value = value
        end
        def value
          @value
        end
      end
      class Box
        def initialize(value)
          @before = value
          leaf = Leaf.new("inner")
          @after = leaf.value
        end
        def text
          "#{@before}:#{@after}"
        end
      end
      puts Box.new("outer").text
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Capture the receiver before arguments reassign its local
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
      alias_cell = cell
      puts cell.store(cell = "changed")
      puts alias_cell.value
      puts cell
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Reject unsupported operations after an alias changes a field type
    Given the Ruby source is:
      """
      class Cell
        def store(value)
          @value = value
        end
        def clean
          @value&.chomp
        end
      end
      cell = Cell.new
      alias_cell = cell
      alias_cell.store(42)
      puts cell.clean
      """
    When I run Rubast
    Then the diagnostic has code "E_UNSUPPORTED" at line 6

  Scenario Outline: Reject unsupported object semantics
    Given the Ruby source is:
      """
      <source>
      """
    When I run Rubast
    Then the diagnostic has code "E_UNSUPPORTED" at line 1

    Examples:
      | source                                                                                    |
      | class Cell; def initialize; end; end; Cell.new.initialize                                 |
      | class Cell; def value; 42; end; end; puts @value                                          |
      | @value = 42                                                                               |

  Scenario Outline: Accepted extended argument fixtures preserve Ruby execution
    Given the Ruby source is:
      """
      <source>
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

    Examples:
      | source |
      | class Cell; def initialize(value); @value = value; end; end; Cell.new |
      | class Cell; def initialize; end; end; Cell.new(42) |
