# frozen_string_literal: true

require "open3"
require "timeout"

module RubastProgramExecution
  def capture_ruby_source(*)
    capture_program(@program_environment || {}, RbConfig.ruby, *, stdin_data: @stdin_data.to_s,
                                                                  unbundled: @unbundled_startup,
                                                                  chdir: @program_directory || Dir.pwd)
  end

  def capture_program(*command, stdin_data: "", timeout: 30, unbundled: false, **)
    if unbundled
      return Bundler.with_unbundled_env { capture_program(*command, stdin_data: stdin_data, timeout: timeout, **) }
    end

    Open3.popen3(*command, **, pgroup: true) do |input, output, errors, process|
      readers = [output, errors].map { |stream| Thread.new { stream.read } }
      begin
        Timeout.timeout(timeout) do
          write_program_input(input, stdin_data)
          [*readers.map(&:value), process.value]
        end
      rescue Timeout::Error
        kill_program_group(process.pid)
        raise
      ensure
        input.close unless input.closed?
        readers.each(&:join)
      end
    end
  end

  private

  def write_program_input(input, data)
    input.write(data)
  rescue Errno::EPIPE
    nil
  ensure
    input.close
  end

  def kill_program_group(pid)
    Process.kill("KILL", -pid)
  rescue Errno::ESRCH
    nil
  end
end
