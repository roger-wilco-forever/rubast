# language: en
Feature: Selected definition changes and reflection
  Scenario Outline: Subsequent calls observe unconditional namespace and method changes
    Given the Ruby source is:
      """
      <source>
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

    Examples:
      | source |
      | class Item; def value; "old"; end; end; item = Item.new; puts item.value; class Item; def value; "new"; end; end; puts item.value; puts item.send(:value) |
      | class Item; def value; 1; end; puts new.value; def value; 2; end; puts new.value; end; puts Item.new.value |
      | class Base; def value; helper; end; def helper; "old"; end; end; class Child < Base; end; item = Child.new; puts item.value; class Base; def helper; "new"; end; end; puts item.value |
      | module Part; def value; "old"; end; end; class Item; include Part; end; item = Item.new; puts item.value; module Part; def value; "new"; end; end; puts item.value |
      | class Base; def value; "old"; end; end; class Child < Base; def value; "child:#{super}"; end; end; item = Child.new; puts item.value; class Base; def value; "new"; end; end; puts item.value |
      | class Item; @value = "state"; def self.value; @value; end; end; Alias = Item; class Alias; def self.label; value; end; end; puts Item.label; puts Alias == Item |
      | module Scope; VALUE = "constant"; class Item; end; end; class Scope::Item; def value; Scope::VALUE; end; end; puts Scope::Item.new.value |
      | class Base; end; class Child < Base; end; class Child < Base; def value; "ok"; end; end; puts Child.new.value |
      | class Item; private; def hidden; "hidden"; end; end; class Item; def visible; "visible"; end; end; puts Item.new.visible; puts Item.new.send(:hidden) |
      | class Item; def initialize; @value = "old"; end; def value; @value; end; end; first = Item.new; class Item; def initialize; @value = "new"; end; end; second = Item.new; puts first.value; puts second.value |
      | class Item; def self.value; "old"; end; end; puts Item.value; class Item; def self.value; "new"; end; end; puts Item.value |
      | class Item; end; item = Item.new; module Part; def value; "added"; end; end; class Item; include Part; end; puts item.value |

  Scenario Outline: Send literal names with existing literal and forwarded blocks
    Given the Ruby source is:
      """
      <source>
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

    Examples:
      | source |
      | class Item; private; def value(number); yield(number); end; end; total = 1; puts Item.new.send(:value, 7) { \|number\| total = number; next number + 1 }; puts total |
      | class Item; def value; yield; puts "unreachable"; end; end; puts Item.new.send("value") { break "done" } |
      | class Item; def value; yield; end; def forward(&block); send(:value, &block); end; end; puts Item.new.forward { "forwarded" } |
      | class Item; def value; 7; end; end; puts Item.new.send(:value, &nil) |
      | class Item; def value; yield; end; def outer; send(:value) { return "returned" }; "unreachable"; end; end; puts Item.new.outer |

  Scenario Outline: Missing user calls reach the selected method_missing implementation
    Given the Ruby source is:
      """
      <source>
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

    Examples:
      | source |
      | class Item; def method_missing(name, value); "#{name}:#{value}"; end; end; puts Item.new.label("Ada"); puts Item.new.send(:other, "Zoë") |
      | class Item; def method_missing(name, *values, suffix:, **extra); puts values.length; "#{name}:#{suffix}:#{extra[:tag]}"; end; end; puts Item.new.label(1, 2, suffix: "!", tag: "ok") |
      | class Item; private; def hidden; "wrong"; end; def method_missing(name); "missing:#{name}"; end; end; puts Item.new.hidden; puts Item.new.send(:hidden) |
      | class Base; def method_missing(name); "base:#{name}"; end; end; class Child < Base; end; puts Child.new.label |
      | class Item; def self.method_missing(name); "class:#{name}"; end; end; puts Item.label |
      | class Item; def method_missing(name); yield(name); end; end; puts Item.new.label { \|name\| "block:#{name}" }; puts Item.new.send(:other) { break "done" } |
      | class Item; def method_missing(name); raise "missing:#{name}"; end; end; Item.new.label |
      | class Item; def method_missing(name, value); value; end; end; Item.new.label |

  Scenario Outline: Reflect lookup and visibility without executing existing methods
    Given the Ruby source is:
      """
      <source>
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

    Examples:
      | source |
      | class Item; def value; raise "wrong"; end; protected; def guarded; 1; end; private; def hidden; 1; end; end; item = Item.new; puts item.respond_to?(:value); puts item.respond_to?("guarded"); puts item.respond_to?(:guarded, true); puts item.respond_to?(:hidden); puts item.respond_to?(:hidden, true); puts item.respond_to?(:absent) |
      | class Item; def value; 1; end; def check(flag); respond_to?(:value, flag); end; end; item = Item.new; puts item.check(false); puts item.check(true); puts item.respond_to?(:object_id); puts item.respond_to?(:puts); puts item.respond_to?(:puts, true); puts item.respond_to?(:send) |
      | class Base; def self.value; 1; end; private_class_method :value; end; class Child < Base; end; puts Child.respond_to?(:value); puts Child.respond_to?(:value, true); puts Child.respond_to?(:new); module Part; end; puts Part.respond_to?(:new) |
      | class Item; private; def hidden; 1; end; public; def check(flag); respond_to?(:hidden, flag); end; end; item = Item.new; puts item.check(false); puts item.check(true); puts item.check(nil); puts item.check(0) |
      | class Item; def value; 1; end; end; item = Item.new; puts item.respond_to?(:value); class Item; private :value; end; puts item.respond_to?(:value); puts item.respond_to?(:value, true); class Item; public :value; end; puts item.respond_to?(:value) |
      | class Base; def check; respond_to?(:value); end; end; class Child < Base; def value; 1; end; end; puts Base.new.check; puts Child.new.check; puts Base.new.check |
      | class Item; def respond_to?(name, flag = false); "custom:#{name}:#{flag}"; end; end; puts Item.new.respond_to?(:absent) |

  Scenario: Native reflection metadata excludes compiler dependencies
    Given the Ruby source is:
      """
      class Item; end
      item = Item.new
      puts item.respond_to?(:to_json)
      puts item.respond_to?(:object_id)
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Preserve fresh-string hook results and boolean results for existing symbols
    Given the Ruby source is:
      """
      class Item
        def visible; 1; end
        private
        def hidden; 1; end
        def respond_to_missing?(name, include_private)
          puts name
          puts include_private
          0
        end
      end
      item = Item.new
      puts item.respond_to?(:visible)
      puts item.respond_to?("virtual", 42)
      puts item.respond_to?("virtual", 42)
      puts item.respond_to?(:hidden)
      puts item.respond_to?(:hidden, true)
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Parsed symbols are interned before execution even in later unused methods
    Given the Ruby source is:
      """
      class Item
        def respond_to_missing?(name, flag); puts flag; 0; end
        def unused; :future_name; end
      end
      puts Item.new.respond_to?("future_name", 42)
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: A failed send argument does not intern its missing string selector
    Given the Ruby source is:
      """
      class Item
        def method_missing(name, *values); 1; end
        def respond_to_missing?(name, flag); puts flag; 0; end
        def fail_argument; raise "argument"; end
      end
      item = Item.new
      begin
        item.send("unseen_selector", item.fail_argument)
      rescue RuntimeError
        puts "rescued"
      end
      puts item.respond_to?("unseen_selector", 42)
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: A required file's parsed symbols change later reflection specializations
    Given the Ruby file "ids.rb" is:
      """
      module Identifiers
        def unused; :loaded_name; end
      end
      """
    And the Ruby source is:
      """
      class Item
        def respond_to_missing?(name, flag); puts flag; 0; end
        def check; respond_to?("loaded_name", 42); end
      end
      item = Item.new
      puts item.check
      require_relative "ids"
      puts item.check
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Conditional reflective writes promote identifiers globally without promoting unset reads
    Given the Ruby source is:
      """
      class Item
        def respond_to_missing?(name, flag); puts flag; 0; end
        def check; respond_to?("@promoted_field", 42); end
      end
      item = Item.new
      other = Item.new
      puts other.instance_variable_get("@promoted_field")
      puts item.check
      if gets
        puts other.instance_variable_set("@promoted_field", 7)
      end
      puts item.check
      """
    And standard input is:
      """
      write
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Static attribute declarations promote their field identifiers
    Given the Ruby source is:
      """
      class Item
        def respond_to_missing?(name, flag); puts flag; 0; end
      end
      item = Item.new
      puts item.respond_to?("@macro_field", 42)
      class Item
        attr_writer "macro_field"
      end
      puts item.respond_to?("@macro_field", 42)
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Skipped reflective writes leave identifiers unpromoted
    Given the Ruby source is:
      """
      class Item
        def respond_to_missing?(name, flag); puts flag; 0; end
        def check; respond_to?("@skipped_field", 42); end
      end
      item = Item.new
      if gets
        item.instance_variable_set("@skipped_field", 7)
      end
      puts item.check
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Preserve native respond_to backtrace frames when a hook raises
    Given the Ruby source is:
      """
      class Item
        def respond_to_missing?(name, flag)
          raise "hook failed"
        end
      end
      Item.new.respond_to?(:virtual)
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Reopening a class changes reflection and hooks for subsequent calls
    Given the Ruby source is:
      """
      class Item
        def responds; respond_to?(:virtual); end
        def respond_to_missing?(name, flag); false; end
      end
      item = Item.new
      puts item.responds
      class Item
        def respond_to_missing?(name, flag); true; end
        def method_missing(name); "new:#{name}"; end
      end
      puts item.responds
      puts item.virtual
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Reflective field access preserves aliases and class instance state
    Given the Ruby source is:
      """
      class Item
        def value; @value; end
      end
      item = Item.new
      alias_item = item
      puts item.instance_variable_get(:@value)
      puts item.instance_variable_set("@value", "Ada")
      puts alias_item.value
      puts alias_item.instance_variable_get(:@value)
      puts Item.instance_variable_set(:@count, 7)
      class Item
        def self.count; @count; end
      end
      puts Item.count
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Reflective writes evaluate receiver and value once before assigning
    Given the Ruby source is:
      """
      class Cell
        def initialize; @value = 1; end
        def receiver; puts "receiver"; self; end
        def change; puts "value"; @value = 2; end
        def value; @value; end
      end
      cell = Cell.new
      puts cell.receiver.instance_variable_set(:@value, cell.change)
      puts cell.value
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario Outline: Reject mutation and reflection outside the declared contracts
    Given the Ruby source is:
      """
      <source>
      """
    When I emit a Rust project
    Then the diagnostic has code "E_UNSUPPORTED" at line 1
    And no Rust project was created

    Examples:
      | source |
      | class Item; end; module Item; end |
      | module Item; end; class Item; end |
      | class First; end; class Second; end; class Item < First; end; class Item < Second; end |
      | class Item; end; if gets; class Item; def value; 1; end; end; end |
      | class Item; end; while gets; class Item; end; end |
      | class Item; def value; [1].first; end; def value; 1; end; end; Item.new.value |
      | class Item; def value; eval("1"); end; def value; 1; end; end |
      | class Item; end; Item.new.respond_to?(gets) |
      | class Item; end; Item.new.respond_to? |
      | class Item; end; Item.new.respond_to?(:value, false, true) |
      | class Item; def respond_to_missing?(name, flag); true; end; end; Item.new.respond_to?("RUBY_VERSION") |
      | class Item; end; name = :@value; Item.new.instance_variable_get(name) |
      | class Item; end; Item.new.instance_variable_set(:@value) |
      | class Item; end; Item.new.instance_variable_get(:invalid) |
      | class Item; end; Item.new.instance_variables |
      | class Item; def method_missing(name); super; end; end; Item.new.absent |
      | class Item; def method_missing(name); absent; end; end; Item.new.absent |
      | class Item; def method_missing(name); "wrong"; end; end; Item.new.object_id |
      | class Item; end; Item.new.method(:value) |
      | class Item; end; Item.class_eval("def value; 1; end") |
      | class Item; end; Item.define_method(:value) { 1 } |
      | class Item; def self.method_added(name); puts name; end; def value; 1; end; end |
      | class Item; def self.singleton_method_added(name); puts name; end; end |
      | class Item; def self.inherited(child); puts "child"; end; end |
      | class Item; if gets; attr_reader :value; end; end |
      | class Item; def value; 1; end; if gets; private :value; end; end |
      | module Part; end; class Item; if gets; include Part; end; end |

  Scenario: Reopening through an alias preserves its written name in body backtraces
    Given the Ruby source is:
      """
      class Original; end
      Alias = Original
      class Alias
        raise "body failed"
      end
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: A realistic registry combines definition changes and virtual methods
    Given I use the example "workloads/dynamic_registry.rb"
    And standard input is:
      """
      Ada
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby
