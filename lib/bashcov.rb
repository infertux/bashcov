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
      @options.bash_path = "/bin/bash"
    end

    # @return [String] The project's root directory
    def root_directory
      @root_directory ||= Pathname.getwd
    end

    # @return [Array<String>] An array representing the components of
    #   +BASH_VERSINFO+
    def bash_versinfo
      @bash_versinfo ||= `#{@options.bash_path} -c 'echo "${BASH_VERSINFO[@]}"'`.chomp.split
    end

    # @return [Boolean] Whether Bash supports +BASH_XTRACEFD+
    def bash_xtracefd?
      @has_bash_xtracefd ||= bash_versinfo[0..1].join.to_i >= 41
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
        opts.on("--bash-path PATH", "Path to Bash") do |p|
          if File.file? p
            p
          else
            abort("`#{p}' is not a valid path")
          end
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

module_function

  # Reset options to the default state
  def set_default_options!
    module_functions = [:root_directory, :name, :parse_options!, :options,
                        :bash_versinfo, :bash_xtracefd?]

    # Would be nice to use SingleForwardable, but the way that
    # SingleForwardable defines methods appears to preclude closing over a
    # locally-scoped object.
    delegate = Bashcov::Instance.new
    module_functions.each do |m|
      define_method m do |*args, &block|
        delegate.send(m, *args, &block)
      end

      module_function m
    end
  end
end

# Make sure default options are set
Bashcov.set_default_options!
