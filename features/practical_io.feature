# language: en
Feature: Practical UTF-8 text I/O
  Scalar output, standard streams, and whole text files preserve Ruby observations.

  Scenario: Print scalars without adding separators or newlines
    Given the Ruby source is:
      """
      p(print("hé", 7, nil, false, :done))
      print("line\n", "tail")
      puts
      puts("a\n", nil, true)
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Warn goes to redirected stderr and adds only missing newlines
    Given the Ruby source is:
      """
      p(warn("hé\n", nil, 7, false, :done))
      p(warn)
      print("stdout")
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Scalar inspection preserves quotes, control characters, Unicode, and return identity
    Given the Ruby source is:
      """
      text = "hé\"\\\0\a\b\t\n\v\f\r\e\u0001\u007F\u0085\u2028"
      p(text)
      p(p(text) == text)
      p('\#{name} #$name #@name')
      p(:plain)
      p(:"name with space")
      p(:é)
      p(:"")
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: All arguments run before output and shared strings retain their identity
    Given the Ruby source is:
      """
      text = "first"
      print(text, text.replace("second"), puts("argument"))
      warn(text, text.replace("last"))
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: A raised argument prevents the outer output
    Given the Ruby source is:
      """
      begin
        print("wrong", raise("stop"))
      rescue RuntimeError => error
        warn(error.message)
      ensure
        puts "cleanup"
      end
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Nil output results keep loop bodies unreachable
    Given the Ruby source is:
      """
      count = 0
      while puts("predicate")
        count += 1
      end
      while print("next")
        count += 1
      end
      p(count)
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Scalar inspection reads runtime Unicode and frozen and mutable buffers
    Given the Ruby source is:
      """
      # frozen_string_literal: true
      p(STDIN.read)
      frozen = "fixed"
      text = frozen.dup
      text << "!"
      p(frozen)
      p(text)
      p("\u0378\uE000\u{1FFFE}\u{1FAE9}\u2029\u061C")
      """
    And standard input is:
      """
      Zoë 😀
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Standard streams can be passed through user methods
    Given the Ruby source is:
      """
      class Reporter
        def emit(stream, text)
          count = stream.write(text, "!")
          p(count)
          p(stream.flush == stream)
          stream.print("tail", nil)
          stream.puts("end\n", false)
        end
      end
      Reporter.new.emit(STDOUT, "hé")
      Reporter.new.emit(::STDERR, "warning")
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Standard stream globals retain the identity of their constant objects
    Given the Ruby source is:
      """
      p($stdin == STDIN)
      p($stdout == STDOUT)
      p($stderr == STDERR)
      $stdout.print("hé", nil)
      $stderr.puts("warning")
      puts $stdin.gets&.chomp
      """
    And standard input is:
      """
      Ada
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Gets and read share stdin and preserve Unicode and EOF
    Given the Ruby source is:
      """
      input = STDIN
      puts input.gets&.chomp
      puts gets&.chomp
      puts input.read
      p(input.gets.nil?)
      p(input.read == "")
      """
    And standard input is:
      """
      Zoë
      Ada
      last
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: An empty stream returns nil from gets and an empty string from read
    Given the Ruby source is:
      """
      p(STDIN.gets.nil?)
      p(STDIN.read == "")
      p(gets.nil?)
      p(STDIN.flush == STDIN)
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: A final input line without a newline is returned before EOF
    Given the Ruby source is:
      """
      puts STDIN.gets&.chomp
      p(STDIN.gets.nil?)
      p(STDIN.read == "")
      """
    And standard input without a final newline is:
      """
      Zoë
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Flush exposes an unterminated prompt before waiting for input
    Given the Ruby source is:
      """
      print "Name: "
      STDOUT.flush
      name = STDIN.gets&.chomp
      puts "Hello, #{name}!"
      """
    When I start Rubast interactively
    Then I see the unterminated prompt "Name: "
    When I enter "Ada"
    Then I see the greeting "Hello, Ada!"

  Scenario Outline: Wrong stream direction raises an IOError with Ruby frames
    Given the Ruby source is:
      """
      <operation>
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

    Examples:
      | operation             |
      | STDIN.write("wrong")  |
      | STDIN.print("wrong")  |
      | STDIN.puts("wrong")   |
      | STDOUT.read           |
      | STDERR.gets           |

  Scenario: Stream failures can be rescued and ensured inside methods
    Given the Ruby source is:
      """
      class Reporter
        def emit(stream)
          stream.write("wrong")
        rescue IOError => error
          warn(error.message)
          7
        ensure
          puts "cleanup"
        end
      end
      p(Reporter.new.emit(STDIN))
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Text files are read at execution time and writes truncate existing contents
    Given the working directory is the source directory
    And the Ruby file "input.txt" is:
      """
      hé\n
      """
    And the Ruby source is:
      """
      path = "report.txt"
      p(File.write(path, "old contents"))
      p(File.write(path, "Zoë\r\n"))
      text = File.read(path)
      p(text.bytesize)
      p(text.length)
      p(text == "Zoë\r\n")
      p(File.write(path, nil))
      p(File.read(path) == "")
      print(File.read("input.txt"))
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Absolute paths and file arguments retain evaluation order
    Given the Ruby source with absolute paths is:
      """
      class Report
        def path
          puts "path"
          "<source_directory>/report.txt"
        end
        def text
          puts "text"
          "hé"
        end
      end
      report = Report.new
      p(::File.write(report.path, report.text))
      puts ::File.read(report.path)
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario Outline: Filesystem and path failures preserve exception messages and frames
    Given the working directory is the source directory
    And the Ruby source is:
      """
      <operation>
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

    Examples:
      | operation                         |
      | File.read("missing.txt")          |
      | File.write("missing/report", "x") |
      | File.read(".")                    |
      | File.write(".", "x")             |
      | File.read("x\0y")                 |
      | File.write("x\0y", "x")           |
      | File.write("/dev/full", "x")      |

  Scenario: A larger write fails during writing rather than final buffer flush
    Given the Ruby source is:
      """
      text = "x"
      14.times { text = text + text }
      File.write("/dev/full", text)
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Failed file operations retain their cause through method and block cleanup
    Given the working directory is the source directory
    And the Ruby source is:
      """
      class Report
        def read
          [1].each do
            begin
              File.read("missing.txt")
            rescue SystemCallError
              raise "report failed"
            ensure
              warn "cleanup"
            end
          end
        end
      end
      Report.new.read
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Qualified aliases preserve stream identity and File dispatch
    Given the working directory is the source directory
    And the Ruby source is:
      """
      module Report
        OUTPUT = ::STDOUT
        STORAGE = ::File
      end
      p(Report::OUTPUT == STDOUT)
      p(Report::STORAGE.write("report.txt", :done))
      Report::OUTPUT.print(Report::STORAGE.read("report.txt"))
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Absolute errno rescue bypasses a lexical constant with the same name
    Given the working directory is the source directory
    And the Ruby source is:
      """
      module Report
        Errno = "local"
        def self.read
          File.read("missing.txt")
        rescue ::Errno::ENOENT => error
          puts error.message
        end
      end
      Report.read
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Changing text data after emission is observed by the standalone binary
    Given the working directory is the source directory
    And the Ruby file "input.txt" is:
      """
      original
      """
    And the Ruby source with absolute paths is:
      """
      path = "<source_directory>/input.txt"
      puts File.read(path)
      p(File.write("<source_directory>/report.txt", "Zoë"))
      """
    When I emit a Rust project
    Then the emitted project contains its source and runtime
    Given the Ruby file "input.txt" is:
      """
      changed
      """
    When I record CRuby execution
    And I remove the Ruby source files
    And I build and run the emitted project
    Then stdout, stderr, and exit status match CRuby

  Scenario: Export a receipt through a real file and stdout
    Given the working directory is the source directory
    And I use the example "workloads/text_report.rb"
    And standard input is:
      """
      Zoë
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Export a receipt with a fallback name at EOF
    Given the working directory is the source directory
    And I use the example "workloads/text_report.rb"
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: Specific errno rescue and SystemCallError rescue share ensure and cause handling
    Given the working directory is the source directory
    And the Ruby source is:
      """
      begin
        File.read("missing.txt")
      rescue Errno::ENOENT => error
        warn(error.message)
      ensure
        puts "cleanup"
      end
      begin
        File.write("missing/report", "x")
      rescue SystemCallError => error
        puts error.message
      end
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: A specific errno handler contributes its field state to normal continuation
    Given the working directory is the source directory
    And the Ruby source is:
      """
      class Report
        attr_accessor :text
        def initialize; @text = 7; end
      end
      report = Report.new
      begin
        report.text = File.read("missing.txt")
      rescue Errno::ENOENT
        report.text = "fallback\n"
      end
      puts report.text.chomp
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario Outline: A failed argument discards unreachable I/O and field effects
    Given the Ruby source is:
      """
      class Cell
        def initialize; @text = "Ada\n"; end
        def text; @text&.chomp; end
        def replace
          @text = 7
          puts "wrong argument"
        end
      end
      class Choice
        def initialize(**options); puts "constructor"; end
        def value(**options); puts "wrong body"; end
      end
      cell = Cell.new
      begin
        <call>
      rescue StandardError
        puts cell.text
      end
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

    Examples:
      | call                                        |
      | Choice.new.value(**7, later: cell.replace)   |
      | Choice.new(**7, later: cell.replace)         |
      | Choice.new.value(**7, later: cell.replace) { puts "wrong block" } |
      | Choice.new(**7, later: cell.replace) { puts "wrong block" }        |
      | Choice.new.value(**7, &cell.replace)                              |
      | print(raise("stop"), cell.replace)                               |

  Scenario: A file path is captured before a later argument reassigns its local
    Given the working directory is the source directory
    And the Ruby source is:
      """
      path = "report.txt"
      p(File.write(path, path = 7))
      puts File.read("report.txt")
      p(path)
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario: User output methods and lexical stream and File constants keep lookup priority
    Given the Ruby source is:
      """
      class Report
        STDOUT = "local"
        File = "local file"
        def print(value); puts value; 7; end
        def warn(value); value + 1; end
        def run
          p(print(STDOUT))
          p(warn(9))
          puts File
          ::STDOUT.write("root")
        end
      end
      Report.new.run
      """
    When I run Rubast
    Then stdout, stderr, and exit status match CRuby

  Scenario Outline: APIs beyond the text I/O contract fail before emission
    Given the Ruby source is:
      """
      <operation>
      """
    When I run Rubast
    Then the diagnostic has code "E_UNSUPPORTED" at line 1

    Examples:
      | operation                               |
      | print                                   |
      | warn("x", uplevel: 1)                   |
      | STDIN.gets(",")                         |
      | STDIN.read(3)                           |
      | STDOUT.close                            |
      | STDOUT.warn("wrong")                    |
      | File.read(7)                            |
      | SystemCallError.new("wrong")            |
      | raise SystemCallError, "wrong"          |
      | STDIN&.read                             |
      | STDOUT.write("x", mode: "w")            |
      | STDOUT.write                            |
      | File.open("report", "w")                |
      | File.read("report", encoding: "UTF-16") |
      | File.write("report", "x", 3)            |
      | print([1, 2])                           |
      | puts STDOUT                             |
      | "#{STDOUT}"                             |
      | $stdout = STDERR                        |
