# language: en
Feature: Greet a user from standard input
  A compiled program should accept input and interpolate it like CRuby.

  Scenario: Greet a user
    Given I use the example "hello_user.rb"
    And standard input is:
      """
      Ada
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Preserve Unicode input
    Given I use the example "hello_user.rb"
    And standard input is:
      """
      Zoë
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Handle end of input
    Given I use the example "hello_user.rb"
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Show the prompt before waiting for input
    Given I use the example "hello_user.rb"
    When I start Rubast interactively
    Then I see the prompt "What is your name?"
    When I enter "Ada"
    Then I see the greeting "Hello, Ada!"
