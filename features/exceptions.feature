Feature: Structured Ruby exceptions

  Scenario: Raise is rescued with its message
    Given the Ruby source is:
      """
      begin
        raise "failed"
      rescue => error
        puts error.message
      end
      puts "after"
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Explicit classes select the first matching rescue
    Given the Ruby source is:
      """
      begin
        raise ArgumentError, "invalid"
      rescue RuntimeError
        puts "wrong"
      rescue TypeError, ArgumentError => error
        puts error.message
      ensure
        puts "cleanup"
      end
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Rescue superclass catches its descendants
    Given the Ruby source is:
      """
      begin
        raise FrozenError, "frozen"
      rescue RuntimeError => error
        puts error.to_s
      end
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Else runs only after normal body completion and sets the result
    Given the Ruby source is:
      """
      value = begin
        puts "body"
        1
      rescue
        2
      else
        puts "else"
        3
      ensure
        puts "ensure"
        4
      end
      puts value
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Exceptions in else bypass the same rescue and still run ensure
    Given the Ruby source is:
      """
      begin
        begin
          puts "body"
        rescue
          puts "wrong"
        else
          raise "else"
        ensure
          puts "ensure"
        end
      rescue => error
        puts error.message
      end
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Nested reraising preserves the original exception
    Given the Ruby source is:
      """
      begin
        begin
          raise "first"
        rescue => error
          puts error.message
          raise
        ensure
          puts "inner ensure"
        end
      rescue => error
        puts error.message
      end
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Ensure returns the saved body result after mutation
    Given the Ruby source is:
      """
      text = "A"
      result = begin
        text
      ensure
        text << "!"
      end
      puts result
      puts text
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Ensure executes on ordinary method return
    Given the Ruby source is:
      """
      class Worker
        def run
          begin
            return 7
          ensure
            puts "cleanup"
          end
        end
      end
      puts Worker.new.run
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Ensure return overrides an earlier return
    Given the Ruby source is:
      """
      class Worker
        def run
          begin
            return 7
          ensure
            return 9
          end
        end
      end
      puts Worker.new.run
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Ensure exception overrides a method return
    Given the Ruby source is:
      """
      class Worker
        def run
          begin
            return 7
          ensure
            raise "cleanup failed"
          end
        end
      end
      begin
        puts Worker.new.run
      rescue => error
        puts error.message
      end
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Ensure return suppresses the pending exception
    Given the Ruby source is:
      """
      class Worker
        def run
          begin
            raise "ignored"
          ensure
            return 9
          end
        end
      end
      puts Worker.new.run
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Nested ensures run inside out on nonlocal return
    Given the Ruby source is:
      """
      class Worker
        def visit
          begin
            yield
          ensure
            puts "callee cleanup"
          end
        end
        def run
          begin
            visit do
              begin
                return 7
              ensure
                puts "block cleanup"
              end
            end
          ensure
            puts "caller cleanup"
          end
        end
      end
      puts Worker.new.run
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Loop break and next run ensure before reaching their targets
    Given the Ruby source is:
      """
      index = 0
      while index < 3
        index += 1
        begin
          next if index == 1
          break 7
        ensure
          puts "cleanup:#{index}"
        end
      end
      puts index
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Block next returns its value after ensure and continues
    Given the Ruby source is:
      """
      values = [1, 2].map do |value|
        begin
          next value + 10
        ensure
          puts "cleanup:#{value}"
        end
      end
      puts values[0]
      puts values[1]
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Block break crosses an intervening ensure
    Given the Ruby source is:
      """
      class Worker
        def visit
          begin
            yield
          ensure
            puts "cleanup"
          end
          "wrong"
        end
      end
      puts Worker.new.visit { break "found" }
      puts "after"
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: An inline method return does not leave an outer protected body
    Given the Ruby source is:
      """
      class Worker
        def run
          return "callee"
          yield
        end
      end
      begin
        puts Worker.new.run { puts "unused" }
        puts "body continues"
      ensure
        puts "outer cleanup"
      end
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Exceptions propagate across ordinary methods
    Given the Ruby source is:
      """
      class Worker
        def fail; raise "failed"; end
        def run; fail; puts "wrong"; end
      end
      begin
        Worker.new.run
      rescue => error
        puts error.message
      end
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Rescue sees writes made before an exception
    Given the Ruby source is:
      """
      value = 0
      begin
        value = 7
        raise "failed"
      rescue
        puts value
      end
      puts value
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Field writes survive an exception in a called method
    Given the Ruby source is:
      """
      class Worker
        def initialize; @value = 0; end
        def run; @value = 7; raise "failed"; end
        def value; @value; end
      end
      worker = Worker.new
      begin
        worker.run
      rescue
        puts worker.value
      end
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Division by zero is a catchable runtime exception
    Given the Ruby source is:
      """
      begin
        puts 7 / 0
      rescue ZeroDivisionError => error
        puts error.message
      ensure
        puts "cleanup"
      end
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Modulo by zero is a catchable runtime exception
    Given the Ruby source is:
      """
      begin
        puts 7 % 0
      rescue ZeroDivisionError => error
        puts error.message
      end
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Frozen mutation is caught without changing aliased bytes
    Given the Ruby source is:
      """
      # frozen_string_literal: true
      text = "A"
      alias_text = text
      begin
        text << "!"
      rescue FrozenError => error
        puts error.message
      end
      puts alias_text
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Invalid negative array assignment is caught without mutation
    Given the Ruby source is:
      """
      values = [1]
      begin
        values[-2] = 7
      rescue IndexError => error
        puts error.message
      end
      puts values[0]
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Retry reruns the protected body and ensure runs after completion
    Given the Ruby source is:
      """
      attempt = 0
      value = begin
        attempt += 1
        raise "retry" if attempt < 2
        7
      rescue
        puts "retrying"
        retry
      ensure
        puts "cleanup:#{attempt}"
      end
      puts value
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Retry from a nested begin retains its rescue target
    Given the Ruby source is:
      """
      attempt = 0
      begin
        attempt += 1
        raise "retry" if attempt < 2
      rescue
        begin
          puts "retrying"
          retry
        ensure
          puts "retry cleanup"
        end
      ensure
        puts "outer cleanup"
      end
      puts attempt
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Uncaught raise retains its Ruby location and exit status
    Given the Ruby source is:
      """
      raise "failed"
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Uncaught method exceptions include Ruby call frames
    Given the Ruby source is:
      """
      class Worker
        def fail; raise "failed"; end
        def run; fail; end
      end
      Worker.new.run
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Uncaught division retains the built in frame
    Given the Ruby source is:
      """
      puts 7 / 0
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Uncaught block errors include iterator frames
    Given the Ruby source is:
      """
      [1].each { raise "failed" }
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Uncaught times errors include the pinned numeric frame
    Given the Ruby source is:
      """
      2.times { raise "failed" }
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Uncaught yield errors include lexical and callee frames
    Given the Ruby source is:
      """
      class Worker
        def run; yield; end
      end
      Worker.new.run { raise "failed" }
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Uncaught replacement errors report their cause
    Given the Ruby source is:
      """
      begin
        raise "first"
      rescue
        raise "second"
      end
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Exception objects can be constructed and raised
    Given the Ruby source is:
      """
      error = ArgumentError.new("invalid")
      begin
        raise error
      rescue => rescued
        puts rescued.message
      end
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Method body rescue else and ensure need no explicit begin
    Given the Ruby source is:
      """
      class Worker
        def run
          raise "failed"
        rescue => error
          error.message
        else
          "wrong"
        ensure
          puts "cleanup"
        end
      end
      puts Worker.new.run
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Rescue modifier returns its handler value
    Given the Ruby source is:
      """
      value = raise("failed") rescue "recovered"
      puts value
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Bare raise without an active exception matches the uncaught Ruby format
    Given the Ruby source is:
      """
      raise
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Multiline error messages retain Ruby formatting
    Given the Ruby source is:
      """
      raise "first\nsecond\n"
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Exception message aliases share mutations
    Given the Ruby source is:
      """
      text = "first"
      error = RuntimeError.new(text)
      error.message << "!"
      puts text
      begin
        raise error
      rescue => rescued
        puts rescued.message
      end
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Frozen exception messages keep their frozen flag
    Given the Ruby source is:
      """
      # frozen_string_literal: true
      error = RuntimeError.new("first")
      begin
        error.message << "!"
      rescue FrozenError => caught
        puts caught.message
      end
      puts error.message
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Frozen error inspection preserves Unicode and escapes
    Given the Ruby source is:
      """
      # frozen_string_literal: true
      text = "Zoë\u0007\u0378\n\#{name}"
      begin
        text.replace("changed")
      rescue => error
        puts error.message
      end
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Repeated raises preserve the first backtrace
    Given the Ruby source is:
      """
      error = RuntimeError.new("first")
      begin
        raise error
      rescue
        puts "caught"
      end
      raise error
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Bare raise in a helper reraises the active exception
    Given the Ruby source is:
      """
      class Worker
        def fail; raise; end
      end
      begin
        raise ArgumentError, "first"
      rescue
        Worker.new.fail
      end
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Cause chains cannot become cyclic when an earlier error is raised again
    Given the Ruby source is:
      """
      first = RuntimeError.new("first")
      begin
        begin
          raise first
        rescue
          raise "second"
        end
      rescue
        raise first
      end
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Implicit block rescue and ensure preserve each map result
    Given the Ruby source is:
      """
      values = [0, 1].map do |value|
        10 / value
      rescue ZeroDivisionError
        7
      ensure
        puts "cleanup:#{value}"
      end
      puts values[0]
      puts values[1]
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Ensure mutates fields after the return value was evaluated
    Given the Ruby source is:
      """
      class Worker
        def initialize; @value = 0; end
        def run
          begin
            @value = 7
            return @value
          ensure
            @value = 9
          end
        end
        def value; @value; end
      end
      worker = Worker.new
      puts worker.run
      puts worker.value
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Ensure break overrides a pending exception
    Given the Ruby source is:
      """
      value = while true
        begin
          raise "ignored"
        ensure
          break 7
        end
      end
      puts value
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Ensure next overrides a pending block break
    Given the Ruby source is:
      """
      values = [1, 2].map do |value|
        begin
          break "ignored"
        ensure
          next value + 10
        end
      end
      puts values[0]
      puts values[1]
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Ignored and empty blocks discard checked exception effects
    Given the Ruby source is:
      """
      class Worker; def run; 7; end; end
      last = 0
      puts Worker.new.run { last = 9; raise "ignored" }
      [].each { last = 8; raise "empty" }
      puts last
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Exceptions in nested iterator blocks have the original Ruby frames
    Given the Ruby source is:
      """
      inner = [2]
      [1].each { inner.each { raise "failed" } }
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Reraising from ensure preserves the pending error
    Given the Ruby source is:
      """
      begin
        raise ArgumentError, "first"
      ensure
        puts "cleanup"
        raise
      end
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Rescue does not catch an exception raised by its ensure
    Given the Ruby source is:
      """
      begin
        begin
          raise "first"
        rescue
          puts "rescued"
        ensure
          raise ArgumentError, "cleanup"
        end
      rescue ArgumentError => error
        puts error.message
      end
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Raise argument side effects precede the exception
    Given the Ruby source is:
      """
      trace = "A"
      begin
        raise(trace << "!")
      rescue => error
        puts error.message
      end
      puts trace
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: An argument exception supersedes frozen receiver mutation
    Given the Ruby source is:
      """
      # frozen_string_literal: true
      text = "A"
      begin
        text.concat(begin; raise ArgumentError, "argument"; "!"; end)
      rescue ArgumentError => error
        puts error.message
      end
      puts text
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Error paths and rescue join shared array slot state
    Given the Ruby source is:
      """
      values = [1]
      begin
        values[0] = 7
        raise "failed"
      rescue
        values[0] = 9
      end
      puts values[0]
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Retry inside an iterator cannot target a rescue outside its block
    Given the Ruby source is:
      """
      attempt = 0
      begin
        attempt += 1
        raise "retry" if attempt < 2
      rescue
        1.times { retry }
      ensure
        puts "cleanup:#{attempt}"
      end
      puts attempt
      """
    When I emit a Rust project
    Then the diagnostic has code "E_UNSUPPORTED" at line 6
    And no Rust project was created

  Scenario: Retry inside a yielded block cannot target a rescue outside its block
    Given the Ruby source is:
      """
      class Worker
        def run; yield; "wrong"; end
      end
      attempt = 0
      begin
        attempt += 1
        raise "retry" if attempt < 2
      rescue
        Worker.new.run { retry }
      ensure
        puts "cleanup:#{attempt}"
      end
      puts attempt
      """
    When I emit a Rust project
    Then the diagnostic has code "E_UNSUPPORTED" at line 9
    And no Rust project was created

  Scenario: A dynamically active rescue supplies bare raise to a lexical block
    Given the Ruby source is:
      """
      class Worker
        def run
          begin
            raise TypeError, "inner"
          rescue
            yield
          end
        end
      end
      begin
        raise ArgumentError, "outer"
      rescue
        Worker.new.run { raise }
      end
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: A yielding callee ensure cannot overwrite its callers local return scope
    Given the Ruby source is:
      """
      class Worker
        def run
          value = 3
          begin
            yield
          ensure
            value = 9
            puts value
          end
        end
      end
      class Caller
        def run(other)
          value = 7
          other.run { return value }
          0
        end
      end
      puts Caller.new.run(Worker.new)
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby


  Scenario: Initializer rescue and ensure retain initialized fields
    Given the Ruby source is:
      """
      class Worker
        def initialize
          @value = 1
          raise "failed"
        rescue
          @value = 7
        ensure
          puts "cleanup"
        end
        def value; @value; end
      end
      puts Worker.new.value
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Uncaught initializer errors keep the Class new frame
    Given the Ruby source is:
      """
      class Worker
        def initialize; raise "failed"; end
      end
      Worker.new
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Reject a nonexception raise argument
    Given the Ruby source is:
      """
      raise 1
      """
    When I emit a Rust project
    Then the diagnostic has code "E_UNSUPPORTED" at line 1
    And no Rust project was created

  Scenario: Reject explicit backtrace arguments
    Given the Ruby source is:
      """
      raise RuntimeError, "failed", []
      """
    When I emit a Rust project
    Then the diagnostic has code "E_UNSUPPORTED" at line 1
    And no Rust project was created

  Scenario: Reject unsupported exception APIs
    Given the Ruby source is:
      """
      RuntimeError.new("failed").backtrace
      """
    When I emit a Rust project
    Then the diagnostic has code "E_UNSUPPORTED" at line 1
    And no Rust project was created

  Scenario: Reject dynamically selected rescue classes
    Given the Ruby source is:
      """
      kind = "invalid"
      begin
        raise "failed"
      rescue kind
        puts "caught"
      end
      """
    When I emit a Rust project
    Then the diagnostic has code "E_UNSUPPORTED" at line 4
    And no Rust project was created

  Scenario: Reject rescue splats
    Given the Ruby source is:
      """
      begin
        raise "failed"
      rescue *[StandardError]
        puts "caught"
      end
      """
    When I emit a Rust project
    Then the diagnostic has code "E_UNSUPPORTED" at line 3
    And no Rust project was created

  Scenario: Reject unbounded retry state growth
    Given the Ruby source is:
      """
      attempt = 0
      begin
        attempt += 1
        raise "failed"
      rescue
        retry
      end
      """
    When I emit a Rust project
    Then the diagnostic has code "E_UNSUPPORTED" at line 2
    And no Rust project was created

  Scenario: Reject custom exception subclasses
    Given the Ruby source is:
      """
      class Failure < StandardError; end
      raise Failure, "failed"
      """
    When I emit a Rust project
    Then the diagnostic has code "E_UNSUPPORTED" at line 1
    And no Rust project was created

  Scenario: The recoverable quote example builds independently
    Given I use the example "recoverable_quote.rb"
    When I emit a Rust project
    Then the emitted project contains its source and runtime
    When I build and run the emitted project
    Then stdout, stderr, and exit status match CRuby

  Scenario: Exception equality ignores different causes
    Given the Ruby source is:
      """
      first = RuntimeError.new("same")
      second = RuntimeError.new("same")
      errors = [first, second]
      2.times do |index|
        begin
          begin
            raise "cause:#{index}"
          rescue
            raise errors[index]
          end
        rescue
          puts "caught"
        end
      end
      puts first == second
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Inherited initializer errors retain their defining class
    Given the Ruby source is:
      """
      class Base
        def initialize; raise "failed"; end
      end
      class Child < Base; end
      Child.new
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Retry inside a blocks own rescue restarts that protected body
    Given the Ruby source is:
      """
      attempt = 0
      1.times do
        begin
          attempt += 1
          raise "failed" if attempt < 2
        rescue
          retry
        ensure
          puts "cleanup:#{attempt}"
        end
      end
      puts attempt
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Exception equality compares Ruby backtrace locations without source columns
    Given the Ruby source is:
      """
      first = RuntimeError.new("same")
      second = RuntimeError.new("same")
      begin; raise first; rescue; end; begin; raise(second); rescue; end
      puts first == second
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Multiline argument errors place source snippets after the complete message
    Given the Ruby source is:
      """
      raise ArgumentError, "first\nsecond"
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby
