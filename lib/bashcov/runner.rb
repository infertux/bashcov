require "bashcov"

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
      @xtrace = Xtrace.new
      fd = @xtrace.file_descriptor
      env = { "PS4" => Xtrace::PS4 }
      options = { :in => :in, fd => fd }

      if Bashcov.options.mute
        options[:out] = "/dev/null"
        options[:err] = "/dev/null"
      end

      command_pid = Process.spawn env, @command, options # spawn the command

      begin
        xtrace_thread = Thread.new { @xtrace.read } # start processing the xtrace output

        Process.wait command_pid

        @xtrace.close

        @coverage = xtrace_thread.value # wait for the thread to return
      rescue XtraceError => e
        $stderr.puts <<-ERROR.gsub(/^\s+/, "").lines.map { |s| s.chomp("\n") }.join(" ")
          Warning: encountered an error parsing Bash's output(error was:
          #{e.message}). This can occur if your script or its path contains
          the sequence `#{Regexp.escape Xtrace::DELIM}', or if your script
          unsets LINENO. Aborting early; coverage report will be incomplete.
        ERROR

        @coverage = e.files
      end

      $?
    end

    def run_xtrace
      inject_xtrace_flag! do
        bash_env = Trap.set("bashcov_debug_trap", Xtrace::DELIM, fd, Xtrace::FIELDS)
        env = { "PS4" => Xtrace::PS4, "BASH_ENV" => bash_env.path }
      end
    end

    def run_trap

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
    # @yield [void] adds "xtrace" to +SHELLOPTS+ and then runs the provided
    #   block
    # @return [Object, ...] the value returned by the calling block
    def inject_xtrace_flag!
      return enum_for(__method__) unless block_given?

      existing_flags_s = ENV["SHELLOPTS"]
      existing_flags = (existing_flags_s || "").split(":")
      ENV["SHELLOPTS"] = (existing_flags | ["xtrace"]).join(":")

      # Calls the provided block
      Proc.new.call
    ensure
      ENV["SHELLOPTS"] = existing_flags_s
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
