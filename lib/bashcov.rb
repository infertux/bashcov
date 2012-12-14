require 'optparse'
require 'ostruct'
require 'bashcov/version'
require 'bashcov/lexer'
require 'bashcov/line'
require 'bashcov/runner'
require 'bashcov/xtrace'

module Bashcov
  class << self
    attr_reader :options

    def set_default_options!
      @options ||= OpenStruct.new
      @options.skip_uncovered = false
    end

    def parse_options! args
      OptionParser.new do |opts|
        opts.banner = "Usage: #{opts.program_name} [options] <filename>"
        opts.version = Bashcov::VERSION

        opts.separator ""
        opts.separator "Specific options:"

        opts.on("-s", "--skip-uncovered", "Do not report uncovered files") do |s|
          @options.skip_uncovered = s
        end

        opts.separator ""
        opts.separator "Common options:"

        opts.on_tail("-h", "--help", "Show this message") do
          abort(opts.help)
        end

        opts.on_tail("--version", "Show version") do
          puts opts.ver
          exit
        end

      end.parse!(args)

      if args.one?
        @options.filename = args.shift
      else
        abort("You must give exactly one file to execute.")
      end
    end

    def mute?
      @mute ||= false
    end

    def mute= state
      @mute = !!state
    end

    def root_directory
      Dir.getwd
    end

    def coverage_array(filename, fill = Line::UNCOVERED)
      lines = File.readlines(filename).size
      [fill] * lines
    end

    def link
      %Q|<a href="https://github.com/infertux/bashcov">bashcov</a> v#{VERSION}|
    end
  end
end

Bashcov.set_default_options!

