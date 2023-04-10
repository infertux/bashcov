# frozen_string_literal: true

require "tempfile"

require "simplecov"

require "bashcov/detective"
require "bashcov/errors"
require "bashcov/field_stream"
require "bashcov/lexer"
require "bashcov/xtrace"

module Bashcov
  # Runs a given command with xtrace enabled then computes code coverage.
  class Runner
    # @param [String] command Command to run
    def initialize(command)
      @command = command
      @detective = Detective.new(Bashcov.bash_path)
    end

    # Runs the command with appropriate xtrace settings.
    # @note Binds Bashcov +stdin+ to the program being executed.
    # @return [Process::Status] Status of the executed command
    def run
      # Clear out previous run
      @result = nil

      field_stream = FieldStream.new
      @xtrace = Xtrace.new(field_stream)
      fd = @xtrace.file_descriptor

      options = { in: :in }
      options[fd] = fd # bind FDs to the child process

      if Bashcov.options.mute
        options[:out] = "/dev/null"
        options[:err] = "/dev/null"
      end

      env =
        if Process.uid.zero?
          # if running as root, Bash 4.4+ does not inherit $PS4 from the environment
          # https://github.com/infertux/bashcov/issues/43#issuecomment-450605839
          write_warning "running as root is NOT recommended, Bashcov may not work properly."

          temp_file = Tempfile.new("bashcov_bash_env")
          temp_file.write("export PS4='#{Xtrace.ps4}'\n")
          temp_file.close

          { "BASH_ENV" => temp_file.path }
        else
          { "PS4" => Xtrace.ps4 }
        end

      env["BASH_XTRACEFD"] = fd.to_s

      with_xtrace_flag do
        command_pid = Process.spawn env, *@command, options # spawn the command

        begin
          # start processing the xtrace output
          xtrace_thread = Thread.new { @xtrace.read }

          Process.wait command_pid

          @xtrace.close

          @coverage = xtrace_thread.value # wait for the thread to return
        rescue XtraceError => e
          write_warning <<-WARNING
            encountered an error parsing Bash's output (error was:
            #{e.message}). This can occur if your script or its path contains
            the sequence #{Xtrace.delimiter.inspect}, or if your script unsets
            LINENO. Aborting early; coverage report will be incomplete.
          WARNING

          @coverage = e.files
        end
      end

      temp_file&.unlink

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

    def write_warning(message)
      warn [
        Bashcov.program_name,
        ": warning: ",
        message.gsub(/^\s+/, "").lines.map(&:chomp).join(" "),
      ].join
    end

    # @note +SHELLOPTS+ must be exported so we use Ruby's {ENV} variable
    # @yield [void] adds "xtrace" to +SHELLOPTS+ and then runs the provided
    #   block
    # @return [Object, ...] the value returned by the calling block
    def with_xtrace_flag
      existing_flags_s = ENV.fetch("SHELLOPTS", "")
      existing_flags = existing_flags_s.split(":")
      ENV["SHELLOPTS"] = (existing_flags | ["xtrace"]).join(":")

      yield
    ensure
      ENV["SHELLOPTS"] = existing_flags_s
    end

    # Add files which have not been executed at all (i.e. with no coverage)
    # @return [void]
    def find_bash_files!
      filtered_files.each do |filename|
        @coverage[filename] = [] if !@coverage.include?(filename) && @detective.shellscript?(filename)
      end
    end

    # @return [Array<Pathname>] the list of files that should be included in
    #   coverage results, unless filtered by one or more SimpleCov filters
    def tracked_files
      return @tracked_files if defined? @tracked_files

      mandatory = SimpleCov.tracked_files ? Pathname.glob(SimpleCov.tracked_files) : []
      under_root = Bashcov.skip_uncovered ? [] : Pathname.new(Bashcov.root_directory).find.to_a

      @tracked_files = (mandatory + under_root).uniq
    end

    # @return [Array<Pathname>] the list of files that should be included in
    #   coverage results
    def filtered_files
      return @filtered_files if defined? @filtered_files

      source_files = tracked_files.map do |file|
        SimpleCov::SourceFile.new(file.to_s, @coverage.fetch(file, []))
      end

      source_file_to_tracked_file = source_files.zip(tracked_files).to_h

      @filtered_files = SimpleCov.filtered(source_files).map do |source_file|
        source_file_to_tracked_file[source_file]
      end
    end

    # @return [void]
    def expunge_invalid_files!
      @coverage.each_key do |filename|
        if !filename.file?
          @coverage.delete filename
          write_warning "#{filename} was executed but has been deleted since then - it won't be reported in coverage."

        elsif !@detective.shellscript?(filename)
          @coverage.delete filename
          write_warning "#{filename} was partially executed but has invalid Bash syntax - it won't be reported in coverage."
        end
      end
    end

    # @see Lexer
    # @return [void]
    def mark_relevant_lines!
      @coverage.each_pair do |filename, coverage|
        lexer = Lexer.new(filename, coverage)
        lexer.complete_coverage
      end
    end

    def convert_coverage
      @coverage.transform_keys(&:to_s)
    end
  end
end
