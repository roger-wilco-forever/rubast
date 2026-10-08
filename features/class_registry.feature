Feature: Class definition registry operations
  Registry collection operations preserve Ruby storage and values.

  Scenario: Array concatenation copies slots and preserves nested object aliases
    Given the Ruby source is:
      """
      nested = [7]
      left = [nested]
      right = [9]
      combined = left + right
      combined[1] = 11
      combined[0][0] = 13
      puts left[0][0]
      puts right[0]
      puts combined[1]
      puts combined.length
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Array equality compares nested values rather than arena identity
    Given the Ruby source is:
      """
      puts(["a", "b"] == ["a", "b"])
      puts([1, ["a", nil, true]] == [1, ["a", nil, true]])
      puts([1, 2] == [1])
      puts([1, 2] != [1, 3])
      puts([1] == 1)
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: nil predicate preserves receiver effects and object identity
    Given the Ruby source is:
      """
      class Choice
        def initialize; @trace = ""; end
        def value; @trace << "called"; nil; end
        def trace; @trace; end
      end
      item = Choice.new
      puts item.value.nil?
      puts item.trace
      puts item.nil?
      puts 7.nil?
      puts false.nil?
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Scalar p prints inspection text and returns its input
    Given the Ruby source is:
      """
      puts(p(7))
      p(nil)
      p(false)
      p(true)
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Class definition registry retains inherited fallback and child state
    Given the Ruby source is:
      """
      class Base
        def self.defs; @defs; end
        def self.add; @defs = defs + [{ keys: ["a", "b"] }]; end
        def self.clear; @defs = []; end
        @defs = []
        add
      end
      class Child < Base
        def self.defs; @defs.nil? ? Base.defs : @defs; end
      end
      p(Child.defs[0][:keys] == ["a", "b"])
      Child.clear
      puts Child.defs.length
      puts Base.defs.length
      Child.add
      puts Child.defs.length
      puts Base.defs.length
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Supplied class definition registry executes unchanged
    Given I use the example "workloads/class_definitions.rb"
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby
