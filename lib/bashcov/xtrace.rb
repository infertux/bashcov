# frozen_string_literal: true

require "io/nonblock"
require "pathname"
require "securerandom"

require "bashcov/errors"

module Bashcov
  # This class manages +xtrace+ output.
  #
  # @see Runner
  class Xtrace
    # [String] Character that will be used to indicate the nesting level of
    #   +xtrace+d instructions
    DEPTH_CHAR = "+"

    # [String] Prefix used in +PS4+ to identify relevant output
    PREFIX = "BASHCOV>"

    # [Array<String>] A collection of Bash internal variables to expand in the
    #   {PS4}
    FIELDS = %w[${LINENO-} ${BASH_SOURCE-} ${PWD-} ${OLDPWD-}].freeze

    class << self
      attr_writer :delimiter, :ps4

      # [String] A randomly-generated UUID used for delimiting the fields of
      # the +PS4+.
      def delimiter
        @delimiter ||= SecureRandom.uuid
      end

      # @return [String] +PS4+ variable used for xtrace output. Expands to
      #   internal Bash variables +BASH_SOURCE+, +PWD+, +OLDPWD+, and +LINENO+,
      #   delimited by {delimiter}.
      # @see http://www.gnu.org/software/bash/manual/bashref.html#index-PS4
      def ps4
        @ps4 ||= make_ps4(*FIELDS)
      end

      # @return [String] a {delimiter}-separated +String+ suitable for use as
      #   +PS4+
      def make_ps4(*fields)
        fields.reduce(DEPTH_CHAR + PREFIX) do |memo, field|
          memo + delimiter + field
        end + delimiter
      end
    end

    # Regexp to match the beginning of the {.ps4}. {DEPTH_CHAR} will be
    # repeated in proportion to the level of Bash call nesting.
    PS4_START_REGEXP = /#{Regexp.escape(DEPTH_CHAR)}+#{Regexp.escape(PREFIX)}$/m

    # Creates a pipe for xtrace output.
    # @see http://stackoverflow.com/questions/6977562/pipe-vs-temporary-file
    def initialize(field_stream)
      @field_stream = field_stream

      @read, @write = IO.pipe
      # Keep Bash's xtrace writes blocking so records are not dropped when the pipe fills.
      @write.nonblock = false

      # Tracks coverage for each file under test
      @files ||= {}

      # Stacks for updating working directory changes
      @pwd_stack ||= []
      @oldpwd_stack ||= []

      @skipped_count = 0
    end

    # [Integer] Number of malformed +PS4+ records skipped by {#read}
    attr_reader :skipped_count

    # [String, nil] Why the first malformed +PS4+ record was skipped
    attr_reader :first_skip_reason

    # @return [Fixnum] File descriptor of the write end of the pipe
    def file_descriptor
      @write.fileno
    end

    # Closes the parent's write end after the command exits, also ending any
    # error-recovery drain without waiting for inherited background writers.
    # @return [void]
    def close
      @write.close
      @read.close if @draining
    end

    # Read fields extracted from Bash's debugging output
    # @return [Hash<Pathname, Array<Integer, nil>>] A hash mapping Bash scripts
    #   to Simplecov-style coverage stats
    # @raise [StandardError] any error while parsing, raised only after
    #   draining until the command exits or the pipe reaches EOF. Malformed
    #   records are skipped (see {#skipped_count}) rather than raised.
    def read
      @field_stream.read = @read

      field_count = FIELDS.length
      fields = @field_stream.each(
        self.class.delimiter, field_count, PS4_START_REGEXP,
      )

      # +take(field_count)+ would be more natural here, but doesn't seem to
      # play nicely with +Enumerator+s backed by +IO+ objects.
      loop do
        break if (hit = (1..field_count).map { fields.next }).empty?

        parse_hit!(*hit)
      end

      @files
    rescue StandardError
      # Keep draining so Bash's blocking xtrace writes cannot fill the pipe and
      # hang the run, or hit a closed pipe and die of SIGPIPE. #close ends the
      # drain once the command exits, so background writers are not waited on.
      @draining = true
      begin
        nil while !@write.closed? && @read.read(65_536)
      rescue IOError
        raise unless @write.closed? # Only ignore closure after the command exits.
      end
      raise
    ensure
      @read.close unless @read.closed?
    end

  private

    # Parses the expanded {ps4} fields and updates the coverage-tracking
    # {@files} hash. A record whose +LINENO+ is not composed solely of digits
    # is skipped: it is usually text that merely looks like the start of a
    # {ps4}, such as the output of +declare -p+ or +set+ being traced, and
    # {FieldStream#each} resynchronizes on the next start of a {ps4}.
    # @overload parse_hit!(lineno, bash_source, pwd, oldpwd)
    #   @param [String]  lineno       expanded +LINENO+
    #   @param [Pathname] bash_source expanded +BASH_SOURCE+
    #   @param [Pathname] pwd         expanded +PWD+
    #   @param [Pathname] oldpwd      expanded +OLDPWD+
    # @return [void]
    def parse_hit!(lineno, *paths)
      if /\A\d+\z/.match?(lineno)
        lineno = lineno.to_i
      elsif lineno == "${LINENO-}"
        # the variable doesn't expand on line misses so we can safely ignore it
        return
      else
        skip_record!("expected integer for LINENO, got #{lineno.inspect}")
        return
      end

      bash_source, pwd, oldpwd = paths.map { |p| Pathname.new(p) }

      update_wd_stacks!(pwd, oldpwd)

      script = find_script(bash_source)

      # for one-liners, +LINENO+ == 0, do this to avoid an +IndexError+
      # one-liners will be culled from the coverage results later on
      index = (lineno > 1 ? lineno - 1 : 0)

      @files[script] ||= []
      @files[script][index] ||= 0
      @files[script][index] += 1
    end

    # Records that a malformed record was skipped
    # @param [String] reason why the record was skipped
    # @return [void]
    def skip_record!(reason)
      @skipped_count += 1
      @first_skip_reason = reason if @skipped_count == 1
    end

    # Scans entries in the +PWD+ stack, checking whether +entry/$BASH_SOURCE+
    # refers to an existing file. Scans the stack in reverse on the assumption
    # that more-recent entries are more plausible candidates for base
    # directories from which +BASH_SOURCE+ can be reached.
    # @param [Pathname] bash_source expanded +BASH_SOURCE+
    # @return [Pathname] the resolved path to +bash_source+, if it exists;
    #   otherwise, +bash_source+ cleaned of redundant slashes and dots
    def find_script(bash_source)
      script = @pwd_stack.reverse.map { |wd| wd + bash_source }.find(&:file?)

      return bash_source.cleanpath if script.nil?

      begin
        script.realpath
      rescue Errno::ENOENT # catch race condition if the file has been deleted
        bash_source.cleanpath
      end
    end

    # Updates the stacks that track the history of values for +PWD+ and
    # +OLDPWD+
    # @param [Pathname] pwd     expanded +PWD+
    # @param [Pathname] oldpwd  expanded +OLDPWD+
    # @return [void]
    def update_wd_stacks!(pwd, oldpwd)
      @pwd_stack[0] ||= pwd
      @oldpwd_stack[0] ||= oldpwd unless oldpwd.to_s.empty?

      # return if we haven't changed working directories
      return if pwd == @pwd_stack[-1]

      # if the current +pwd+ is identical to the top of the +@oldpwd_stack+ and
      # the current +oldpwd+ is identical to the second-to-top entry, then a
      # previous cd/pushd has been undone
      if pwd == @oldpwd_stack[-1] && oldpwd == @oldpwd_stack[-2]
        @pwd_stack.pop
        @oldpwd_stack.pop
      else # new cd/pushd
        @pwd_stack << pwd
        @oldpwd_stack << oldpwd
      end
    end
  end
end
