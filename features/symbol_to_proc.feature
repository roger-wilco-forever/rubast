Feature: Literal Symbol callbacks reuse validated block dispatch

  Scenario: The former ignored Symbol block boundary executes unchanged
    Given the Ruby source is:
      """
      class Choice; def value; 7; end; end; Choice.new.value(&:to_s)
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: A packing batch combines callbacks inheritance and collection
    Given I use the example "workloads/callback_batch.rb"
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby
    And CRuby prints the reference output:
      """
      packed/packed
      total:3350 cents
      """

  Scenario: Map selects concrete inherited and overridden public methods
    Given the Ruby source is:
      """
      class Base
        def initialize(number)
          @number = number
        end
        def value
          @number
        end
      end
      class Child < Base
        def value
          super + 1
        end
      end
      values = [Base.new(7), Child.new(8)].map(&:value)
      puts values[0]
      puts values[1]
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Each preserves aliases and callback mutations across collection
    Given the Ruby source is:
      """
      class Item
        attr_reader :number
        def initialize
          @number = 0
        end
        def increment
          GC.start
          @number += 1
        end
      end
      item = Item.new
      items = [item, item]
      returned = items.each(&:increment)
      returned.push(item)
      puts items.length
      puts item.number
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Supported native selectors operate on scalar and collection receivers
    Given the Ruby source is:
      """
      texts = ["Ada\n", "Zoë\n"].map(&:chomp)
      puts texts[0]
      puts texts[1]
      lengths = [[1], [2, 3]].map(&:length)
      puts lengths[0]
      puts lengths[1]
      missing = [nil, 7, true].map(&:nil?)
      puts missing[0]
      puts missing[1]
      puts missing[2]
      puts 2.times(&:nil?)
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario Outline: Optional array slots invoke the callback only when present
    Given the Ruby source is:
      """
      values = ["first\n"]
      if gets&.chomp == "yes"
        values.push("second\n")
        nil
      end
      mapped = values.map(&:chomp)
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

  Scenario: Named callbacks forward through methods constructors and super
    Given the Ruby source is:
      """
      class Item
        def value
          7
        end
      end
      class Producer
        def run(item, &callback)
          callback.call(item)
        end
      end
      class Base
        attr_reader :result
        def initialize(item, &callback)
          @result = Producer.new.run(item, &callback)
        end
      end
      class Child < Base
        def initialize(item, &callback)
          super
        end
      end
      puts Child.new(Item.new, &:value).result
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Explicit super can replace its callback with a literal Symbol
    Given the Ruby source is:
      """
      class Item
        def value
          7
        end
      end
      class Base
        def run(item)
          yield item
        end
      end
      class Child < Base
        def run(item)
          super(item, &:value)
        end
      end
      puts Child.new.run(Item.new)
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Empty and ignored callbacks perform no dispatch
    Given the Ruby source is:
      """
      class Choice
        def value
          7
        end
      end
      puts [].map(&:missing).length
      puts 0.times(&:missing)
      puts Choice.new.value(&:to_s)
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Call arguments run once before callback dispatch
    Given the Ruby source is:
      """
      class Item
        attr_accessor :number
        def initialize
          @number = 1
        end
        def value
          @number
        end
      end
      class Producer
        def run(item, ignored)
          yield item
        end
      end
      item = Item.new
      puts Producer.new.run(item, item.number = 9, &:value)
      puts item.number
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Missing and inaccessible targets reach the existing method_missing hook
    Given the Ruby source is:
      """
      class Item
        private
        def hidden
          "unexpected"
        end
        def method_missing(name)
          "missing:#{name}"
        end
      end
      values = [Item.new].map(&:hidden)
      puts values[0]
      values = [Item.new].map(&:unknown)
      puts values[0]
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Callback errors retain native frames and cleanup continues
    Given the Ruby source is:
      """
      # frozen_string_literal: true
      begin
        ["frozen"].map(&:clear)
      rescue FrozenError => error
        puts error.message
      ensure
        GC.start
      end
      puts ["after\n"].map(&:chomp)[0]
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario Outline: Uncaught callback failures retain the exact CRuby backtrace
    Given the Ruby source is:
      """
      <source>
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

    Examples:
      | source |
      | class Item; def value; raise "failure"; end; end; [Item.new].map(&:value) |
      | class Item; def value(required); required; end; end; [Item.new].map(&:value) |
      | class Item; attr_writer :value; end; [Item.new].map(&:value=) |
      | values = { "frozen" => 1 }; values.keys.map(&:clear) |
      | values = { "frozen" => 1 }; values.keys.map(&:chomp!) |
      | class Item; def value; raise "failure"; end; end; class Producer; def run(item); yield item; end; end; Producer.new.run(Item.new, &:value) |
      | class Item; def value; raise "failure"; end; end; class Producer; def run(item, &block); block.call(item); end; end; Producer.new.run(Item.new, &:value) |

  Scenario Outline: Unsupported conversion selector and callback shapes stay located
    Given the Ruby source is:
      """
      <source>
      """
    When I emit a Rust project
    Then the diagnostic has code "E_UNSUPPORTED" at line 1
    And no Rust project was created

    Examples:
      | source |
      | selector = :nil?; [1].map(&selector) |
      | [1].map(&:to_s) |
      | [1].sum(&:nil?) |
      | [1]&.map(&:nil?) |
      | class Item; private; def hidden; 7; end; end; [Item.new].map(&:hidden) |
      | class Item; protected; def hidden; 7; end; def run; [self].map(&:hidden); end; end; Item.new.run |
      | class Producer; def run; yield; end; end; Producer.new.run(&:nil?) |
      | class Producer; def run; yield(1, 2); end; end; Producer.new.run(&:nil?) |
      | class Producer; def run; yield(1, kind: 2); end; end; Producer.new.run(&:nil?) |
      | class Producer; def run(&block); block; end; end; Producer.new.run(&:nil?) |
