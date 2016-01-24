# frozen_string_literal: true

require "pathname"
require "securerandom"

module Bashcov
  # This class manages +xtrace+ output.
  #
  # @see Runner
  class Xtrace
    # [String] Character that will be used to indicate the nesting level of
    #   +xtrace+d instructions
    DEPTH_CHAR = "+".freeze

    # [String] Prefix used in +PS4+ to identify relevant output
    PREFIX = "BASHCOV>".freeze

    # [String] A randomly-generated token for delimiting the fields of the
    #   +{PS4}+
    DELIM = SecureRandom.uuid

    # [String] +PS4+ variable used for xtrace output.  Expands to internal Bash
    # variables +$BASH_SOURCE+, +$PWD+, +$OLDPWD+, and +$LINENO+, delimited by
    # {DELIM}.
    # @see http://www.gnu.org/software/bash/manual/bashref.html#index-PS4
    PS4 = %W(#{DEPTH_CHAR + PREFIX} ${BASH_SOURCE} ${PWD} ${OLDPWD} ${LINENO}).reduce(DELIM) do |a, e|
      a + e + DELIM
    end

    # Regexp to match the beginning of the {PS4}.  {DEPTH_CHAR} will be
    # repeated in proportion to the level of Bash call nesting.
    LINE_START_REGEXP = /\A#{Regexp.escape(DEPTH_CHAR)}+#{PREFIX}/

    # Creates a pipe for xtrace output.
    # @see http://stackoverflow.com/questions/6977561/pipe-vs-temporary-file
    def initialize
      @read, @write = IO.pipe

      # Tracks coverage for each file under test
      @files ||= {}

      # Stacks for updating working directory changes
      @pwd_stack ||= []
      @oldpwd_stack ||= []
    end

    # @return [Fixnum] File descriptor of the write end of the pipe
    def file_descriptor
      @write.fileno
    end

    # Closes the pipe for writing.
    # @return [void]
    def close
      @write.close
    end

    # Parses xtrace output and computes coverage.
    # @return [Hash] Hash of executed files with coverage information
    def read
      lines = @read.each_line(DELIM)
fail RuntimeError, "#{lines.to_a.inspect}"
      loop do
        # Reject all lines until we've seen the start of the PS4
        nil until lines.next =~ LINE_START_REGEXP

        # The next three lines will be $BASH_SOURCE, $PWD, $OLDPWD, and $LINENO
        bash_source, pwd, oldpwd = (1..3).map { Pathname.new lines.next.chomp(DELIM) }
        lineno = lines.next.chomp(DELIM)

        # If +$LINENO+ isn't a series of digits, something has gone wrong.  Add
        # +@files+ to the exception in order to propagate the existing coverage
        # data back to the {Bashcov::Runner} instance.
        unless lineno =~ /\A\d+\z/
          got = lineno.empty? ? "<nil>" : lineno
          raise XtraceError.new("expected integer for $LINENO, got `#{got}'", @files)
        end

        parse_hit!(bash_source, pwd, oldpwd, lineno.to_i)
      end

      @files
    rescue StopIteration
      # :nocov: -- here in case the +lines+ iterator raises it on +#next+.
      @files
      # :nocov:
    end

  private

    # Parses the expanded {PS4} fields and updates the coverage-tracking
    # {@files} hash
    # @param [Pathname] bash_source expanded +$BASH_SOURCE+
    # @param [Pathname] pwd         expanded +$PWD+
    # @param [Pathname] oldpwd      expanded +$OLDPWD+
    # @param [Integer]  lineno      expanded +$LINENO+
    def parse_hit!(bash_source, pwd, oldpwd, lineno)
      update_wd_stacks!(pwd, oldpwd)

      script = find_script(bash_source)

      # For one-liners, +$LINENO+ == 0.  Do this to avoid an +IndexError+;
      # one-liners will be culled from the coverage results later on.
      index = lineno > 1 ? lineno - 1 : 0

      @files[script] ||= []
      @files[script][index] ||= 0
      @files[script][index] += 1
    end

    # Scans entries in the $PWD stack, checking whether +entry/$BASH_SOURCE+
    # refers to an existing file.  Scans the stack in reverse on the assumption
    # that more-recent entries are more plausible candidates for base
    # directories from which $BASH_SOURCE can be reached.
    # @param [Pathname] bash_source expanded +$BASH_SOURCE+
    # @return [Pathname] the resolved path to +bash_source+, if it exists;
    #   otherwise, +bash_source+ cleaned of redundant slashes and dots
    def find_script(bash_source)
      script = @pwd_stack.reverse.map { |wd| wd + bash_source }.find(&:file?)
      script.nil? ? bash_source.cleanpath : script.realpath
    end

    # Updates the stacks that track the history of values for +$PWD+ and
    # +$OLDPWD+
    # @param [Pathname] pwd     expanded +$PWD+
    # @param [Pathname] oldpwd  expanded +$OLDPWD+
    # @return [void]
    def update_wd_stacks!(pwd, oldpwd)
      @pwd_stack[0] ||= pwd
      @oldpwd_stack[0] ||= oldpwd unless oldpwd.to_s.empty?

      # We haven't changed working directories; short-circuit.
      return if pwd == @pwd_stack[-1]

      # If the current +pwd+ is identical to the top of the +@oldpwd_stack+ and
      # the current +oldpwd+ is identical to the second-to-top entry, then a
      # previous cd/pushd has been undone.
      if pwd == @oldpwd_stack[-1] && oldpwd == @oldpwd_stack[-2]
        @pwd_stack.pop
        @oldpwd_stack.pop
      # New cd/pushd.
      else
        @pwd_stack << pwd
        @oldpwd_stack << oldpwd
      end
    end
  end
end
