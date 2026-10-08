# language: en
Feature: Track realistic programs and their current compiler blockers
  Scenario: Invoice totals and payments preserve shared line-item state
    Given I use the example "workloads/invoice.rb"
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby
    And CRuby prints the reference output:
      """
      Ada: 2 x Ruby book, 3000 cents, unpaid
      payment below total
      Ada: 2 x Ruby book, 3000 cents, unpaid
      payment received
      Ada: 3 x Ruby book, 4500 cents, paid
      """

  Scenario: Shipping policies inherit construction and use super
    Given I use the example "workloads/shipping.rb"
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby
    And CRuby prints the reference output:
      """
      standard:5200
      express:5700
      """

  @unsupported_examples
  Scenario: Log summaries need a range policy for input-dependent counters
    Given I use the example "workloads/log_summary.rb"
    And standard input is:
      """
      ok
      error
      ok
      """
    When I emit a Rust project
    Then the diagnostic has code "E_INTEGER_RANGE" at line 7
    And no Rust project was created
    And CRuby prints the reference output:
      """
      successful:2 failed:1
      """

  @unsupported_examples
  Scenario: Log summaries handle EOF without reading a line
    Given I use the example "workloads/log_summary.rb"
    When I emit a Rust project
    Then the diagnostic has code "E_INTEGER_RANGE" at line 7
    And no Rust project was created
    And CRuby prints the reference output:
      """
      successful:0 failed:0
      """

  @unsupported_examples
  Scenario: Shopping-cart totals need arrays and Symbol-to-Proc aggregation
    Given I use the example "workloads/shopping_cart.rb"
    When I emit a Rust project
    Then the diagnostic has code "E_UNSUPPORTED" at line 16
    And no Rust project was created
    And CRuby prints the reference output:
      """
      total:4900 cents
      """

  @unsupported_examples
  Scenario Outline: Notification configuration needs joins of different object handles
    Given I use the example "workloads/notification.rb"
    And standard input is:
      """
      <channel>
      """
    When I emit a Rust project
    Then the diagnostic has code "E_UNSUPPORTED" at line 25
    And no Rust project was created
    And CRuby prints the reference output:
      """
      <message>
      """

    Examples:
      | channel | message   |
      | email   | email:Ada |
      | sms     | sms:Ada   |

  @unsupported_examples
  Scenario: Class definition registries need class methods and load-time state
    Given I use the example "workloads/class_definitions.rb"
    When I emit a Rust project
    Then the diagnostic has code "E_UNSUPPORTED" at line 4
    And no Rust project was created
    And CRuby prints the reference output:
      """
      true
      """

  @unsupported_examples
  Scenario: Guarded unit pricing needs predicate narrowing
    Given I use the example "workloads/unit_pricing.rb"
    When I emit a Rust project
    Then the diagnostic has code "E_UNSUPPORTED" at line 11
    And no Rust project was created
    And CRuby prints the reference output:
      """
      3333
      quantity must be at least 1
      """
