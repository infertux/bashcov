require "optparse"
require "ostruct"
require "pathname"

require "bashcov/version"
require "bashcov/errors"

# Bashcov default module
# @note Keep it short!
module Bashcov
  [:Lexer, :Line, :Runner, :Trap, :Xtrace].each do |class_sym|
    autoload class_sym, "bashcov/#{class_sym.downcase}"
  end
  autoload :FieldStream, "bashcov/field_stream"

  # Container for parsing and exposing options and static configuration
  class Instance
    # @return [OpenStruct] Bashcov settings
    attr_reader :options

    # Sets default options overriding any existing ones.
    # @return [void]
    def initialize
      @options ||= OpenStruct.new
      @options.skip_uncovered = false
      @options.mute            = false
      @options.use_trap        = false
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

    # @return [Boolean] Whether Bash supports a +PS4+ of greater than 128 bytes
    # @see https://tiswww.case.edu/php/chet/bash/CHANGES
    # @note Item +i.+ under the +bash-4.2-release+ to +bash-4.3-alpha+ change
    #   list notes that version 4.2 truncates +PS4+ if it is greater than 128
    #   bytes.
    def truncated_ps4?
      @has_truncated_ps4 ||= bash_versinfo[0..1].join.to_i <= 42
    end

    # @return [Boolean]  Whether to use +trap+ to capture coverage stats
    def skip_uncovered?
      options.skip_uncovered
    end

    # @return [Boolean]  Whether to use +trap+ to capture coverage stats
    def mute?
      options.mute
    end

    # @return [Boolean]  Whether to use +trap+ to capture coverage stats
    def trap?
      options.use_trap
    end

    # @return [Integer, nil]  Maximum +PS4+ length, or nil if length is
    #    effectively unlimited
    def ps4_length
      truncated_ps4? ? 128 : nil
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
    # @note +fullname+ instead of name to avoid clashing with +Module.name+
    def fullname
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
        opts.on("-T", "--trap", "Use `trap' to capture coverage") do |t|
          @options.use_trap = t
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

  class << self
    attr_accessor :delegate

    # Reset options to the default state
    def set_default_options!
      self.delegate = Bashcov::Instance.new
    end

    def respond_to_missing?(*args)
      delegate.respond_to?(*args)
    end

    def method_missing(method_name, *args, &block)
      delegate.send(method_name, *args, &block)
    end
  end
end

# Make sure default options are set
Bashcov.set_default_options!
