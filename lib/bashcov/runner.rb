module Bashcov
  # Runs a given command with xtrace enabled then computes code coverage.
  class Runner
    # @param [String] command Command to run
    def initialize(command)
      @command = command
    end

    # Runs the command with appropriate xtrace settings.
    # @note Binds Bashcov +stdin+ to the program being executed.
    # @return [Process::Status] Status of the executed command
    def run
      inject_xtrace_flag!

      @xtrace = Xtrace.new
      fd = @xtrace.file_descriptor
      options = { :in => :in, fd => fd } # bind FDs to the child process
      options.merge!(out: "/dev/null", err: "/dev/null") if Bashcov.options.mute
      env = { "BASH_XTRACEFD" => fd.to_s, "PS4" => Xtrace::PS4 }

      command_pid = Process.spawn env, @command, options # spawn the command
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

        convert_coverage
      end
    end

  private

    # @note +SHELLOPTS+ must be exported so we use Ruby's {ENV} variable
    # @return [void]
    def inject_xtrace_flag!
      existing_flags = (ENV["SHELLOPTS"] || "").split(":")
      ENV["SHELLOPTS"] = (existing_flags | ["xtrace"]).join(":")
    end

    # Add files which have not been executed at all (i.e. with no coverage)
    # @return [void]
    def find_bash_files!
      return if Bashcov.options.skip_uncovered

      Pathname.glob("#{Bashcov.root_directory}/**/*.sh").each do |filename|
        @coverage[filename] = [] unless @coverage.include?(filename)
      end
    end

    # @return [void]
    def expunge_invalid_files!
      @coverage.each_key do |filename|
        next if filename.file?

        @coverage.delete filename
        warn "Warning: #{filename} was executed but has been deleted since then - it won't be reported in coverage."
      end
    end

    # @see Lexer
    # @return [void]
    def mark_relevant_lines!
      @coverage.each_pair do |filename, coverage|
        lexer = Lexer.new(filename, coverage)
        lexer.uncovered_relevant_lines do |lineno|
          @coverage[filename][lineno] = Bashcov::Line::UNCOVERED
        end
      end
    end

    def convert_coverage
      Hash[@coverage.map { |filename, coverage| [filename.to_s, coverage] }]
    end
  end
end
