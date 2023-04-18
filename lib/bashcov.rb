# frozen_string_literal: true

require "optparse"
require "pathname"

require "bashcov/runner"
require "bashcov/version"

# Bashcov default module
# @note Keep it short!
module Bashcov
  # A +Struct+ to store Bashcov configuration
  Options = Struct.new(
    *%i[skip_uncovered mute bash_path root_directory command command_name]
  )

  class << self
    # @return [Struct] The +Struct+ object representing Bashcov configuration
    def options
      set_default_options! unless defined?(@options)
      @options
    end

    # Parses the given CLI arguments and sets +options+.
    # @param [Array] args list of arguments
    # @raise [SystemExit] if invalid arguments are given
    # @return [void]
    def parse_options!(args)
      begin
        option_parser.parse!(args)
      rescue OptionParser::ParseError, Errno::ENOENT => e
        abort "#{option_parser.program_name}: #{e.message}"
      end

      if args.empty?
        abort("You must give exactly one command to execute.")
      else
        options.command = args.unshift(bash_path)
      end
    end

    # @return [String] Program name
    def program_name
      "bashcov"
    end

    # @return [String] Program name including version for easy consistent output
    # @note +fullname+ instead of name to avoid clashing with +Module.name+
    def fullname
      [
        program_name,
        VERSION,
        "with Bash #{BASH_VERSION},",
        "Ruby #{RUBY_VERSION},",
        "and SimpleCov #{SimpleCov::VERSION}",
        (Process.uid.zero? ? "as root user (NOT recommended)" : nil),
      ].compact.join(" ")
    end

    # @return [String] The value to use as +SimpleCov.command_name+. Uses the
    #   value of +--command-name+, if this flag was provided, or
    #   +BASHCOV_COMMAND_NAME, if set, defaulting to a stringified
    #   representation of {Bashcov#command}.
    def command_name
      return @options.command_name if @options.command_name
      return ENV.fetch("BASHCOV_COMMAND_NAME", nil) unless ENV.fetch("BASHCOV_COMMAND_NAME", "").empty?

      command.compact.join(" ")
    end

    def bash_path
      # First attempt to use the value from `options`, but ignore all exceptions.
      # This is used early for the `BASH_VERSION` definition, so first use will likely error.
      begin
        return @options.bash_path if @options.bash_path
      rescue NoMethodError; end # rubocop:disable Lint/SuppressedException

      # Support the same `BASHCOV_BASH_PATH` environment variable used in the spec tests.
      return ENV.fetch("BASHCOV_BASH_PATH", nil) unless ENV.fetch("BASHCOV_BASH_PATH", "").empty?

      # Fall back to standard Bash location.
      "/bin/bash"
    end

    def bash_version
      `#{bash_path} -c 'echo -n ${BASH_VERSINFO[0]}.${BASH_VERSINFO[1]}'`
    end

    # Wipe the current options and reset default values
    def set_default_options!
      @options = Options.new

      @options.skip_uncovered   = false
      @options.mute             = false
      @options.root_directory   = Dir.getwd
    end

    # Define option accessors
    Options.new.members.each do |option|
      [option, "#{option}="].each do |method|
        next if instance_methods(false).include?(method)

        define_method method do |*args|
          options.public_send(*[method, *args])
        end
      end
    end

  private

    def help
      <<-HELP.gsub(/^ +/, "").gsub("\t", " " * 4)
        Usage: #{program_name} [options] [--] <command> [options]
        Examples:
        \t#{program_name} ./script.sh
        \t#{program_name} --skip-uncovered ./script.sh
        \t#{program_name} -- ./script.sh --some --flags
        \t#{program_name} --skip-uncovered -- ./script.sh --some --flags
      HELP
    end

    def option_parser
      OptionParser.new do |opts|
        opts.program_name = program_name
        opts.version = Bashcov::VERSION
        opts.banner = help

        opts.separator "\nSpecific options:"

        opts.on("-s", "--skip-uncovered", "Do not report uncovered files") do |s|
          options.skip_uncovered = s
        end
        opts.on("-m", "--mute", "Do not print script output") do |m|
          options.mute = m
        end
        opts.on("--bash-path PATH", "Path to Bash executable") do |p|
          raise Errno::ENOENT, p unless File.file? p

          options.bash_path = p

          # Redefine `BASH_VERSION` constant with upated `bash_path`.
          # This is hacky, but a lot of code references that constant and this should only have to be done once.
          send(:remove_const, "BASH_VERSION")
          const_set("BASH_VERSION", bash_version.freeze)
        end
        opts.on("--root PATH", "Project root directory") do |d|
          raise Errno::ENOENT, d unless File.directory? d

          options.root_directory = d
        end
        opts.on("--command-name NAME", "Value to use as SimpleCov.command_name") do |c|
          options.command_name = c
        end

        opts.separator "\nCommon options:"

        opts.on_tail("-h", "--help", "Show this message") do
          abort(opts.help)
        end
        opts.on_tail("--version", "Show version") do
          puts opts.ver
          exit
        end
      end
    end
  end

  # Current Bash version (e.g. 4.2)
  BASH_VERSION = bash_version.freeze
end
