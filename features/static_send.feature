# language: en
Feature: Send literal names to statically resolved user methods
  Scenario: Send symbol and string names to private and protected inherited methods
    Given the Ruby source is:
      """
      class Base
        def initialize(value)
          @value = value
        end
        private
        def value
          @value
        end
        protected
        def change(value)
          @value = value
        end
      end
      class Child < Base
        def read
          send(:value)
        end
      end
      item = Child.new("Ada")
      puts item.send("value")
      puts item.send(:change, "Zoë")
      puts item.read
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Preserve receiver and argument evaluation order with shared fields
    Given the Ruby source is:
      """
      class Cell
        def initialize
          @value = 1
        end
        def receiver
          puts "receiver"
          self
        end
        def value
          puts "value"
          @value
        end
        def change
          puts "change"
          @value = 2
        end
        private
        def take(first, second)
          puts first
          puts second
          @value
        end
      end
      cell = Cell.new
      puts cell.receiver.send(:take, cell.value, cell.change)
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Bind defaults, splats, keywords, and rest arguments through send
    Given the Ruby source is:
      """
      class Label
        def text(first = "default", *rest, suffix: "!", **extra)
          puts first
          puts rest.length
          puts suffix
          puts extra[:tag]
          first
        end
      end
      label = Label.new
      puts label.send(:text)
      words = ["Ada", "Zoë"]
      options = { suffix: "?", tag: "ok" }
      puts label.send("text", *words, **options)
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Resolve inherited private class methods on the concrete class object
    Given the Ruby source is:
      """
      class Base
        def self.label
          part
        end
        def self.part
          "base"
        end
        private_class_method :label
      end
      class Child < Base
        def self.part
          "child"
        end
      end
      alias_class = Child
      puts Base.send(:label)
      puts alias_class.send("label")
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Preserve prepend lookup and super for sent methods
    Given the Ruby source is:
      """
      module Prefix
        def label
          "prefix:#{super}"
        end
      end
      class Label
        def label
          "base"
        end
        prepend Prefix
      end
      puts Label.new.send(:label)
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Preserve overrides of send including ordinary block forwarding
    Given the Ruby source is:
      """
      class Custom
        def send(name, value)
          yield "#{name}:#{value}"
        end
      end
      puts Custom.new.send(:message, "Ada") { |text| "custom:#{text}" }
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Preserve ordinary send overrides without a block
    Given the Ruby source is:
      """
      class Custom
        def send(name, value)
          "#{name}:#{value}"
        end
      end
      puts Custom.new.send(:missing, "custom")
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Send native attribute readers and writers without losing aliases
    Given the Ruby source is:
      """
      class Cell
        attr_accessor :value
        private :value, :value=
      end
      cell = Cell.new
      alias_cell = cell
      puts cell.send(:value=, "Ada")
      puts alias_cell.send(:value)
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Specialize an included module's sent helper for each concrete host
    Given the Ruby source is:
      """
      module Dispatch
        def label
          send(:part)
        end
      end
      class First
        include Dispatch
        private
        def part
          "first"
        end
      end
      class Second
        include Dispatch
        private
        def part
          "second"
        end
      end
      puts First.new.label
      puts Second.new.label
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Keep direct and sent method specializations separate when nested lookup differs
    Given the Ruby source is:
      """
      class Base
        def label
          part
        end
        def part
          "base"
        end
      end
      class Child < Base
        def part
          "child"
        end
      end
      puts Base.new.label
      puts Child.new.send(:label)
      puts Child.new.label
      puts Base.new.send(:label)
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Retain uncaught exception locations and backtraces through send
    Given the Ruby source is:
      """
      class Failing
        def fail_now
          raise "failed"
        end
      end
      Failing.new.send(:fail_now)
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Retain uncaught argument error locations through send
    Given the Ruby source is:
      """
      class Required
        def take(value)
          value
        end
      end
      Required.new.send(:take)
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario Outline: Diagnose send outside the static contract before emission
    Given the Ruby source is:
      """
      <source>
      """
    When I emit a Rust project
    Then the diagnostic has code "E_UNSUPPORTED" at line 1
    And no Rust project was created

    Examples:
      | source                                                                                                 |
      | class Item; def value; 1; end; end; name = :value; Item.new.send(name)                                    |
      | class Item; def value; 1; end; end; Item.new.send("#{:value}")                                           |
      | class Item; def value; 1; end; end; Item.new.send(*[:value])                                              |
      | class Item; def value; 1; end; end; Item.new.send(1)                                                      |
      | class Item; def value; 1; end; end; Item.new.send                                                        |
      | class Item; end; Item.new.send(:missing)                                                                |
      | class Item; end; Item.new.send(:object_id)                                                              |
      | class Item; def initialize; end; end; Item.new.send(:initialize)                                        |
      | class Item; end; Item.send(:new)                                                                       |
      | class Item; def value; 1; end; end; Item.new&.send(:value)                                                |
      | class Item; def value; send(:value); end; end; Item.new.send(:value)                                     |
      | 1.send(:to_s)                                                                                          |
      | class Item; def value; 1; end; end; Item.new.public_send(:value)                                          |
      | class Item; def value; 1; end; end; Item.new.__send__(:value)                                             |
