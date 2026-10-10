# language: en
Feature: Preserve extended argument boundaries

  Scenario: Invalid block conversions preserve argument order and Ruby TypeError
    Given the Ruby source is:
      """
      class Choice
        def value(number = puts("wrong default"), &callback); puts "wrong body"; end
      end
      trace = "A"
      begin
        Choice.new.value(trace << "1", &(trace << "2"; 7))
      rescue TypeError => error
        puts error.message
      end
      puts trace
      begin
        Choice.new.value(&true)
      rescue TypeError => error
        puts error.message
      end
      begin
        Choice.new.value(&"bad")
      rescue TypeError => error
        puts error.message
      end
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Uncaught invalid block conversion keeps caller frame and source snippet
    Given the Ruby source is:
      """
      class Choice
        def value(&callback); puts "wrong body"; end
      end
      Choice.new.value(&7)
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Repeated wrong default constructors retain the current call location
    Given the Ruby source is:
      """
      class Choice; end
      begin
        Choice.new(7)
      rescue ArgumentError
        puts "first"
      end
      Choice.new(9)
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Argument errors discard later field mutations in rescued execution
    Given the Ruby source is:
      """
      class Cell
        def initialize; @text = "Ada\n"; end
        def text; @text&.chomp; end
        def replace; @text = 7; end
      end
      class Choice
        def value(**options); puts "wrong body"; end
      end
      cell = Cell.new
      begin
        Choice.new.value(**7, later: cell.replace)
      rescue TypeError
        puts cell.text
      end
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Call-time default allocations fail only at the existing loop boundary
    Given the Ruby source is:
      """
      class Choice
        def value(values = []); values.length; end
      end
      puts Choice.new.value([7])
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Rest packs are independent on bounded repeated yielding calls
    Given the Ruby source is:
      """
      class Choice
        def value(*values, **options); values[0] + options[:extra]; end
      end
      choice = Choice.new
      [7,9].each { |number| puts choice.value(number, extra: 1) }
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: A default expression exception skips later supplied block execution
    Given the Ruby source is:
      """
      class Choice
        def value(number = raise("default"), &callback)
          callback.call(number)
        ensure
          puts "wrong cleanup"
        end
      end
      begin
        Choice.new.value { puts "wrong block" }
      rescue RuntimeError => error
        puts error.message
      end
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Block arguments are bound before default calls in the method scope
    Given the Ruby source is:
      """
      class Choice
        def value(number = yield(7), &callback); callback.call(number + 1); end
      end
      puts Choice.new.value { |number| number + 10 }
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Unknown integer keyword keys produce a rescuable Ruby argument error
    Given the Ruby source is:
      """
      class Choice
        def value(count: 7); count; end
      end
      begin
        Choice.new.value(**{9 => 1})
      rescue ArgumentError => error
        puts error.message
      end
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario Outline: Reject extended argument semantics without an execution contract
    Given the Ruby source is:
      """
      <source>
      """
    When I emit a Rust project
    Then the diagnostic has code "E_UNSUPPORTED" at line 1
    And no Rust project was created

    Examples:
      | source |
      | class Choice; def value(*); end; end |
      | class Choice; def value(**); end; end |
      | class Choice; def value(&); end; end |
      | class Choice; def value(**nil); end; end |
      | class Choice; def value(...); end; end |
      | class Choice; def value((one, two)); end; end |
      | class Choice; def value(&callback); callback; end; end; Choice.new.value { 7 } |
      | class Choice; def value(&callback); @callback = callback; end; end; Choice.new.value { 7 } |
      | class Choice; def value(&callback); [callback]; end; end; Choice.new.value { 7 } |
      | class Choice; def value(&callback); {saved: callback}; end; end; Choice.new.value { 7 } |
      | class Choice; def value(&callback); puts callback; end; end; Choice.new.value { 7 } |
      | class Choice; def value(&callback); "#{callback}"; end; end; Choice.new.value { 7 } |
      | class Choice; def value(&callback); helper(callback); end; def helper(value); 7; end; end; Choice.new.value { 7 } |
      | class Choice; def value(&callback); callback.lambda?; end; end; Choice.new.value { 7 } |
      | class Choice; def value(&callback); [7].each(&callback); end; end; Choice.new.value { 7 } |
      | class Choice; def value(*values); 7; end; end; class Input; def to_a; [7]; end; end; Choice.new.value(*Input.new) |
      | class Choice; def value(**values); 7; end; end; class Input; def to_hash; {count: 7}; end; end; Choice.new.value(**Input.new) |
      | class Choice; def value(*values); 7; end; end; Choice.new.value(*(if true; [7]; else; [7, 9]; end)) |

  Scenario: Named block failures follow the Ruby exception hierarchy
    Given the Ruby source is:
      """
      class Choice
        def value(&callback); callback.call; end
      end
      begin
        Choice.new.value
      rescue NameError => error
        puts error.message
      end
      begin
        raise NameError, "named"
      rescue StandardError => error
        puts error.message
      end
      raise NoMethodError, "manual"
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: The configurable quote example builds independently
    Given I use the example "configurable_quotes.rb"
    When I emit a Rust project
    Then the emitted project contains its source and runtime
    When I build and run the emitted project
    Then stdout, stderr, and exit status match CRuby

  Scenario: Explicit super block conversion errors occur before the base body
    Given the Ruby source is:
      """
      class Base
        def value(&callback); puts "wrong body"; end
      end
      class Child < Base
        def value; super(&7); end
      end
      begin
        Child.new.value
      rescue TypeError => error
        puts error.message
      end
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: A block expression exception prevents defaults and callee execution
    Given the Ruby source is:
      """
      class Choice
        def value(number = puts("wrong default"), &callback); puts "wrong body"; end
      end
      begin
        Choice.new.value(&raise("conversion"))
      rescue RuntimeError => error
        puts error.message
      end
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Block call receiver expressions run once before argument expressions
    Given the Ruby source is:
      """
      class Choice
        def value(trace, &callback)
          (trace << "R"; callback).call(trace << "A")
        end
      end
      trace = ""
      puts Choice.new.value(trace) { |text| text }
      puts trace
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Nil keyword splats contribute no keywords or positional arguments
    Given the Ruby source is:
      """
      class Choice
        def value(count: 7); count; end
        def positional(number = 9); number; end
      end
      choice = Choice.new
      puts choice.value(**nil)
      puts choice.positional(**nil)
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Invalid literal boolean keyword splats raise Ruby TypeError
    Given the Ruby source is:
      """
      class Choice
        def value(**options); puts "wrong body"; end
      end
      begin
        Choice.new.value(**false)
      rescue TypeError => error
        puts error.message
      end
      begin
        Choice.new.value(**true)
      rescue TypeError => error
        puts error.message
      end
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby
