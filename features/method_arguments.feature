# language: en
Feature: Bind extended method arguments with Ruby evaluation order

  Scenario: Omitted optional arguments differ from explicit nil
    Given the Ruby source is:
      """
      class Choice
        def value(number = 7); number; end
      end
      choice = Choice.new
      puts choice.value
      puts choice.value(nil) == nil
      puts choice.value(9)
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Defaults run at call time in method scope and only when omitted
    Given the Ruby source is:
      """
      class Choice
        def initialize; @count = 0; end
        def count; @count; end
        def next_value; @count += 1; end
        def value(first = next_value, second = first + 10); "#{first}:#{second}"; end
      end
      choice = Choice.new
      puts choice.value
      puts choice.value(7)
      puts choice.value(8, 9)
      puts choice.count
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Supplied arguments finish before defaults run
    Given the Ruby source is:
      """
      class Choice
        def value(first, second = first << "D"); puts first; second; end
      end
      text = "A"
      puts Choice.new.value(text << "B")
      puts text
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Defaults see the method receiver and preserve aliases
    Given the Ruby source is:
      """
      class Choice
        def initialize(text = "new"); @text = text; end
        def text; @text; end
        def value(text = @text); text << "!"; end
      end
      first = Choice.new
      second = Choice.new("other")
      puts first.value
      puts first.text
      puts second.value
      puts second.text
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Required trailing arguments bind from the right
    Given the Ruby source is:
      """
      class Choice
        def value(first, middle = 10, last); "#{first}:#{middle}:#{last}"; end
      end
      choice = Choice.new
      puts choice.value(1, 2)
      puts choice.value(1, 2, 3)
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: A default exception occurs before implicit method ensure
    Given the Ruby source is:
      """
      class Choice
        def value(number = raise("default"))
          puts "body"
        ensure
          puts "method cleanup"
        end
      end
      begin
        Choice.new.value
      rescue => error
        puts error.message
      end
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Wrong arity evaluates arguments but does not evaluate defaults or body
    Given the Ruby source is:
      """
      class Choice
        def value(first, second = puts("default")); puts "body"; end
      end
      trace = "A"
      begin
        Choice.new.value(trace << "1", trace << "2", trace << "3")
      rescue ArgumentError => error
        puts error.message
      end
      puts trace
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Missing required arguments are rescuable runtime errors
    Given the Ruby source is:
      """
      class Choice
        def value(first, second = 10); first; end
      end
      begin
        Choice.new.value
      rescue ArgumentError => error
        puts error.message
      end
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Uncaught wrong arity retains the defining method frame
    Given the Ruby source is:
      """
      class Choice
        def value(first, second = 10); first; end
      end
      Choice.new.value
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Wrong default constructor arity has the BasicObject initialize frame
    Given the Ruby source is:
      """
      class Choice; end
      Choice.new(1)
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Optional arguments work with literal yielding calls
    Given the Ruby source is:
      """
      class Choice
        def value(first = 7); yield(first); "after"; end
      end
      choice = Choice.new
      puts choice.value { |number| puts number }
      puts choice.value(9) { |number| puts number }
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Omitted defaults and provided inputs cannot share an incompatible function
    Given the Ruby source is:
      """
      class Choice
        def value(number = 7); number; end
      end
      choice = Choice.new
      puts choice.value(1)
      puts choice.value
      puts choice.value(2)
      puts choice.value
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Bare super forwards updated optional parameter values
    Given the Ruby source is:
      """
      class Base
        def value(number = 3); number; end
      end
      class Child < Base
        def value(number = 7); number += 1; super; end
      end
      puts Child.new.value
      puts Child.new.value(10)
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Rest arguments collect independent arrays with shared elements
    Given the Ruby source is:
      """
      class Choice
        def values(*values); values; end
      end
      choice = Choice.new
      text = "A"
      first = choice.values(text, 7)
      second = choice.values(text, 9)
      first[0] << "!"
      first[1] = 10
      puts text
      puts second[0]
      puts second[1]
      puts choice.values.length
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Leading optional rest and trailing arguments bind in Ruby order
    Given the Ruby source is:
      """
      class Choice
        def value(first, middle = 10, *rest, last); "#{first}:#{middle}:#{rest.length}:#{last}"; end
      end
      choice = Choice.new
      puts choice.value(1, 2)
      puts choice.value(1, 2, 3)
      puts choice.value(1, 2, 3, 4, 5)
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Array splats snapshot elements before later argument effects
    Given the Ruby source is:
      """
      class Choice
        def value(first, second, third); "#{first}:#{second}:#{third}"; end
      end
      values = [1, 2]
      puts Choice.new.value(*values, values[0] = 9)
      puts values[0]
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Multiple splats and nil splats preserve argument order
    Given the Ruby source is:
      """
      class Choice
        def value(*values); "#{values.length}:#{values[0]}:#{values[2]}"; end
      end
      first = [1, 2]
      second = [3]
      puts Choice.new.value(*nil, *first, *second)
      puts Choice.new.value(*7, 8, 9)
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Bare super expands the mutated rest array
    Given the Ruby source is:
      """
      class Base
        def value(*values); "#{values.length}:#{values[0]}:#{values[1]}"; end
      end
      class Child < Base
        def value(*values); values[0] = 7; values.push(9); super; end
      end
      puts Child.new.value(1)
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Required and optional keywords bind by name
    Given the Ruby source is:
      """
      class Choice
        def value(first, count:, label: "items"); "#{first}:#{label}:#{count}"; end
      end
      choice = Choice.new
      puts choice.value(7, count: 2)
      puts choice.value(9, label: "orders", count: 3)
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Keyword defaults see prior defaults and instance state
    Given the Ruby source is:
      """
      class Choice
        def initialize; @count = 0; end
        def next_value; @count += 1; end
        def value(first = next_value, count: next_value, total: first + count); total; end
        def count; @count; end
      end
      choice = Choice.new
      puts choice.value
      puts choice.value(10, count: 20, total: 30)
      puts choice.count
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Explicit nil keywords do not evaluate their defaults
    Given the Ruby source is:
      """
      class Choice
        def value(label: puts("default")); label; end
      end
      choice = Choice.new
      puts choice.value(label: nil) == nil
      puts choice.value == nil
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Positional hashes differ from keyword arguments
    Given the Ruby source is:
      """
      class Choice
        def value(options = {count: 0}, count: 7); "#{options[:count]}:#{count}"; end
      end
      choice = Choice.new
      puts choice.value({count: 3})
      puts choice.value(count: 3)
      begin
        choice.value({count: 3}, unknown: 4)
      rescue ArgumentError => error
        puts error.message
      end
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Methods without keyword parameters receive nonempty keywords as a positional hash
    Given the Ruby source is:
      """
      class Choice
        def value(options); options[:count]; end
      end
      puts Choice.new.value(count: 7)
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Empty double splats contribute no positional hash
    Given the Ruby source is:
      """
      class Choice
        def value(*values); values.length; end
      end
      empty = {}
      puts Choice.new.value(**empty)
      puts Choice.new.value(empty)
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Double splats copy keyword values before later mutations
    Given the Ruby source is:
      """
      class Choice
        def value(first:, second:); "#{first}:#{second}"; end
      end
      options = {first: 1}
      puts Choice.new.value(**options, second: options[:first] = 9)
      puts options[:first]
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Duplicate keyword values run their effects and the last value wins
    Given the Ruby source is:
      """
      class Choice
        def value(count:); count; end
      end
      trace = "A"
      options = {count: trace << "B"}
      puts Choice.new.value(**options, count: trace << "C")
      puts trace
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Keyword rest creates independent storage in insertion order
    Given the Ruby source is:
      """
      class Choice
        def value(required:, **options); options; end
      end
      source = {required: 1, first: "A", second: 2}
      result = Choice.new.value(**source)
      result[:first] << "!"
      result[:second] = 7
      keys = result.keys
      puts keys[0]
      puts keys[1]
      puts source[:first]
      puts source[:second]
      puts source.key?(:required)
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Missing required keywords are checked before defaults and body
    Given the Ruby source is:
      """
      class Choice
        def value(number = puts("default"), first:, second:); puts "body"; end
      end
      begin
        Choice.new.value
      rescue ArgumentError => error
        puts error.message
      end
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Unknown keywords preserve their input order in the error message
    Given the Ruby source is:
      """
      class Choice
        def value(count: 7); count; end
      end
      begin
        Choice.new.value(third: 3, second: 2)
      rescue ArgumentError => error
        puts error.message
      end
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Uncaught missing keyword errors retain the method name frame
    Given the Ruby source is:
      """
      class Choice
        def value(count:); count; end
      end
      Choice.new.value
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Invalid double splat types raise before entering the method
    Given the Ruby source is:
      """
      class Choice
        def value(**options); puts "body"; end
      end
      begin
        Choice.new.value(**1)
      rescue TypeError => error
        puts error.message
      end
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Required keywords count as one argument for wrong positional arity
    Given the Ruby source is:
      """
      class Choice
        def value(first, count:); first; end
      end
      begin
        Choice.new.value(1, 2)
      rescue ArgumentError => error
        puts error.message
      end
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Bare super forwards changed positional keyword and keyword rest values
    Given the Ruby source is:
      """
      class Base
        def value(number, count:, **options); "#{number}:#{count}:#{options[:extra]}"; end
      end
      class Child < Base
        def value(number = 1, count: 2, **options)
          number += 1
          count += 1
          options[:extra] = 7
          super
        end
      end
      puts Child.new.value(extra: 3)
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Keyword calls with literal blocks keep the callers lexical scope
    Given the Ruby source is:
      """
      class Choice
        def value(number = 7, count: 2); yield(number + count); end
      end
      offset = 10
      puts Choice.new.value(count: 3) { |number| number + offset }
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Named block parameters can call their supplied literal block
    Given the Ruby source is:
      """
      class Choice
        def value(number = 7, &callback); callback.call(number); end
      end
      offset = 10
      puts Choice.new.value { |number| number + offset }
      puts Choice.new.value(9) { |number| number + offset }
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Missing block parameters are nil and guarded calls remain safe
    Given the Ruby source is:
      """
      class Choice
        def value(&callback)
          if callback
            callback.call
          else
            "no callback"
          end
        end
      end
      choice = Choice.new
      puts choice.value
      puts choice.value { "called" }
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Missing block calls raise Ruby NoMethodError
    Given the Ruby source is:
      """
      class Choice
        def value(&callback); callback.call; end
      end
      begin
        Choice.new.value
      rescue NoMethodError => error
        puts error.message
      end
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Uncaught missing block calls preserve source snippets and frames
    Given the Ruby source is:
      """
      class Choice
        def value(&callback); callback.call; end
      end
      Choice.new.value
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Explicit block forwarding preserves caller captures self and next values
    Given the Ruby source is:
      """
      class Relay
        def value(number, &callback); callback.call(number); end
      end
      class Choice
        def initialize; @offset = 10; end
        def value(relay, &callback); relay.value(7, &callback); end
        def run(relay)
          last = 0
          result = value(relay) { |number| last = number; next number + @offset }
          puts last
          result
        end
      end
      puts Choice.new.run(Relay.new)
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: A forwarded block break leaves its original receiving method
    Given the Ruby source is:
      """
      class Relay
        def value(&callback); callback.call; puts "wrong relay"; end
      end
      class Choice
        def value(other, &callback); other.value(&callback); puts "wrong receiver"; end
      end
      puts Choice.new.value(Relay.new) { break "found" }
      puts "after"
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: A forwarded block return leaves its lexical defining method through ensure
    Given the Ruby source is:
      """
      class Relay
        def value(&callback)
          callback.call
        ensure
          puts "relay cleanup"
        end
      end
      class Choice
        def run(other)
          other.value { return 7 }
          0
        ensure
          puts "caller cleanup"
        end
      end
      puts Choice.new.run(Relay.new)
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Block call splats preserve the first value and later argument effects
    Given the Ruby source is:
      """
      class Choice
        def value(values, text, &callback); callback.call(*values, text << "!"); end
      end
      values = [7, 9]
      text = "A"
      puts Choice.new.value(values, text) { |number| number + 1 }
      puts text
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Yield splats support positional and keyword payloads
    Given the Ruby source is:
      """
      class Choice
        def value(values, options); yield(*values, **options); end
      end
      puts Choice.new.value([7, 9], {extra: 3}) { |number| number + 1 }
      puts Choice.new.value([], {extra: 3}) { |options| options[:extra] }
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Explicit nil block forwarding does not forward the current block
    Given the Ruby source is:
      """
      class Relay
        def value(&callback); callback == nil; end
      end
      class Choice
        def value(other, &callback); other.value(&nil); end
      end
      puts Choice.new.value(Relay.new) { "unused" }
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Bare super and explicit super arguments forward the current literal block
    Given the Ruby source is:
      """
      class Base
        def value(number = 3, &callback); callback.call(number); end
      end
      class Child < Base
        def value(number = 7, &callback); number += 1; super; end
      end
      class Other < Base
        def value(number = 10, &callback); super(number + 1); end
      end
      puts Child.new.value { |number| number + 10 }
      puts Other.new.value { |number| number + 10 }
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Calling an outer block from an inner block uses the original environment
    Given the Ruby source is:
      """
      class Choice
        def value(other, &callback); other.value { callback.call(7) }; end
      end
      class Relay
        def value; yield; end
      end
      offset = 10
      puts Choice.new.value(Relay.new) { |number| number + offset }
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Constructors accept keyword defaults and named blocks
    Given the Ruby source is:
      """
      class Choice
        def initialize(number = 7, label: "quote", &callback)
          @label = label
          @number = callback.call(number)
        ensure
          puts "initialized"
        end
        def value; "#{@label}:#{@number}"; end
      end
      choice = Choice.new(label: "order") { |number| number + 10 }
      puts choice.value
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: A constructor block break overrides the constructed object result
    Given the Ruby source is:
      """
      class Choice
        def initialize(&callback)
          callback.call
          puts "wrong"
        ensure
          puts "initialized"
        end
      end
      puts Choice.new { break 7 }
      puts "after"
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Ordinary initializer returns still produce the constructed object
    Given the Ruby source is:
      """
      class Choice
        def initialize(&callback); @value = callback.call; return 99; end
        def value; @value; end
      end
      puts Choice.new { 7 }.value
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: A plain yield without a block raises LocalJumpError
    Given the Ruby source is:
      """
      class Choice
        def value; yield; end
      end
      begin
        Choice.new.value
      rescue LocalJumpError => error
        puts error.message
      end
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Block conversion effects run after ordinary arguments and before defaults
    Given the Ruby source is:
      """
      class Choice
        def value(number = puts("default"), &callback); callback == nil; end
      end
      trace = "A"
      puts Choice.new.value(trace << "1", &(trace << "2"; nil))
      puts trace
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Explicit super nil blocks suppress the inherited block
    Given the Ruby source is:
      """
      class Base
        def value(&callback); callback == nil; end
      end
      class Child < Base
        def value(&callback); super(&nil); end
      end
      puts Child.new.value { "ignored" }
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Explicit super blocks replace the inherited literal block
    Given the Ruby source is:
      """
      class Base
        def value(number = 3, &callback); callback.call(number); end
      end
      class Child < Base
        def value(&callback); super { |number| number + 10 }; end
      end
      puts Child.new.value { 99 }
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: A forwarded constructor block preserves its original break target
    Given the Ruby source is:
      """
      class Item
        def initialize(&callback); @value = callback.call; end
        def value; @value; end
      end
      class Choice
        def value(&callback); Item.new(&callback).value; puts "wrong"; end
      end
      puts Choice.new.value { break 7 }
      puts "after"
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Named constructor blocks can be forwarded through super
    Given the Ruby source is:
      """
      class Base
        def initialize(number = 3, &callback); @value = callback.call(number); end
        def value; @value; end
      end
      class Child < Base
        def initialize(number = 7, &callback); super(number + 1, &callback); end
      end
      puts Child.new { |number| number + 10 }.value
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Integer keys survive keyword rest and bare super
    Given the Ruby source is:
      """
      class Base
        def value(**options); options[7]; end
      end
      class Child < Base
        def value(**options); super; end
      end
      puts Child.new.value(**{7 => "seven"})
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: A block can receive an array as its sole argument
    Given the Ruby source is:
      """
      class Choice
        def value(&callback); callback.call([7, 9]); end
      end
      puts Choice.new.value { |values| values[1] }
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Invalid keyword splats stop later arguments and callee effects
    Given the Ruby source is:
      """
      class Choice
        def value(number = puts("wrong default"), **options); puts "wrong body"; end
      end
      trace = "A"
      begin
        Choice.new.value(**7, extra: trace << "wrong")
      rescue TypeError => error
        puts error.message
      end
      puts trace
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby
