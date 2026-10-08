Feature: Visibility declaration values and constructor access
  Static declarations preserve their values and method access.

  Scenario: Single visibility names retain their original scalar type
    Given the Ruby source is:
      """
      class Choice
        def first; 7; end
        def second; 9; end
        puts(private(:first) == :first)
        puts(public("second") == "second")
      end
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Multiple visibility names retain original symbol and string values
    Given the Ruby source is:
      """
      class Choice
        def first; 7; end
        def second; 9; end
        names = private(:first, "second")
        puts names.length
        puts(names[0] == :first)
        puts(names[1] == "second")
      end
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Wrapped method declarations return the method symbol
    Given the Ruby source is:
      """
      class Choice
        name = private def value; 7; end
        puts(name == :value)
      end
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Class method visibility declarations return their class object
    Given the Ruby source is:
      """
      class Choice
        def self.value; 7; end
        klass = private_class_method(:value)
        puts klass == self
        klass = public_class_method("value")
        puts klass == self
        puts klass.value
      end
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Private native new remains callable through an implicit class receiver
    Given the Ruby source is:
      """
      class Choice
        attr_reader :value
        def initialize(value); @value = value; end
        private_class_method :new
        def self.build(value); new(value); end
      end
      puts Choice.build(7).value
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Private native new remains callable with a literal block inside its class method
    Given the Ruby source is:
      """
      class Choice
        attr_reader :value
        def initialize(value); @value = yield value; end
        private_class_method :new
        def self.build(value); new(value) { |number| number + 1 }; end
      end
      puts Choice.build(7).value
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Private native new rejects outside calls
    Given the Ruby source is:
      """
      class Choice
        private_class_method :new
      end
      Choice.new
      """
    When I emit a Rust project
    Then the diagnostic has code "E_UNSUPPORTED" at line 4
    And no Rust project was created

  Scenario: Private user new rejects outside calls
    Given the Ruby source is:
      """
      class Choice
        def self.new; 7; end
        private_class_method :new
      end
      Choice.new
      """
    When I emit a Rust project
    Then the diagnostic has code "E_UNSUPPORTED" at line 5
    And no Rust project was created
