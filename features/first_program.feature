# language: en
Feature: First Ruby-to-Rust compilation slice
  To verify the path from Ruby source to an executable
  As a Rubast developer
  I want to run supported programs through Rubast

  Scenario: Print an integer
    Given the Ruby source is:
      """
      puts 42
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Execute an empty class definition
    Given the Ruby source is:
      """
      class Greeter; end
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Execute an empty module definition
    Given the Ruby source is:
      """
      module Greeter; end
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Preserve statement order and 64-bit integer boundaries
    Given the Ruby source is:
      """
      puts -9223372036854775808
      puts 9223372036854775807
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Reject an integer outside the current range
    Given the Ruby source is:
      """
      puts 9223372036854775808
      """
    When I run Rubast
    Then the diagnostic has code "E_INTEGER_RANGE" at line 1

  Scenario: Reject an unsupported block instead of silently dropping it
    Given the Ruby source is:
      """
      puts(42) { puts 99 }
      """
    When I run Rubast
    Then the diagnostic has code "E_UNSUPPORTED" at line 1

  Scenario: Preserve the Ruby location of a syntax error
    Given the Ruby source is:
      """
      puts(
      """
    When I run Rubast
    Then the diagnostic has code "E_PARSE" at line 1


  Scenario: Preserve string escapes and local reassignment
    Given the Ruby source is:
      """
      name = "Ada"
      name = "Zoë"
      puts "Hello, \"#{name}\"!\\"
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby
