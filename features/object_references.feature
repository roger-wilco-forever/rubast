# language: en
Feature: Preserve object references across calls and fields
  Scenario: Build and run the retained cyclic-reference example
    Given I use the example "linked_names.rb"
    When I emit a Rust project
    Then the emitted project contains its source and runtime
    When I build and run the emitted project
    Then stdout, stderr, and exit status match CRuby

  Scenario: Pass and return an object without copying its state
    Given the Ruby source is:
      """
      class Cell
        def initialize(value)
          @value = value
        end
        def store(value)
          @value = value
        end
        def value
          @value
        end
      end
      class Relay
        def change(cell)
          cell.store("Grace")
          cell
        end
      end
      cell = Cell.new("Ada")
      returned = Relay.new.change(cell)
      returned.store("Zoë")
      puts cell.value
      puts returned == cell
      puts returned != Cell.new("Zoë")
      puts !returned
      puts nil == returned
      puts true != returned
      puts returned == 42
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Return self explicitly and skip unreachable field changes
    Given the Ruby source is:
      """
      class Cell
        def change(value)
          @value = value
          return self
          @value = 42
        end
        def clean
          @value&.chomp
        end
      end
      cell = Cell.new
      returned = cell.change("Ada\n")
      puts returned.clean
      puts cell.clean
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Return a newly constructed object through nested methods
    Given the Ruby source is:
      """
      class Name
        def initialize(text)
          @text = text
        end
        def text
          @text
        end
      end
      class Factory
        def make(text)
          build(text)
        end
        def build(text)
          Name.new(text)
        end
      end
      factory = Factory.new
      first = factory.make("Ada")
      second = factory.make("Zoë")
      puts first.text
      puts second.text
      puts first == second
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Share constructor object arguments and ignore object initializer results
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
      class Holder
        def initialize(child)
          @child = child
        end
        def child
          @child
        end
        def replace(child)
          @child = child
        end
      end
      first = Cell.new
      second = Cell.new
      holder = Holder.new(first)
      holder.child.store("Ada")
      old = holder.child
      holder.replace(second).store("Zoë")
      puts first.value
      puts holder.child.value
      old.store("Grace")
      puts first.value
      puts second.value
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Capture an object argument before a later argument replaces the field
    Given the Ruby source is:
      """
      class First
        def text
          "first"
        end
      end
      class Second
        def text
          "second"
        end
      end
      class Holder
        def initialize(child)
          @child = child
        end
        def child
          @child
        end
        def replace(child)
          @child = child
        end
      end
      class Relay
        def first(first, second)
          first
        end
      end
      holder = Holder.new(First.new)
      captured = Relay.new.first(holder.child, holder.replace(Second.new))
      puts captured.text
      puts holder.child.text
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Observe mutations made by a later argument through an earlier object argument
    Given the Ruby source is:
      """
      class Cell
        def store(value)
          @value = value
          self
        end
        def value
          @value
        end
      end
      class Relay
        def read(first, second)
          first.value
        end
      end
      cell = Cell.new
      cell.store("before")
      puts Relay.new.read(cell, cell.store("after"))
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Specialize receiver functions when object arguments change lookup
    Given the Ruby source is:
      """
      class First
        def text
          "first"
        end
      end
      class Second
        def text
          "second"
        end
      end
      class Relay
        def read(child)
          child.text
        end
      end
      relay = Relay.new
      puts relay.read(First.new)
      puts relay.read(Second.new)
      puts relay.read(First.new)
      """
    When I emit a Rust project
    Then the emitted project contains its source and runtime
    And the emitted Rust defines 4 receiver functions
    When I build and run the emitted project
    Then stdout, stderr, and exit status match CRuby

  Scenario: Specialize nested lookup when object fields change class
    Given the Ruby source is:
      """
      class First
        def text
          "first"
        end
      end
      class Second
        def text
          "second"
        end
      end
      class Holder
        def replace(child)
          @child = child
        end
        def read
          helper
        end
        def helper
          @child.text
        end
      end
      holder = Holder.new
      holder.replace(First.new)
      puts holder.read
      holder.replace(Second.new)
      puts holder.read
      holder.replace(First.new)
      puts holder.read
      """
    When I emit a Rust project
    Then the emitted project contains its source and runtime
    And the emitted Rust defines 7 receiver functions
    When I build and run the emitted project
    Then stdout, stderr, and exit status match CRuby

  Scenario: Keep self references and mutual cycles usable
    Given the Ruby source is:
      """
      class Node
        def initialize(text)
          @text = text
          @link = self
        end
        def connect(other)
          @link = other
          self
        end
        def link
          @link
        end
        def rename(text)
          @text = text
        end
        def text
          @text
        end
      end
      first = Node.new("Ada")
      second = Node.new("Zoë")
      puts first.link == first
      first.connect(second)
      second.connect(first)
      first.link.link.rename("Grace")
      puts first.text
      puts first.link.text
      puts first.link.link == first
      puts first.link != first
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Merge nested object mutations across branches and method exits
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
      class Holder
        def initialize(child)
          @child = child
        end
        def change(flag)
          if flag
            @child.store("early\n")
            return @child
          end
          @child.store("late\n")
          @child
        end
      end
      cell = Cell.new
      holder = Holder.new(cell)
      puts holder.change(true).clean
      puts cell.clean
      puts holder.change(false).clean
      puts cell.clean
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Restore mutations through cycles in an untaken branch
    Given the Ruby source is:
      """
      class Node
        def initialize
          @link = self
        end
        def link
          @link
        end
        def store(value)
          @value = value
        end
        def value
          @value
        end
      end
      node = Node.new
      node.store("original")
      if false
        node.link.store("changed")
      end
      puts node.link.value
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Return the same handle from both conditional branches
    Given the Ruby source is:
      """
      class Cell
        def pick(flag)
          return self if flag
          self
        end
      end
      cell = Cell.new
      puts cell.pick(true) == cell
      puts cell.pick(false) == cell
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Prefer a user equality method over built-in identity
    Given the Ruby source is:
      """
      class Cell
        def ==(other)
          "custom"
        end
      end
      puts Cell.new == Cell.new
      puts Cell.new != Cell.new
      puts Cell.new == 42
      puts Cell.new != nil
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Evaluate default inequality receivers and arguments exactly once
    Given the Ruby source is:
      """
      class Cell
        def ==(other)
          "truthy"
        end
      end
      class Factory
        def initialize
          @child = Cell.new
          @count = 9223372036854775805
        end
        def take
          @count = @count + 1
          puts "take"
          @child
        end
        def count
          @count
        end
      end
      factory = Factory.new
      puts factory.take != factory.take
      puts factory.count
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario Outline: Return self and object-valued assignments
    Given the Ruby source is:
      """
      <source>
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

    Examples:
      | source                                                                                                                      |
      | class Cell; def identity; self; end; end; cell = Cell.new; puts cell.identity == cell                                         |
      | class Cell; def store; @value = self; end; end; cell = Cell.new; puts cell.store == cell                                     |
      | class Cell; def identity; return self; end; end; cell = Cell.new; puts cell.identity == cell                                  |
      | class Value; def value; 42; end; end; class Cell; def store; @value = Value.new; end; end; puts Cell.new.store.value        |
      | class Cell; def !; "custom"; end; end; puts !Cell.new                                                                        |
      | class Cell; def ==(other); false; end; def !=(other); "custom"; end; end; puts Cell.new != nil                              |

  Scenario: Defer unused lookup that depends on an unknown parameter
    Given the Ruby source is:
      """
      class Relay
        def unused(child)
          child.text
        end
        def value
          42
        end
      end
      puts Relay.new.value
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Specialize a method for primitive and user-defined operations
    Given the Ruby source is:
      """
      class Number
        def +(other)
          "custom"
        end
      end
      class Relay
        def add(value)
          value + 1
        end
      end
      relay = Relay.new
      puts relay.add(2)
      puts relay.add(Number.new)
      puts relay.add(3)
      """
    When I emit a Rust project
    Then the emitted project contains its source and runtime
    And the emitted Rust defines 3 receiver functions
    When I build and run the emitted project
    Then stdout, stderr, and exit status match CRuby

  Scenario: Reject invalid operations after mutation through a returned alias
    Given the Ruby source is:
      """
      class Cell
        def identity
          self
        end
        def store(value)
          @value = value
        end
        def clean
          @value&.chomp
        end
      end
      cell = Cell.new
      cell.store("Ada\n")
      cell.identity.store(42)
      puts cell.clean
      """
    When I emit a Rust project
    Then the diagnostic has code "E_UNSUPPORTED" at line 9
    And no Rust project was created

  Scenario: Reject a scalar operation after nested branch state changes its possible type
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
      class Holder
        def initialize(child)
          @child = child
        end
        def child
          @child
        end
      end
      holder = Holder.new(Cell.new)
      holder.child.store("Ada\n")
      if gets
        holder.child.store(42)
      end
      puts holder.child.clean
      """
    When I emit a Rust project
    Then the diagnostic has code "E_UNSUPPORTED" at line 6
    And no Rust project was created

  Scenario Outline: Reject unsupported reference operations before emission
    Given the Ruby source is:
      """
      <source>
      """
    When I emit a Rust project
    Then the diagnostic has code "E_UNSUPPORTED" at line 1
    And no Rust project was created

    Examples:
      | source                                                                                                                |
      | class Cell; def value; self; end; end; puts Cell.new                                                                    |
      | class Cell; def value; self; end; end; puts "#{Cell.new}"                                                              |
      | class Cell; def value; self; end; end; if Cell.new; puts 42; end                                                        |
      | class Cell; def value; self; end; end; class Relay; def read(child); child.missing; end; end; Relay.new.read(Cell.new) |
      | class Relay; def read(child); child.text; end; end; Relay.new.read(42)                                                 |
      | class Cell; def value; 42; end; end; class Relay; def read(child); child.initialize; end; end; Relay.new.read(Cell.new) |
      | class Cell; def pick(flag); if flag; self; else; Cell.new; end; end; end; Cell.new.pick(true)                           |
      | class Cell; def pick(flag); return self if flag; nil; end; end; Cell.new.pick(true)                                    |
      | class Cell; def value; 42; end; def store(flag); if flag; @link = self; else; @link = Cell.new; end; end; end; Cell.new.store(true) |
      | class Cell; def value; self; end; end; Cell.new&.value                                                                 |
      | class Cell; def store; @link = self; end; def value; @link.value; end; end; cell = Cell.new; cell.store; cell.value    |

  @delegated_scalar_equality
  Scenario Outline: Reject scalar equality that may delegate to an object
    Given the Ruby source is:
      """
      <source>
      """
    When I emit a Rust project
    Then the diagnostic has code "E_UNSUPPORTED" at line 1
    And no Rust project was created

    Examples:
      | source                                                                                                                          |
      | class Comparator; def ==(other); true; end; end; puts 42 == Comparator.new                                                       |
      | class Comparator; def ==(other); true; end; end; puts 42 != Comparator.new                                                       |
      | class Comparator; def ==(other); true; end; def to_str; "text"; end; end; puts "text" == Comparator.new                       |
      | class Comparator; def ==(other); true; end; def to_str; "text"; end; end; puts "text" != Comparator.new                       |
