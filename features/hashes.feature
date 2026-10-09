# language: en
Feature: Symbols and ordered shared hashes with immutable built-in keys
  Scenario: Symbols preserve names, equality, truthiness and scalar returns
    Given the Ruby source is:
      """
      class Echo
        def value(input)
          input
        end
      end
      name = Echo.new.value(:"Zoë")
      puts name
      puts "name:#{name}"
      puts name == :"Zoë"
      puts name != :other
      puts name == "Zoë"
      puts !name
      if name
        puts "truthy"
      end
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Distinguish missing keys from stored nil and replace without reordering
    Given the Ruby source is:
      """
      values = { first: nil, second: "Ada", 1 => "one", -1 => "minus" }
      alias_values = values
      puts values.key?(:first)
      puts values.key?(:missing)
      puts values[:first]
      puts values[:missing]
      alias_values[:second] = "Zoë"
      values[:third] = "Grace"
      puts values.length
      keys = values.keys
      puts keys[0]
      puts keys[1]
      puts keys[2]
      puts keys[-1]
      puts values.values[1]
      puts values[-1]
      puts !values
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Literal keys and values execute in order and duplicate replacement retains first position
    Given the Ruby source is:
      """
      class Trace
        def key(value)
          puts value
          value
        end
        def value(value)
          puts value
          value
        end
      end
      trace = Trace.new
      values = { trace.key(:a) => trace.value(1), trace.key(:b) => trace.value(2), trace.key(:a) => trace.value(3) }
      puts values.length
      puts values.keys[0]
      puts values.keys[1]
      puts values[:a]
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Capture a write key before its right operand changes the local
    Given the Ruby source is:
      """
      values = {}
      key = :first
      puts(values[key] = (key = :second; "Ada"))
      puts values.key?(:first)
      puts values.key?(:second)
      puts values[key]
      puts values[:first]
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Hash arguments and returns retain nested mutable aliases and cycles
    Given the Ruby source is:
      """
      class Store
        def initialize(data)
          @data = data
        end
        def put(key, value)
          @data[key] = value
          @data
        end
      end
      names = ["Ada"]
      data = { names: names }
      store = Store.new(data)
      alias_data = store.put(:self, data)
      alias_data[:self][:names][0] << "!"
      puts names[0]
      puts data.length
      keys = data.keys
      keys[0] = :changed
      puts data.keys[0]
      copies = data.values
      copies[0].push("Grace")
      puts data[:names][-1]
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario Outline: Branch state retains key presence, value types and possible lengths
    Given the Ruby source is:
      """
      values = { first: nil }
      if gets
        values[:second] = "Ada"
      else
        values[:first] = 7
      end
      puts values.length
      puts values.key?(:first)
      puts values.key?(:second)
      puts values[:first]
      puts values[:second]
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

  Scenario: Mutate a fixed key across bounded loop iterations
    Given the Ruby source is:
      """
      values = { name: "Ada" }
      index = 0
      while index < 3
        values[:name] << "!"
        index += 1
      end
      puts values[:name]
      puts values.length
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Deferred key parameters are validated for each actual call
    Given the Ruby source is:
      """
      class Factory
        def make(key, value)
          { key => value }
        end
      end
      factory = Factory.new
      puts factory.make(:name, "Ada")[:name]
      puts factory.make(7, "seven")[7]
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario Outline: Reject undeclared key types and hash operations before emission
    Given the Ruby source is:
      """
      <source>
      """
    When I emit a Rust project
    Then the diagnostic has code "E_UNSUPPORTED" at line 1
    And no Rust project was created

    Examples:
      | source                                                                             |
      | values = { nil => 1 }                                                              |
      | values = { true => 1 }                                                             |
      | values = {}; values[[]] = 1                                                        |
      | class Key; end; values = { Key.new => 1 }                                           |
      | values = {}; index = if gets; 0; else; 1; end; values[index] = 1                     |
      | values = {}; key = if gets; :a; else; :b; end; values[key]                           |
      | values = {}; values.fetch(:missing)                                                |
      | values = {}; values[:missing] += 1                                                 |
      | values = {}; puts values                                                          |
      | values = {}; puts "#{values}"                                                     |
      | values = {}; puts values == {}                                                    |
      | values = {}; values.each { puts 1 }                                                |
      | values = { **{} }                                                                  |
      | while gets; {}; end                                                               |
      | values = { a: 1 }; while gets; values.keys; end                                    |
      | values = {}; if gets; values[:a] = 1; else; values[:b] = 2; end; values.keys          |
      | values = {}; if gets; values[:a] = 1; values[:b] = 2; else; values[:b] = 2; values[:a] = 1; end; values.values |

  Scenario: Bound the number of tracked hash insertion orders
    Given the Ruby source is:
      """
      values = {}
      if gets; values[:a] = 1; else; values[:b] = 1; end
      if gets; values[:c] = 1; else; values[:d] = 1; end
      if gets; values[:e] = 1; else; values[:f] = 1; end
      if gets; values[:g] = 1; else; values[:h] = 1; end
      if gets; values[:i] = 1; else; values[:j] = 1; end
      if gets; values[:k] = 1; else; values[:l] = 1; end
      puts values.length
      """
    When I emit a Rust project
    Then the diagnostic has code "E_UNSUPPORTED" at line 7
    And no Rust project was created

  Scenario: Retain an independently buildable definition store
    Given I use the example "definition_store.rb"
    When I emit a Rust project
    Then the emitted project contains its source and runtime
    When I build and run the emitted project
    Then stdout, stderr, and exit status match CRuby
