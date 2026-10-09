# language: en
Feature: Practical collections with bounded shapes and allocation
  Scenario Outline: Execute the former finite allocation and count boundaries unchanged
    Given the Ruby source is:
      """
      <source>
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

    Examples:
      | source                                                             |
      | values = { "name" => 1 }                                           |
      | [1].each { [] }                                                    |
      | [1].map { {} }                                                     |
      | class Cell; end; [1].each { Cell.new }                              |
      | values = [1]; values.each { values.map { puts 1 } }                 |
      | count = if gets; 1; else; 2; end; count.times { puts 1 }             |
      | class Choice; def value(values = []); values.length; end; end; choice = Choice.new; 1.times { choice.value } |

  Scenario: Literal String keys replace by content and retain insertion order
    Given the Ruby source is:
      """
      values = { "name" => "Ada", :name => "symbol", "name" => "Grace", 1 => "one" }
      alias_values = values
      alias_values["name"] = "Zoë"
      puts values.length
      puts values["name"]
      puts values[:name]
      puts values.keys[0]
      puts values.values[0]
      puts values.key?("missing")
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario Outline: Runtime String lookup searches only String keys
    Given the Ruby source is:
      """
      labels = { "ok" => "accepted", "error" => "rejected", :ok => 7, 1 => true }
      key = "#{gets&.chomp}"
      puts labels[key] if key == "ok"
      puts labels["" + "error"]
      puts labels.key?("" + "missing")
      """
    And standard input is:
      """
      <input>
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

    Examples:
      | input |
      | ok    |
      | other |

  Scenario: Hash String keys are frozen copies while their dup remains mutable
    Given the Ruby source is:
      """
      values = { "a\nZoë" => 1 }
      key = values.keys[0]
      begin
        key << "!"
      rescue FrozenError => error
        puts error.message
      end
      copy = key.dup
      copy << "!"
      puts key
      puts copy
      puts values["a\nZoë"]
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario Outline: Traverse optional scalar slots and join captured assignments
    Given the Ruby source is:
      """
      values = [2]
      alias_values = values
      if gets&.chomp == "yes"
        alias_values.push(3)
        nil
      end
      total = 0
      returned = values.each { |value| total += value }
      puts total
      puts returned.length
      puts values[-1]
      mapped = values.map { |value| value * 2 }
      puts mapped.length
      puts mapped[0]
      puts mapped[-1]
      """
    And standard input is:
      """
      <input>
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

    Examples:
      | input |
      | yes   |
      |       |

  Scenario Outline: Bounded times uses the runtime count and preserves next
    Given the Ruby source is:
      """
      count = if gets&.chomp == "yes"; 3; else; 1; end
      total = 0
      returned = count.times do |index|
        next if index == 1
        total += index
      end
      puts returned
      puts total
      """
    And standard input is:
      """
      <input>
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

    Examples:
      | input |
      | yes   |
      |       |

  Scenario: Finite iterators allocate distinct objects arrays and hashes with aliases
    Given the Ruby source is:
      """
      class Line
        attr_accessor :quantity
        def initialize(quantity)
          @quantity = quantity
        end
      end
      rows = []
      3.times do |index|
        line = Line.new(index + 1)
        rows.push({ "line" => line, "tags" => ["new"] })
      end
      rows[0]["line"].quantity = 7
      rows[0]["tags"][0] << "!"
      rows.each do |row|
        puts row["line"].quantity
        puts row["tags"][0]
      end
      mapped = rows.map { |row| [row["line"].quantity] }
      puts mapped[0][0]
      puts mapped[1][0]
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario Outline: Optional iterations preserve break return and ensure
    Given the Ruby source is:
      """
      class Reporter
        def run(values)
          total = 0
          values.each do |value|
            begin
              total += value
              break values if value == 3
            ensure
              puts "visited:#{value}"
            end
          end
          puts total
          return total if total == 5
          total
        end
      end
      values = [2]
      if gets&.chomp == "yes"
        values.push(3)
        nil
      end
      puts Reporter.new.run(values)
      """
    And standard input is:
      """
      <input>
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

    Examples:
      | input |
      | yes   |
      |       |

  Scenario Outline: Keep unbounded allocation and unknown shapes as located diagnostics
    Given the Ruby source is:
      """
      <source>
      """
    When I emit a Rust project
    Then the diagnostic has code "E_UNSUPPORTED" at line 1
    And no Rust project was created

    Examples:
      | source                                                           |
      | values = {}; key = "name"; values[key] = 1                        |
      | values = {}; values["a" + "b"] = 1                                |
      | while gets; []; end                                              |
      | while gets; 1.times { {} }; end                                   |
      | class Cell; end; 1.times { while gets; Cell.new; end }             |
      | values = [1]; values.each { values.push(2) }                      |
      | values = []; values.push(1) if gets; values.each { values << 2 }   |
      | count = if gets; 1001; else; 1; end; count.times { puts 1 }        |

  Scenario Outline: Order processing retains independent line items and optional totals
    Given I use the example "workloads/order_batch.rb"
    And standard input is:
      """
      <input>
      """
    When I emit a Rust project
    Then the emitted project contains its source and runtime
    When I build and run the emitted project
    Then stdout, stderr, and exit status match CRuby
    And CRuby prints the reference output:
      """
      tea:3:packed!
      coffee:2:packed
      lines:<lines> total:<total> cents
      """

    Examples:
      | input | lines | total |
      | gift  | 3     | 3350  |
      | none  | 2     | 3150  |

  Scenario Outline: Bounded log processing ignores missing and unknown status lines
    Given I use the example "workloads/log_batch.rb"
    And standard input is:
      """
      <input>
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby
    And CRuby prints the reference output:
      """
      <output>
      """

    Examples:
      | input              | output                                                               |
      | ok\nerror\nok      | accepted\nrejected\naccepted\nprocessed:3 successful:2 failed:1       |
      | error\nunknown\nok | rejected\naccepted\nprocessed:2 successful:1 failed:1                 |
      | unknown            | processed:0 successful:0 failed:0                                     |

  Scenario: Empty bounded log processing also matches CRuby
    Given I use the example "workloads/log_batch.rb"
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby
    And CRuby prints the reference output:
      """
      processed:0 successful:0 failed:0
      """

  Scenario: Bound fresh arena allocations across finite iterator bodies
    Given the Ruby source is:
      """
      1000.times { [[], [], [], [], [], [], [], [], [], []]; nil }
      """
    When I emit a Rust project
    Then the diagnostic has code "E_UNSUPPORTED" at line 1
    And no Rust project was created

  Scenario: Uncaught frozen-key mutation reports the Ruby failure and location
    Given the Ruby source is:
      """
      values = { "name" => 1 }
      values.keys[0] << "!"
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario Outline: Optional traversal preserves failure paths and cleanup
    Given the Ruby source is:
      """
      values = [2]
      if gets&.chomp == "zero"
        values.push(0)
        nil
      end
      values.each do |value|
        begin
          puts 10 / value
        ensure
          puts "cleanup"
        end
      end
      """
    And standard input is:
      """
      <input>
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

    Examples:
      | input |
      | zero  |
      |       |

  Scenario Outline: Function specialization retains the runtime slot guards
    Given the Ruby source is:
      """
      class Counter
        def count(values)
          count = 0
          values.each { count += 1 }
          count
        end
      end
      counter = Counter.new
      fixed = [1, 2]
      variable = [1]
      if gets&.chomp == "yes"
        variable.push(2)
        nil
      end
      puts counter.count(fixed)
      puts counter.count(variable)
      """
    And standard input is:
      """
      <input>
      """
    When I emit a Rust project
    Then the emitted Rust defines 2 receiver functions
    When I build and run the emitted project
    Then stdout, stderr, and exit status match CRuby

    Examples:
      | input |
      | yes   |
      |       |

  Scenario: String keys survive keyword-rest copies without becoming symbols
    Given the Ruby source is:
      """
      class Store
        def copy(**values)
          values
        end
      end
      values = Store.new.copy(**{ "name" => "Ada", name: "symbol" })
      puts values["name"]
      puts values[:name]
      puts values.keys[0]
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Fresh next return and omitted-default results keep independent storage
    Given the Ruby source is:
      """
      class Factory
        def value(values = [])
          values.push(7)
          values
        end
        def returned
          1.times { return [9] }
        end
      end
      factory = Factory.new
      defaults = [1, 2].map { factory.value }
      defaults[0].push(8)
      puts defaults[0].length
      puts defaults[1].length
      mapped = [1, 2].map { |value| next [value] }
      mapped[0][0] = 3
      puts mapped[0][0]
      puts mapped[1][0]
      puts factory.returned[0]
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby
