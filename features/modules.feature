Feature: Static module composition
  Module lookup and class object extension match CRuby.

  Scenario: Included methods retain their defining lexical constants
    Given the Ruby source is:
      """
      module Rules
        RATE = 7
        def value; RATE; end
      end
      class Choice
        RATE = 9
        include Rules
      end
      puts Choice.new.value
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Multiple include arguments preserve Ruby precedence
    Given the Ruby source is:
      """
      module First
        def value; "first"; end
      end
      module Second
        def value; "second"; end
      end
      class Choice
        include First, Second
      end
      puts Choice.new.value
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Sequential includes reverse precedence and super continues through mixins
    Given the Ruby source is:
      """
      module First
        def value; "first:#{super}"; end
      end
      module Second
        def value; "second:#{super}"; end
      end
      class Base
        def value; "base"; end
      end
      class Choice < Base
        include First
        include Second
        def value; "choice:#{super}"; end
      end
      puts Choice.new.value
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Nested includes deduplicate shared ancestors without moving them
    Given the Ruby source is:
      """
      module Shared
        def value; "shared:#{super}"; end
      end
      module First
        include Shared
        def value; "first:#{super}"; end
      end
      module Second
        include Shared
        def value; "second:#{super}"; end
      end
      class Base
        def value; "base"; end
      end
      class Choice < Base
        include First
        include Second
      end
      puts Choice.new.value
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Repeated inclusion keeps its original lookup position
    Given the Ruby source is:
      """
      module First
        def value; "first"; end
      end
      module Second
        def value; "second"; end
      end
      class Choice
        include First
        include Second
        include First
      end
      puts Choice.new.value
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Extend adds module methods to class objects and inherited class methods
    Given the Ruby source is:
      """
      module Rules
        def value; @value; end
        def store(value); @value = value; end
      end
      class Base
        extend Rules
        store(7)
      end
      class Child < Base
      end
      puts Base.value
      puts Child.value
      Child.store(9)
      puts Child.value
      puts Base.value
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Extend self shares module state with its singleton methods
    Given the Ruby source is:
      """
      module Rules
        def value; @value; end
        def store(value); @value = value; end
        extend self
        store(7)
      end
      puts Rules.value
      Rules.store(9)
      puts Rules.value
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Mixin constructors retain concrete allocation identity
    Given the Ruby source is:
      """
      module Storage
        def initialize(value); @value = value; end
        def value; @value; end
      end
      class Choice
        include Storage
      end
      item = Choice.new(7)
      puts item.value
      puts item == item
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Mixin blocks preserve super forwarding and original break targets
    Given the Ruby source is:
      """
      module Wrapper
        def value(number, &callback); super(number + 1, &callback); end
      end
      class Base
        def value(number); yield number; 99; end
      end
      class Choice < Base
        include Wrapper
      end
      puts(Choice.new.value(7) { |value| break value })
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

