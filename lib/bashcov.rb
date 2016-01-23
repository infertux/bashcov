require "forwardable"
require "optparse"
require "ostruct"
require "pathname"
require "bashcov/version"
require "bashcov/lexer"
require "bashcov/line"
require "bashcov/runner"
require "bashcov/xtrace"
require "bashcov/errors"

# Bashcov default module
# @note Keep it short!
module Bashcov
  # Container for parsing and exposing options and static configuration
  class Instance
    # @return [OpenStruct] Bashcov settings
    attr_reader :options

    # Sets default options overriding any existing ones.
    # @return [void]
    def initialize
      @options ||= OpenStruct.new
      @options.skip_uncovered = false
      @options.mute = false
    end

    # @return [String] The project's root directory
    def root_directory
      @root_directory ||= Pathname.getwd
    end

    # Parses the given CLI arguments and sets +options+.
    # @param [Array] args list of arguments
    # @raise [SystemExit] if invalid arguments are given
    # @return [void]
    def parse_options!(args)
      option_parser.parse!(args)

      if args.empty?
        abort("You must give exactly one command to execute.")
      else
        @options.command = args.join(" ")
      end
    end

    # @return [String] Program name including version for easy consistent output
    def name
      "bashcov v#{VERSION}"
    end

  private

    def help(program_name)
      <<-HELP.gsub!(/^ +/, "").gsub!("\t", " " * 4)
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
        opts.program_name = "bashcov"
        opts.version = Bashcov::VERSION
        opts.banner = help opts.program_name

        opts.separator "\nSpecific options:"

        opts.on("-s", "--skip-uncovered", "Do not report uncovered files") do |s|
          @options.skip_uncovered = s
        end
        opts.on("-m", "--mute", "Do not print script output") do |m|
          @options.mute = m
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

  class << self
    extend Forwardable

    def_delegators :@instance, :root_directory, :name, :parse_options!, :options

    # Resets options to a fresh state
    def set_default_options!
      @instance = Bashcov::Instance.new
    end
  end
end

# Make sure default options are set
Bashcov.set_default_options!
