# language: en
Feature: Share array storage and mutable UTF-8 strings
  Scenario: Array literals evaluate elements once in order
    Given the Ruby source is:
      """
      first = "before"
      values = [first, (first = "after"), gets&.chomp, gets&.chomp]
      puts values.length
      puts values[0]
      puts values[1]
      puts values[2]
      puts values[3]
      """
    And standard input is:
      """
      Ada
      Zoë
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Read negative and out-of-range indexes
    Given the Ruby source is:
      """
      values = [7, "Ada", true]
      puts values[-1]
      puts values[-3]
      puts values[-4]
      puts values[3]
      puts values[9223372036854775807]
      puts values[-9223372036854775808]
      puts [].length
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Array aliases share indexed writes and pushes
    Given the Ruby source is:
      """
      values = ["Ada"]
      alias_values = values
      puts(alias_values[0] = "Zoë")
      values.push(42, nil)
      alias_values << true
      puts values[0]
      puts alias_values[1]
      puts values[-1]
      puts values.length
      puts values.push.length
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Positive writes extend with nil and negative writes replace an existing slot
    Given the Ruby source is:
      """
      values = [1]
      puts(values[3] = "Ada")
      puts values.length
      puts values[1]
      puts values[2]
      puts(values[-1] = "Zoë")
      puts values[3]
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Resolve a negative write index after evaluating the right operand
    Given the Ruby source is:
      """
      values = ["old"]
      puts(values[-1] = (values.push("added"); "new"))
      puts values[0]
      puts values[1]
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Capture push arguments before a later argument replaces a slot
    Given the Ruby source is:
      """
      values = ["Ada"]
      values.push(values[0], (values[0] = 42))
      puts values[0]
      puts values[1]
      puts values[2]
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Array arguments and fields preserve shared object references
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
      class Box
        def initialize(values)
          @values = values
        end
        def change(value)
          @values[0].store(value)
          @values
        end
      end
      cell = Cell.new
      values = [cell]
      returned = Box.new(values).change("Ada")
      returned[0].store("Zoë")
      puts cell.text
      puts values[0].text
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Nested arrays and cycles retain mutations without recursive ownership
    Given the Ruby source is:
      """
      values = []
      values << values
      values[0][0].push("Ada")
      puts values.length
      puts values[0][-1]
      values[1] = "Zoë"
      puts values[0][1]
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Dynamic reads join scalar element types and include absent slots
    Given the Ruby source is:
      """
      values = ["Ada", 42]
      index = if gets
        0
      else
        2
      end
      puts values[index]
      """
    And standard input is:
      """
      line
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Mutate a fixed array slot across bounded loop iterations
    Given the Ruby source is:
      """
      values = [0]
      count = 0
      while count < 3
        count += 1
        values[0] = count
      end
      puts values[0]
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Array branch writes and early method exits join element types
    Given the Ruby source is:
      """
      class Writer
        def write(values)
          if gets
            values[0] = "Ada"
            return values
          end
          values[0] = 42
          values
        end
      end
      values = [nil]
      Writer.new.write(values)
      puts values[0]
      """
    And standard input is:
      """
      line
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Concatenation creates a new string while append and replace share aliases
    Given the Ruby source is:
      """
      text = "Zoë"
      alias_text = text
      combined = text + "!"
      puts combined
      puts text
      returned = text << "!"
      returned.concat(returned)
      puts alias_text
      text.replace("Ada")
      puts returned
      alias_text.clear
      puts text
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Count UTF-8 characters and bytes separately
    Given the Ruby source is:
      """
      text = "Zoë"
      puts text.length
      puts text.bytesize
      text << "🙂"
      puts text.length
      puts text.bytesize
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Chomp and dup return independent mutable strings from a frozen literal
    Given the Ruby source is:
      """
      # frozen_string_literal: true
      text = "Ada\n"
      first = text&.chomp
      second = text.chomp
      duplicate = text.dup
      first << "!"
      second.replace("Zoë")
      duplicate.chomp!
      duplicate << "?"
      puts text
      puts first
      puts second
      puts duplicate
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Chomp bang returns nil when unchanged and the original string when changed
    Given the Ruby source is:
      """
      text = "Ada\r\n"
      alias_text = text
      result = text.chomp!
      text << "!"
      puts result
      puts alias_text
      puts text.chomp!
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Arrays preserve mutable string aliases and frozen-element metadata
    Given the Ruby source is:
      """
      text = "Ada"
      values = [text]
      values[0] << "!"
      puts text
      text.replace("Zoë")
      puts values[0]
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Compound string concatenation replaces the local without mutating its old alias
    Given the Ruby source is:
      """
      # frozen_string_literal: true
      text = "Ada"
      old = text
      text += "!"
      text << "?"
      puts old
      puts text
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Specialize a shared method for integer and string addition
    Given the Ruby source is:
      """
      class Doubler
        def twice(value)
          value + value
        end
      end
      doubler = Doubler.new
      puts doubler.twice(7)
      puts doubler.twice("Ada")
      """
    When I emit a Rust project
    Then the emitted project contains its source and runtime
    And the emitted Rust defines 2 receiver functions
    When I build and run the emitted project
    Then stdout, stderr, and exit status match CRuby

  Scenario Outline: Reject unsupported collection operations before emission
    Given the Ruby source is:
      """
      <source>
      """
    When I emit a Rust project
    Then the diagnostic has code "E_UNSUPPORTED" at line 1
    And no Rust project was created

    Examples:
      | source                                                                                              |
      | values = []; values[-1] = 1                                                                        |
      | values = []; values[10000] = 1                                                                     |
      | values = []; values["key"]                                                                        |
      | values = [1]; values[0, 1]                                                                         |
      | values = []; puts values                                                                          |
      | values = []; puts "#{values}"                                                                    |
      | values = [1]; puts values == [1]                                                                   |
      | values = [1]; values.each { puts 1 }                                                               |
      | values = [1]; values[0] += 1                                                                       |
      | class Cell; end; values = [Cell.new, Cell.new]; index = if gets; 0; else; 1; end; values[index]       |
      | values = []; while gets; values.push(1); end                                                       |
      | while gets; []; end                                                                               |
      | text = "Ada"; text << 65                                                                          |
      | text = "Ada"; text.replace(42)                                                                    |
      | text = "Ada"; text[0] = "Z"                                                                       |
      | text = "Ada"; text + nil                                                                          |

  Scenario: Reject unsupported array calls even when an argument returns
    Given the Ruby source is:
      """
      class Example
        def go
          [].missing(begin; return 1; 42; end)
        end
      end
      Example.new.go
      """
    When I emit a Rust project
    Then the diagnostic has code "E_UNSUPPORTED" at line 3
    And no Rust project was created

  Scenario Outline: Reject mutations of known frozen literals before emission
    Given the Ruby source is:
      """
      # frozen_string_literal: true
      text = "Ada"
      <operation>
      """
    When I emit a Rust project
    Then the diagnostic has code "E_UNSUPPORTED" at line 3
    And no Rust project was created

    Examples:
      | operation               |
      | text << "!"            |
      | text.concat("!")       |
      | text.replace("Zoë")    |
      | text.clear              |
      | text.chomp!             |
      | [text][0] << "!"        |

  Scenario: Retain a standalone project with shared arrays and strings
    Given I use the example "shared_collections.rb"
    When I emit a Rust project
    Then the emitted project contains its source and runtime
    When I build and run the emitted project
    Then stdout, stderr, and exit status match CRuby
