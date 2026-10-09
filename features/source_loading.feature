Feature: Static Ruby source dependencies
  Dependencies execute in Ruby load order with their own file-local scope.

  Scenario: User instance methods named like loaders retain normal lookup
    Given the Ruby source is:
      """
      class UserLoader
        def require_relative(name); "relative:#{name}"; end
        def require(name); "require:#{name}"; end
        def load(name); "load:#{name}"; end
        def autoload(name); "autoload:#{name}"; end
        def run
          puts require_relative("custom")
          puts self.require("custom")
          puts load("custom")
          puts self.autoload("custom")
        end
      end
      UserLoader.new.run
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Extended and singleton loader names remain user methods in declaration bodies
    Given the Ruby source is:
      """
      module CustomPaths
        def require_relative(name); "relative:#{name}"; end
      end
      class UserLoader
        extend CustomPaths
        puts require_relative("body")
        def self.require(name); "require:#{name}"; end
        puts self.require("body")
      end
      puts UserLoader.require("caller")
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Module loader-like helpers resolve on their actual host
    Given the Ruby source is:
      """
      module CustomCalls
        def run; require_relative("custom"); end
      end
      class UserLoader
        include CustomCalls
        def require_relative(name); "host:#{name}"; end
      end
      puts UserLoader.new.run
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: A lexical constant named Kernel may refer to a user class
    Given the Ruby source is:
      """
      class CustomKernel
        def self.require(name); "custom:#{name}"; end
      end
      module CustomPaths
        Kernel = CustomKernel
        def self.run; Kernel.require("caller"); end
      end
      puts CustomPaths.run
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Explicit builtin loading remains rejected in an unused module method
    Given the Ruby source is:
      """
      module CustomPaths
        def unused
          Kernel.require_relative "missing"
        end
      end
      """
    When I emit a Rust project
    Then the diagnostic has code "E_LOAD" at line 3
    And no Rust project was created

  Scenario: The multi-file quote application retains its single-file behavior
    Given I use the example "workloads/multi_file_quote.rb"
    Then CRuby prints the reference output:
      """
      Ada: 1270
      1220
      550
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Relative files load once and return booleans in source order
    Given the Ruby file "lib/settings.rb" is:
      """
      puts "settings"
      value = 12
      LIMIT = value
      """
    And the Ruby source is:
      """
      value = 7
      puts "before"
      first = require_relative "lib/settings"
      puts first
      puts require_relative "lib/../lib/settings.rb"
      puts LIMIT
      puts value
      puts "after"
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Circular dependencies retain partial constant availability
    Given the Ruby file "lib/first.rb" is:
      """
      FIRST = 20
      puts "first"
      require_relative "second"
      puts SECOND
      """
    And the Ruby file "lib/second.rb" is:
      """
      puts "second"
      puts FIRST
      puts require_relative "first"
      SECOND = 30
      """
    And the Ruby source is:
      """
      puts require_relative "lib/first"
      puts require_relative "lib/second"
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Methods and constants retain defining file scopes
    Given the Ruby file "settings.rb" is:
      """
      module Shop
        RATE = 2
        module Pricing
          def total
            subtotal * RATE
          end
        end
      end
      """
    And the Ruby file "quote.rb" is:
      """
      require_relative "settings"
      class Shop::Quote
        include Shop::Pricing
        attr_accessor :subtotal
        def initialize(subtotal)
          @subtotal = subtotal
        end
      end
      """
    And the Ruby source is:
      """
      require_relative "quote"
      quote = Shop::Quote.new(15)
      puts quote.total
      quote.subtotal = 20
      puts quote.total
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Explicit require paths share the relative load registry
    Given the working directory is the source directory
    And the Ruby file "settings.rb" is:
      """
      puts "settings"
      LIMIT = 4
      """
    And the Ruby source is:
      """
      puts require "./settings"
      puts require_relative "settings.rb"
      puts require "./settings.rb"
      puts LIMIT
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario Outline: Required-file failures preserve Ruby frames and source locations
    Given the working directory is the source directory
    Given the Ruby file "inner.rb" is:
      """
      puts "inner"
      raise ArgumentError, "dependency failed"
      """
    And the Ruby file "outer.rb" is:
      """
      puts "outer"
      <load_inner>
      puts "unreachable"
      """
    And the Ruby source is:
      """
      puts "main"
      <load_outer>
      puts "unreachable"
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

    Examples:
      | load_inner               | load_outer               |
      | require_relative "inner" | require_relative "outer" |
      | require "./inner"        | require "./outer"        |

  Scenario: Explicit require frames also match CRuby without Bundler startup
    Given the working directory is the source directory
    And the program environment excludes Bundler startup
    And the Ruby file "inner.rb" is:
      """
      raise ArgumentError, "dependency failed"
      """
    And the Ruby source is:
      """
      require "./inner"
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Every dependency is validated before emission
    Given the Ruby file "invalid.rb" is:
      """
      class Broken
        def unused
          /unsupported/
        end
      end
      """
    And the Ruby source is:
      """
      puts "must not execute"
      require_relative "invalid"
      """
    When I emit a Rust project
    Then the diagnostic has code "E_UNSUPPORTED" at line 3
    And the diagnostic names Ruby file "invalid.rb"
    And no Rust project was created

  Scenario: Dependency parse errors name the dependency
    Given the Ruby file "invalid.rb" is:
      """
      value =
      """
    And the Ruby source is:
      """
      require_relative "invalid"
      """
    When I emit a Rust project
    Then the diagnostic has code "E_PARSE" at line 1
    And the diagnostic names Ruby file "invalid.rb"
    And no Rust project was created

  Scenario Outline: Dynamic paths and non-file-level loading are rejected
    Given the Ruby file "settings.rb" is:
      """
      LIMIT = 1
      """
    And the Ruby source is:
      """
      <source>
      """
    When I emit a Rust project
    Then the diagnostic has code "E_LOAD" at line <line>
    And no Rust project was created

    Examples:
      | source                                                     | line |
      | name = "settings"; require_relative name                   | 1    |
      | require_relative "#{gets}"                                | 1    |
      | if gets; require_relative "settings"; end                   | 1    |
      | 2.times { require_relative "settings" }                    | 1    |
      | class Host; def load; require_relative "settings"; end; end | 1    |
      | class Host; require_relative "settings"; end               | 1    |
      | begin; require_relative "settings"; rescue; end            | 1    |
      | require "json"                                             | 1    |
      | require_relative "settings", "extra"                      | 1    |
      | require_relative "settings" do; puts "block"; end         | 1    |

  Scenario: Missing static dependencies fail at their require site
    Given the Ruby source is:
      """
      puts "must not execute"
      require_relative "missing"
      """
    When I emit a Rust project
    Then the diagnostic has code "E_LOAD" at line 2
    And no Rust project was created

  Scenario: Absolute and symlink aliases identify the same loaded Ruby file
    Given the Ruby file "lib/settings.rb" is:
      """
      puts "settings"
      LIMIT = 8
      """
    And the file "alias.rb" links to "lib/settings.rb"
    And the Ruby source with absolute paths is:
      """
      puts require "<source_directory>/alias.rb"
      puts require_relative "lib/settings"
      puts require "<source_directory>/lib/settings.rb"
      puts LIMIT
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario Outline: File paths are normalized before Ruby extensions are resolved
    Given the Ruby file "library.rb" is:
      """
      VALUE = 11
      puts "library"
      """
    And the Ruby file ".rb" is:
      """
      VALUE = 33
      puts "hidden"
      """
    And the Ruby file ".rb.rb" is:
      """
      VALUE = 99
      puts "decoy"
      """
    And the Ruby source is:
      """
      puts require_relative "<path>"
      puts require_relative "<alias>"
      puts VALUE
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

    Examples:
      | path      | alias      |
      | library/. | library    |
      | library/  | library.rb |
      | .rb       | ./.rb      |

  Scenario: Relative paths use the requiring file's real directory
    Given the Ruby file "lib/settings.rb" is:
      """
      require_relative "nested/value"
      puts VALUE
      """
    And the Ruby file "lib/nested/value.rb" is:
      """
      VALUE = 11
      """
    And the file "alias.rb" links to "lib/settings.rb"
    And the Ruby source is:
      """
      require_relative "alias"
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: File-local block bindings and shared object effects remain isolated
    Given the Ruby file "first.rb" is:
      """
      values = [3, 4]
      total = 0
      values.each { |value| total = total + value }
      STATE = values
      puts total
      """
    And the Ruby file "second.rb" is:
      """
      values = [7, 8]
      total = 0
      values.each { |value| total = total + value }
      STATE[0] = total
      puts total
      """
    And the Ruby source is:
      """
      values = [1, 2]
      total = 100
      require_relative "first"
      require_relative "second"
      values.each { |value| total = total + value }
      puts total
      puts STATE[0]
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Dependencies preserve frozen string pragmas independently
    Given the Ruby file "settings.rb" is:
      """
      # frozen_string_literal: true
      TEXT = "constant"
      """
    And the Ruby source is:
      """
      # frozen_string_literal: false
      require_relative "settings"
      text = "mutable"
      text << "!"
      puts text
      begin
        TEXT << "!"
      rescue FrozenError => error
        puts error.message
      end
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Required-file syntax warnings appear once at load time
    Given the Ruby file "settings.rb" is:
      """
      values = { key: 1, key: 2 }
      puts values[:key]
      """
    And the Ruby source is:
      """
      require_relative "settings"
      require_relative "settings.rb"
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Emitted projects include all dependencies without requiring Ruby source files
    Given the Ruby file "settings.rb" is:
      """
      LIMIT = 42
      puts "settings"
      """
    And the Ruby source is:
      """
      require_relative "settings"
      puts LIMIT
      """
    When I emit a Rust project
    Then the emitted project contains its source and runtime
    When I record CRuby execution
    And I remove the Ruby source files
    And I build and run the emitted project
    Then stdout, stderr, and exit status match CRuby

  Scenario: Constants cannot be used before their dependency has loaded
    Given the Ruby file "settings.rb" is:
      """
      LIMIT = 1
      """
    And the Ruby source is:
      """
      puts LIMIT
      require_relative "settings"
      """
    When I emit a Rust project
    Then the diagnostic has code "E_UNSUPPORTED" at line 1
    And no Rust project was created

  Scenario: Constants introduced after a circular require remain unavailable inside it
    Given the Ruby file "first.rb" is:
      """
      require_relative "second"
      LATER = 1
      """
    And the Ruby file "second.rb" is:
      """
      require_relative "first"
      puts LATER
      """
    And the Ruby source is:
      """
      require_relative "first"
      """
    When I emit a Rust project
    Then the diagnostic has code "E_UNSUPPORTED" at line 2
    And the diagnostic names Ruby file "second.rb"
    And no Rust project was created

  Scenario: The command-line entry is not already a required feature
    Given the Ruby source is:
      """
      puts "entry"
      puts require_relative "example"
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario Outline: Unsupported loaders and native extensions fail before emission
    Given the Ruby source is:
      """
      <source>
      """
    When I emit a Rust project
    Then the diagnostic has code "E_LOAD" at line 1
    And no Rust project was created

    Examples:
      | source                             |
      | load "settings.rb"                 |
      | autoload :Settings, "settings.rb"   |
      | require_relative "extension.so"     |
      | Kernel.require_relative "settings" |
      | require_relative "a\0b"            |
