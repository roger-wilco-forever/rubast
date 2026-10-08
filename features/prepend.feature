Feature: Static prepended modules
  Prepended lookup has distinct super positions.

  Scenario: Prepend runs before own methods and super retains the concrete receiver
    Given the Ruby source is:
      """
      module Wrapper
        def value; "wrapper:#{super}"; end
      end
      class Base
        def value; "base"; end
      end
      class Choice < Base
        prepend Wrapper
        def value; "choice:#{super}"; end
      end
      puts Choice.new.value
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Included and prepended occurrences of one module have distinct super positions
    Given the Ruby source is:
      """
      module Wrapper
        def value; "wrapper:#{super}"; end
      end
      class Base
        def value; "base"; end
      end
      class Choice < Base
        include Wrapper
        prepend Wrapper
        def value; "choice:#{super}"; end
      end
      puts Choice.new.value
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Multiple prepend arguments preserve declared order
    Given the Ruby source is:
      """
      module First
        def value; "first:#{super}"; end
      end
      module Second
        def value; "second:#{super}"; end
      end
      class Choice
        prepend First, Second
        def value; "choice"; end
      end
      puts Choice.new.value
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Repeated prepend keeps its original position
    Given the Ruby source is:
      """
      module First
        def value; "first:#{super}"; end
      end
      module Second
        def value; "second:#{super}"; end
      end
      class Choice
        prepend First
        prepend Second
        prepend First
        def value; "choice"; end
      end
      puts Choice.new.value
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Nested prepends preserve dependencies and ancestor positions
    Given the Ruby source is:
      """
      module Shared
        def value; "shared:#{super}"; end
      end
      module Wrapper
        include Shared
        def value; "wrapper:#{super}"; end
      end
      class Choice
        include Shared
        prepend Wrapper
        def value; "choice"; end
      end
      puts Choice.new.value
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Prepended initializer methods retain allocated receiver fields
    Given the Ruby source is:
      """
      module Wrapper
        def initialize(value); super(value + 1); end
      end
      class Choice
        prepend Wrapper
        def initialize(value); @value = value; end
        def value; @value; end
      end
      puts Choice.new(7).value
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

