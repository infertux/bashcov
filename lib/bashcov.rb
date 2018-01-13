# frozen_string_literal: true

require "optparse"
require "pathname"

require "bashcov/bash_info"
require "bashcov/runner"
require "bashcov/version"

# Bashcov default module
# @note Keep it short!
module Bashcov
  extend Bashcov::BashInfo

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
        "and SimpleCov #{SimpleCov::VERSION}.",
      ].join(" ")
    end

    # @return [String] The value to use as +SimpleCov.command_name+. Uses the
    #   value of +--command-name+, if this flag was provided, or
    #   +BASHCOV_COMMAND_NAME, if set, defaulting to a stringified
    #   representation of {Bashcov#command}.
    def command_name
      return @options.command_name if @options.command_name
      return ENV["BASHCOV_COMMAND_NAME"] unless ENV.fetch("BASHCOV_COMMAND_NAME", "").empty?
      command.compact.join(" ")
    end

    # Wipe the current options and reset default values
    def set_default_options!
      @options = Options.new

      @options.skip_uncovered   = false
      @options.mute             = false
      @options.bash_path        = "/bin/bash"
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

    def option_parser # rubocop:disable Metrics/MethodLength
      OptionParser.new do |opts| # rubocop:disable Metrics/BlockLength
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
  BASH_VERSION = `#{bash_path} -c 'echo -n ${BASH_VERSINFO[0]}.${BASH_VERSINFO[1]}'`.freeze
end
