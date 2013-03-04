module Bashcov
  # Runs a given command with xtrace enabled then computes code coverage.
  class Runner
    # @param [String] command Command to run
    def initialize command
      @command = command
    end

    # Runs the command with appropriate xtrace settings.
    # @note Binds Bashcov +stdin+ to the program executed.
    # @return [Process::Status] Status of the executed command
    def run
      inject_xtrace_flag!

      @xtrace = Xtrace.new
      fd = @xtrace.file_descriptor
      @command = "BASH_XTRACEFD=#{fd} PS4='#{Xtrace.ps4}' #{@command}"
      options = {:in => :in, fd => fd} # bind fds to the child process
      options.merge!({out: '/dev/null', err: '/dev/null'}) if Bashcov.options.mute

      pid = Process.spawn @command, options
      Process.wait pid

      $?
    end

    # @return [Hash] Coverage hash of the last run
    def result
      files = if Bashcov.options.skip_uncovered
        {}
      else
        find_bash_files "#{Bashcov.root_directory}/**/*.sh"
      end

      files = add_coverage_result files
      files = ignore_irrelevant_lines files
    end

    # @param [String] directory Directory to scan
    # @return [Hash] Coverage hash of Bash files in the given +directory+. All
    #   files are marked as uncovered.
    def find_bash_files directory
      Dir[directory].inject({}) do |files, file|
        absolute_path = File.expand_path(file)
        next unless File.file?(absolute_path)

        files.merge!(absolute_path => Bashcov.coverage_array(absolute_path))
      end
    end

    # @param [Hash] files Initial coverage hash
    # @return [Hash] Given hash including coverage result from {Xtrace}
    # @see Xtrace
    def add_coverage_result files
      @xtrace.files.each do |file, lines|
        lines.each_with_index do |line, lineno|
          files[file] ||= Bashcov.coverage_array(file)
          files[file][lineno] = line if line
        end
      end

      files
    end

    # @param [Hash] files Initial coverage hash
    # @return [Hash] Given hash ignoring irrelevant lines
    # @see Lexer
    def ignore_irrelevant_lines files
      files.each do |filename, lines|
        lexer = Lexer.new(filename)
        lexer.irrelevant_lines.each do |lineno|
          files[filename][lineno] = Bashcov::Line::IGNORED
        end
      end
    end

  private

    def inject_xtrace_flag!
      # SHELLOPTS must be exported so we use Ruby's ENV variable
      existing_flags = (ENV['SHELLOPTS'] || '').split(':')
      ENV['SHELLOPTS'] = (existing_flags | ['xtrace']).join(':')
    end
  end
end

