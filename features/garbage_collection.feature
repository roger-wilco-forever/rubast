Feature: Reclamation preserves the supported Ruby object graph

  Scenario: Automatic collection preserves a bounded generated allocation batch
    Given I use the example "workloads/memory_batch.rb"
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby
    And CRuby prints the reference output:
      """
      19900
      true
      """

  Scenario: Locals constants and class state preserve mixed cyclic aliases
    Given the Ruby source is:
      """
      class Cell
        attr_accessor :links
        @saved = nil
        def self.save(value)
          @saved = value
        end
        def self.saved
          @saved
        end
      end
      cell = Cell.new
      links = [cell]
      values = { node: cell, links: links }
      cell.links = values
      Saved = cell
      Cell.save(cell)
      GC.start
      Cell.saved.links[:links].push(7)
      GC.start
      puts Saved.links[:links].length
      puts links[1]
      links[0].links[:node].links[:links][1] = 9
      puts cell.links[:links][1]
      puts GC.start.nil?
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Constructors argument snapshots receivers and return values remain roots
    Given the Ruby source is:
      """
      class Cell
        attr_reader :value
        def initialize(value)
          GC.start
          @value = value
        end
        def self.collect
          GC.start
          2
        end
        def combine(*rest, **options)
          GC.start
          puts @value[0]
          puts rest[0][0]
          puts rest[1]
          puts options[:extra][0]
          @value
        end
      end
      returned = Cell.new([7]).combine([8], Cell.collect, extra: [9])
      GC.start
      puts returned[0]
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Captured locals and lexical self survive collection during nested yield
    Given the Ruby source is:
      """
      class Producer
        def run
          GC.start
          yield
        end
      end
      class Consumer
        def initialize
          @values = [7]
        end
        def run(producer)
          captured = [8]
          producer.run do
            GC.start
            @values.push(captured[0])
          end
          GC.start
          @values
        end
      end
      result = Consumer.new.run(Producer.new)
      GC.start
      puts result[0]
      puts result[1]
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Pending return next and break results survive ensure collection
    Given the Ruby source is:
      """
      class Factory
        def returned
          1.times do
            begin
              return [7]
            ensure
              GC.start
            end
          end
        end
      end
      returned = Factory.new.returned
      mapped = [1, 2].map do |value|
        begin
          next [value]
        ensure
          GC.start
        end
      end
      broken = 1.times do
        begin
          break [9]
        ensure
          GC.start
        end
      end
      GC.start
      puts returned[0]
      puts mapped[0][0]
      puts mapped[1][0]
      puts broken[0]
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Rescue state and pending exceptions survive cleanup collection
    Given the Ruby source is:
      """
      values = [7]
      begin
        begin
          raise "first"
        rescue RuntimeError => error
          GC.start
          puts error.message
          values.push(8)
          raise "second"
        ensure
          GC.start
        end
      rescue RuntimeError => error
        GC.start
        puts error.message
        puts values[0]
        puts values[1]
      end
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Lexical user GC methods retain priority over the built-in namespace
    Given the Ruby source is:
      """
      module Outer
        class GC
          def self.start
            puts "user GC"
            7
          end
        end
        puts GC.start
        puts ::GC.start.nil?
      end
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Shared strings and frozen copied hash keys retain their state
    Given the Ruby source is:
      """
      text = "shared".dup
      values = [text]
      hash = { "name" => text }
      GC.start
      values[0] << "!"
      puts hash["name"]
      key = hash.keys[0]
      GC.start
      begin
        key << "!"
      rescue FrozenError => error
        puts error.message
      end
      puts hash[key]
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: An uncaught cause chain keeps its Ruby backtrace across collection
    Given the Ruby source is:
      """
      class Worker
        def run
          begin
            raise "first"
          rescue RuntimeError
            raise "second"
          ensure
            GC.start
          end
        end
      end
      Worker.new.run
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario Outline: Unsupported memory APIs retain located diagnostics
    Given the Ruby source is:
      """
      <source>
      """
    When I emit a Rust project
    Then the diagnostic has code "E_UNSUPPORTED" at line 1
    And no Rust project was created

    Examples:
      | source                              |
      | GC.start(full_mark: false)           |
      | GC.start(1)                         |
      | GC.start { puts "ignored" }         |
      | GC&.start                           |
      | GC.disable                          |
      | GC.stat                             |
      | ObjectSpace.define_finalizer(nil)    |
