module Bashcov
  # Runs a given command with xtrace enabled then computes code coverage.
  class Runner
    # @param [String] command Command to run
    def initialize command
      @command = command
    end

    # Runs the command with appropriate xtrace settings.
    # @note Binds Bashcov +stdin+ to the program being executed.
    # @return [Process::Status] Status of the executed command
    def run
      inject_xtrace_flag!

      @xtrace = Xtrace.new
      fd = @xtrace.file_descriptor
      options = {:in => :in, fd => fd} # bind fds to the child process
      options.merge!({out: '/dev/null', err: '/dev/null'}) if Bashcov.options.mute

      ENV["BASH_XTRACEFD"] = "#{fd}"
      ENV["PS4"] = "#{Xtrace::PS4}"

      command_pid = Process.spawn @command, options # spawn the command
      xtrace_thread = Thread.new { @xtrace.read } # start processing the xtrace output

      Process.wait command_pid
      @xtrace.close

      @coverage = xtrace_thread.value # wait for the thread to return

      $?
    end

    # @return [Hash] Coverage hash of the last run
    # @note The result is memoized.
    def result
      @result ||= begin
        find_bash_files!
        expunge_invalid_files!
        mark_relevant_lines!

        @coverage
      end
    end

  private

    # @note +SHELLOPTS+ must be exported so we use Ruby's {ENV} variable
    # @return [void]
    def inject_xtrace_flag!
      existing_flags = (ENV['SHELLOPTS'] || '').split(':')
      ENV['SHELLOPTS'] = (existing_flags | ['xtrace']).join(':')
    end

    # Add files which have not been executed at all (i.e. with no coverage)
    # @return [void]
    def find_bash_files!
      return if Bashcov.options.skip_uncovered

      Dir["#{Bashcov.root_directory}/**/*.sh"].each do |file|
        @coverage[file] ||= [] # empty coverage array
      end
    end

    # @return [void]
    def expunge_invalid_files!
      @coverage.each_key do |file|
        unless File.file? file
          @coverage.delete file
          warn "Warning: #{file} was executed but has been deleted since then - it won't be reported in coverage."
        end
      end
    end

    # @see Lexer
    # @return [void]
    def mark_relevant_lines!
      @coverage.each do |filename, coverage|
        lexer = Lexer.new(filename, coverage)
        lexer.uncovered_relevant_lines do |lineno|
          @coverage[filename][lineno] = Bashcov::Line::UNCOVERED
        end
      end
    end
  end
end

