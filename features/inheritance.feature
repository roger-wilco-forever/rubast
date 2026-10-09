# language: en
Feature: Inherit instance methods while preserving Ruby lookup
  Scenario: Inherit construction and methods through empty subclasses
    Given the Ruby source is:
      """
      class Label
        def initialize(name)
          @name = name
        end
        def text
          @name&.chomp
        end
      end
      class Child < Label
      end
      class Grandchild < Child
      end
      class Empty
      end
      first = Grandchild.new("Ada\n")
      second = Child.new("Zoë\n")
      puts first.text
      puts second.text
      empty = Empty.new
      puts empty == empty
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Dispatch inherited helpers and constructors on the actual receiver
    Given the Ruby source is:
      """
      class Base
        def initialize(name)
          store(name)
        end
        def store(name)
          @name = name
        end
        def text
          "base:#{@name}"
        end
        def message
          "#{text}:#{self.text}"
        end
      end
      class Child < Base
        def store(name)
          @name = "child:#{name}"
        end
        def text
          @name
        end
      end
      puts Base.new("Ada").message
      puts Child.new("Zoë").message
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Start super above the defining class and skip missing methods
    Given the Ruby source is:
      """
      class Base
        def text(name)
          "base:#{name}"
        end
      end
      class Gap < Base
      end
      class Middle < Gap
        def text(name)
          "middle:#{super}"
        end
      end
      class Child < Middle
        def text(name)
          "child:#{super(name)}"
        end
      end
      class Leaf < Child
      end
      puts Middle.new.text("Ada")
      puts Leaf.new.text("Zoë")
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Forward current parameter values without reevaluating caller expressions
    Given the Ruby source is:
      """
      class Base
        def text(first, second)
          "#{first}:#{second}:#{first}"
        end
      end
      class Child < Base
        def text(name, other)
          name = "changed:#{name}"
          first = super
          "#{first}/#{super}"
        end
      end
      puts Child.new.text(gets&.chomp, gets&.chomp)
      puts gets&.chomp
      """
    And standard input is:
      """
      Ada
      Zoë
      remaining
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Evaluate explicit super arguments once from left to right
    Given the Ruby source is:
      """
      class Base
        def text(first, second)
          "#{first}:#{second}:#{first}"
        end
      end
      class Child < Base
        def text
          @name = "before"
          result = super(@name, change(gets&.chomp))
          "#{result}:#{@name}"
        end
        def change(name)
          @name = name
        end
      end
      puts Child.new.text
      puts gets&.chomp
      """
    And standard input is:
      """
      Ada
      remaining
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Distinguish super with no arguments from forwarding
    Given the Ruby source is:
      """
      class Base
        def text
          "base"
        end
      end
      class Child < Base
        def text(name)
          "#{name}:#{super()}"
        end
      end
      puts Child.new.text("Ada")
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Run superclass constructors on the same object and ignore their results
    Given the Ruby source is:
      """
      class Base
        def initialize(name)
          super()
          @name = name
          "base result"
        end
        def name
          @name
        end
      end
      class Child < Base
        def initialize(name)
          puts super
          @name = "child:#{@name}"
          return "child result"
        end
      end
      object = Child.new("Ada")
      alias_object = object
      puts alias_object.name
      puts object == alias_object
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Use the default no-argument initializer as a super target
    Given the Ruby source is:
      """
      class Base
      end
      class Child < Base
        def initialize
          puts super
          @name = "Ada"
        end
        def name
          @name
        end
      end
      puts Child.new.name
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Share inherited object fields and dispatch inherited equality overrides
    Given the Ruby source is:
      """
      class Base
        def initialize(value)
          @value = value
        end
        def value
          @value
        end
        def connect(other)
          @other = other
          self
        end
        def other
          @other
        end
        def ==(other)
          puts "compare"
          @value == other.value
        end
      end
      class Child < Base
      end
      first = Child.new(7)
      second = Base.new(7)
      first.connect(second)
      puts first == second
      puts first != second
      puts first.other == second
      puts first.connect(first).other.other != second
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Forward and return an object through super without copying its fields
    Given the Ruby source is:
      """
      class Base
        def store(other)
          @other = other
        end
        def name(value)
          @name = value
        end
        def text
          @name
        end
        def other
          @other
        end
      end
      class Child < Base
        def store(other)
          result = super
          result.name("Ada")
          result
        end
      end
      first = Child.new
      second = Base.new
      returned = first.store(second)
      puts returned == second
      returned.name("Zoë")
      puts first.other.text
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Restore the super context after calls on another receiver
    Given the Ruby source is:
      """
      class Other
        def value
          "other"
        end
      end
      class Base
        def value
          "base"
        end
      end
      class Child < Base
        def value
          puts Other.new.value
          return super
          "unreachable"
        end
      end
      puts Child.new.value
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario Outline: Reject unsupported inheritance and super semantics before emission
    Given the Ruby source is:
      """
      <source>
      """
    When I emit a Rust project
    Then the diagnostic has code "E_UNSUPPORTED" at line 1
    And no Rust project was created

    Examples:
      | source                                                                                                                |
      | class Child < Missing; end                                                                                            |
      | class Child < Child; end                                                                                              |
      | class Child < Object; end                                                                                             |
      | class Child < String; end                                                                                             |
      | class Base; end; class Child < Base.new; end                                                                           |
      | class Base; end; class Child < Base; def value; super; end; end                                                        |
      | class Base; def value; self.value; end; end; class Child < Base; end                                                    |
      | class Base; def value; helper; end; def helper; 1; end; end; class Child < Base; def helper; value; end; end; Child.new.value |
      | class Base; def initialize; end; end; class Child < Base; end; Child.new.initialize                                    |
      | super                                                                                                                 |

  Scenario: Report a missing super target at its Ruby source line
    Given the Ruby source is:
      """
      class Base
      end
      class Child < Base
        def value
          super
        end
      end
      """
    When I emit a Rust project
    Then the diagnostic has code "E_UNSUPPORTED" at line 5
    And no Rust project was created

  Scenario Outline: Accepted extended argument fixtures preserve Ruby execution
    Given the Ruby source is:
      """
      <source>
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

    Examples:
      | source |
      | class Base; def value(input); input; end; end; class Child < Base; def value; super(); end; end |
      | class Base; def value; 1; end; end; class Child < Base; def value(input); super; end; end |
      | class Base; end; class Child < Base; def initialize(input); super; end; end |
      | class Base; def value; 1; end; end; class Child < Base; def value; super { 1 }; end; end |
      | class Base; def value(input); input; end; end; class Child < Base; def value(input); super(*input); end; end |
