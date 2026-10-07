# language: en
Feature: Save an independently buildable Rust project
  Scenario Outline: Build and run a saved project
    Given I use the example "<example>"
    When I emit a Rust project
    Then the emitted project contains its source and runtime
    When I build and run the emitted project
    Then stdout, stderr, and exit status match CRuby
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

    Examples:
      | example       |
      | greeter.rb    |
      | hello_user.rb |

  Scenario: Preserve stdin in a saved project
    Given I use the example "hello_user.rb"
    And standard input is:
      """
      Zoë
      """
    When I emit a Rust project
    When I build and run the emitted project
    Then stdout, stderr, and exit status match CRuby

  Scenario: Emit into an existing empty directory without invoking Cargo
    Given I use the example "greeter.rb"
    And the output directory is empty
    And Cargo is unavailable
    When I emit a Rust project
    Then the emitted project contains its source and runtime

  Scenario: Emit and run an empty class
    Given the Ruby source is:
      """
      class Unsupported; end
      """
    When I emit a Rust project
    Then the emitted project contains its source and runtime
    When I build and run the emitted project
    Then stdout, stderr, and exit status match CRuby

  Scenario: Reject unsupported input without creating a project
    Given the Ruby source is:
      """
      module Unsupported; end
      """
    When I emit a Rust project
    Then the diagnostic has code "E_UNSUPPORTED" at line 1
    And no Rust project was created

  Scenario: Preserve existing destination files
    Given I use the example "greeter.rb"
    And the output directory contains an existing file
    When I emit a Rust project
    Then the diagnostic has code "E_OUTPUT" at line 1
    And the existing output file is unchanged

  Scenario: Report a destination filesystem error
    Given I use the example "greeter.rb"
    And the output path has a file as its parent
    When I emit a Rust project
    Then the diagnostic has code "E_OUTPUT" at line 1
    And the output parent file is unchanged

  Scenario Outline: Reject invalid command usage
    When I invoke Rubast with "<arguments>"
    Then Rubast reports a usage error

    Examples:
      | arguments                            |
      | emit-rust example.rb                 |
      | emit-rust example.rb -o               |
      | emit-rust example.rb -o out extra     |
      | run example.rb -o out                |
      | emit-rust example.rb --unknown        |
