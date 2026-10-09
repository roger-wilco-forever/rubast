# language: en
Feature: Preserve behavior in measured application workloads
  Scenario Outline: Sustained workloads match the Ruby reference
    Given I use the benchmark "<name>"
    And standard input is:
      """
      Ada λ
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

    Examples:
      | name              |
      | quote_requests    |
      | invoice_summaries |
      | receipt_labels    |

  Scenario: Interpolation creates independent mutable results from frozen strings
    Given the Ruby source is:
      """
      # frozen_string_literal: true
      name = "Zoë λ"
      result = "left:#{name}:#{name}:right"
      result << "!"
      puts result
      puts name
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Interpolation copies shared string bytes and converts supported scalars
    Given the Ruby source is:
      """
      name = "Ada"
      other = name
      result = "#{nil}|#{false}|#{true}|#{42}|#{:label}|#{name}|#{other}"
      name.replace("Zoë")
      result << "!"
      puts result
      puts name
      puts other
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby
