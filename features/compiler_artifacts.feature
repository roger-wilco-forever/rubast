# language: en
Feature: Persistent binaries and inspectable compiler artifacts
  Scenario Outline: Build a standalone binary without executing the program
    Given the Ruby source is:
      """
      require_relative "settings"
      print "Customer: "
      name = gets&.chomp
      puts "#{PREFIX}#{name}"
      """
    And the Ruby file "settings.rb" is:
      """
      PREFIX = "Hello, "
      """
    And standard input is:
      """
      Zoë
      """
    When I record CRuby execution
    And I build a persistent binary in "<profile>" mode
    Then the binary was built without running it
    When I remove the Ruby source files
    And I run the persistent binary
    Then stdout, stderr, and exit status match CRuby

    Examples:
      | profile |
      | debug   |
      | release |

  Scenario: Retain a release project that builds independently
    Given I use the example "greeter.rb"
    When I build a persistent binary in "release" mode retaining its project
    Then the binary was built without running it
    And the retained project uses the "release" profile
    And the emitted source map refers to Ruby source
    When I build and run the emitted project
    Then stdout, stderr, and exit status match CRuby

  Scenario: A retained run keeps its original execution result
    Given the Ruby source is:
      """
      puts "before"
      raise "failed"
      """
    When I run Rubast in release mode retaining its project
    Then stdout, stderr, and exit status match CRuby
    And the retained project uses the "release" profile

  Scenario Outline: Preserve occupied binary destinations
    Given I use the example "greeter.rb"
    And the binary destination is an existing "<kind>"
    When I build a persistent binary in "debug" mode
    Then the diagnostic has code "E_OUTPUT" at line 1
    And the binary destination is unchanged

    Examples:
      | kind            |
      | file            |
      | directory       |
      | dangling link   |

  Scenario: Reject a binary inside its retained project before writing
    Given I use the example "greeter.rb"
    And the binary destination is inside the retained project
    When I build a persistent binary in "debug" mode retaining its project
    Then the diagnostic has code "E_OUTPUT" at line 1
    And no Rust project was created

  Scenario: Reject overlapping destinations through a directory alias
    Given I use the example "greeter.rb"
    And the binary destination overlaps the retained project through a directory alias
    When I build a persistent binary in "debug" mode retaining its project
    Then the diagnostic has code "E_OUTPUT" at line 1
    And the aliased output directory is unchanged
    And no binary was created

  Scenario: Report a binary destination filesystem error
    Given I use the example "greeter.rb"
    And the binary destination has a file as its parent
    When I build a persistent binary in "debug" mode
    Then the diagnostic has code "E_OUTPUT" at line 1
    And the binary parent file is unchanged

  Scenario: Preserve an occupied retained project
    Given I use the example "greeter.rb"
    And the output directory contains an existing file
    When I build a persistent binary in "debug" mode retaining its project
    Then the diagnostic has code "E_OUTPUT" at line 1
    And the existing output file is unchanged
    And no binary was created

  Scenario: Source diagnostics precede artifact creation
    Given the Ruby source is:
      """
      eval("1")
      """
    When I build a persistent binary in "debug" mode retaining its project
    Then the diagnostic has code "E_UNSUPPORTED" at line 1
    And no Rust project was created
    And no binary was created

  Scenario: Missing Cargo is a build diagnostic and keeps requested artifacts
    Given I use the example "greeter.rb"
    And Cargo is unavailable
    When I build a persistent binary in "debug" mode retaining its project
    Then the diagnostic has code "E_BUILD" at line 1
    And the retained project contains compiler artifacts
    And no binary was created

  Scenario Outline: Inspect IR without invoking Cargo or executing Ruby
    Given the Ruby source is:
      """
      puts "not executed"
      """
    And Cargo is unavailable
    When I dump "<stage>" IR
    Then the IR dump has stage "<stage>" and node "<node>"
    And the IR dump identifies Ruby line 1

    Examples:
      | stage      | node    |
      | normalized | Call    |
      | semantic   | Builtin |

  Scenario: Normalized IR remains available for semantically unsupported code
    Given the Ruby source is:
      """
      eval("1")
      """
    When I dump "normalized" IR
    Then the IR dump has stage "normalized" and node "Call"
    When I dump "semantic" IR
    Then the diagnostic has code "E_UNSUPPORTED" at line 1

  Scenario: Semantic IR preserves cyclic object references
    Given the Ruby source is:
      """
      class Link
        attr_accessor :other
      end
      link = Link.new
      link.other = link
      puts "ready"
      """
    When I dump "semantic" IR
    Then the IR dump has stage "semantic" and node "ObjectType"
    And the IR dump contains valid shared references
    And the IR dump retains an object cycle

  Scenario Outline: Reject invalid artifact command usage
    When I invoke Rubast with "<arguments>"
    Then Rubast reports a usage error

    Examples:
      | arguments                                       |
      | build example.rb                                |
      | build example.rb -o out --stage normalized       |
      | build example.rb -o out --keep-project           |
      | dump-ir example.rb --stage unknown               |
      | dump-ir example.rb -o out                        |
      | dump-ir example.rb --release                     |
      | run example.rb --stage semantic                  |
      | emit-rust example.rb -o out --release            |
      | emit-rust example.rb -o out --keep-project dir   |
