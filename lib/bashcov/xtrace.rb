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
    #   {PS4}. The last five tell the hits traced in a subshell, the depth
    #   of function calls and sourced files, the process of the shell (its
    #   subshells share it, another Bash it runs does not), the function
    #   running and the first line of the command Bash ran, see
    #   {#subshell_hits}.
    FIELDS = %w[
      ${LINENO-} ${BASH_SOURCE-} ${PWD-} ${OLDPWD-} ${BASH_SUBSHELL-} ${#BASH_SOURCE[@]} $$ ${FUNCNAME-}
      ${BASH_COMMAND%%[[:cntrl:]]*}
    ].freeze

    # Start of the text Bash traces for the header of a +for+, +case+ or
    # +select+ command
    HEADER_TRACE = /\A(?:for|case|select) |\A\(\( /

    # Hits which a command at subshell level 0 was given to hold
    # @!attribute script
    #   @return [Pathname] script of that command
    # @!attribute command
    #   @return [String] its +BASH_COMMAND+
    # @!attribute index
    #   @return [Integer] its line
    # @!attribute calls
    #   @return [Integer] its depth of calls
    # @!attribute counts
    #   @return [Hash{Array => Integer}] the hits, as keys of {#subshell_hits},
    #     with their counts
    Settled = Struct.new(:script, :command, :index, :calls, :counts)

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
      @subshell_hits = {}
      # hits traced in a subshell and not counted yet, by process and by the
      # subshell level of the last command holding them: script, line,
      # command, whether it is a stale header, depth of calls and function
      # (the function called by the substitution, if any, once held) and
      # lines holding it. Each Bash process has its own, since the hits of a
      # script run by another come in the same trace.
      @pending_hits = Hash.new { |hash, process| hash[process] = {} }
      # last command traced by each process at each subshell level, with its
      # script and line
      @last_commands = Hash.new { |hash, process| hash[process] = {} }
      # for each process, the hits its last command at level 0 was given to
      # hold, see {#restore_holder!}
      @last_settled = {}
    end

    # [Hash{Pathname => Hash{Array(Integer, String, Boolean, Array<Integer, nil>, String) => Integer}}]
    #   For each script, the number of hits traced in a subshell by line
    #   (0-based), first line of the command Bash ran, whether Bash traced a
    #   header with the command run before (it does not update +BASH_COMMAND+
    #   for the header of a +for+, +case+ or +select+ command), and the lines
    #   of the commands holding it, innermost first: the next hit traced at
    #   each lower subshell level, +nil+ for one in another script or none;
    #   and, for a hit in a function which the substitution called, the name
    #   of that function, +nil+ otherwise. Bash traces the commands of such a
    #   function on their own lines when it is defined out of the
    #   substitution; those of another script are left out. Bash reports
    #   the commands of a command substitution spanning several lines on the
    #   wrong lines, which {HitRelocator} fixes with these.
    attr_reader :subshell_hits

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
        self.class.delimiter, field_count, PS4_START_REGEXP, following: true,
      )

      # +take(field_count)+ would be more natural here, but doesn't seem to
      # play nicely with +Enumerator+s backed by +IO+ objects.
      loop do
        break if (hit = (0..field_count).map { fields.next }).empty?

        parse_hit!(*hit)
      end
      @pending_hits.each_key { |process| settle_subshell_hits!(process, [nil, nil, 0, nil]) }

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
    # @param [String] lineno      expanded +LINENO+
    # @param [String] bash_source expanded +BASH_SOURCE+
    # @param [String] pwd         expanded +PWD+
    # @param [String] oldpwd      expanded +OLDPWD+
    # @param [String] subshell    expanded +BASH_SUBSHELL+
    # @param [String] calls       expanded +${#BASH_SOURCE[@]}+, how deep in
    #   function calls and sourced files the hit is
    # @param [String] process     expanded +$$+
    # @param [String] function    expanded +FUNCNAME+
    # @param [String] command     first line of the expanded +BASH_COMMAND+
    # @param [String] trace       first line of the text Bash traced after
    #   the {ps4}
    # @return [void]
    def parse_hit!(lineno, bash_source, pwd, oldpwd, subshell = "0", calls = "", process = "", function = "", command = "", trace = "")
      if /\A\d+\z/.match?(lineno)
        lineno = lineno.to_i
      elsif lineno == "${LINENO-}"
        # the variable doesn't expand on line misses so we can safely ignore it
        return
      else
        skip_record!("expected integer for LINENO, got #{lineno.inspect}")
        return
      end

      bash_source, pwd, oldpwd = [bash_source, pwd, oldpwd].map { |path| Pathname.new(path) }

      update_wd_stacks!(pwd, oldpwd)

      script = find_script(bash_source)

      # for one-liners, +LINENO+ == 0, do this to avoid an +IndexError+
      # one-liners will be culled from the coverage results later on
      index = (lineno > 1 ? lineno - 1 : 0)

      @files[script] ||= []
      @files[script][index] ||= 0
      @files[script][index] += 1

      depth = /\A\d+\z/.match?(subshell) ? subshell.to_i : 0

      # Bash keeps +BASH_COMMAND+ from the command run before at the same
      # subshell level when tracing the header of a +for+, +case+ or
      # +select+ command, which is on a line of its own, even after the
      # substitutions of the header ran; the text it traces then tells it
      # from the same command run again. An arithmetic command is traced
      # like the expressions of an arithmetic +for+, but as its own text.
      last_commands = @last_commands[process]
      last = last_commands[depth]
      stale = [script, command] == last&.first(2) && index != last.last && HEADER_TRACE.match?(trace) &&
              command.delete(" ") != trace.delete(" ")
      last_commands.delete_if { |level, _| level > depth }
      last_commands[depth] = [script, command, index] unless stale

      calls = calls.to_i
      # a stale header keeps the text of the holder run before it: it is no
      # holder of the hits settled then
      restore_holder!(process, script, command, index, calls) if depth.zero? && !stale
      settle_subshell_hits!(process, [script, index, depth, calls], command)
      return unless depth.positive?

      (@pending_hits[process][depth] ||= Hash.new(0))[[script, index, command, stale, [calls, function], []]] += 1
    end

    # Before Bash 5.2, the commands of an +EXIT+ trap set in a substitution
    # are traced at subshell level 0, on the first lines, with the
    # +BASH_COMMAND+ of the command holding the substitution, which is traced
    # after them: the hits which the first command of the trap was given
    # follow each of these, up to the last one, their real holder.
    # @param [String] process process of the hit at level 0 being read
    # @param [Pathname] script its script
    # @param [String] command its +BASH_COMMAND+
    # @param [Integer] index its line
    # @param [Integer] calls its depth of calls
    # @return [void]
    def restore_holder!(process, script, command, index, calls)
      settled = @last_settled[process]
      return unless settled
      return if trap_call?(settled, command, calls)
      return if [settled.script, settled.command, settled.index] == [script, command, index]

      @last_settled.delete(process)
      return unless [settled.script, settled.command] == [script, command]
      return if @pending_hits[process].keys.any?(&:positive?)

      hits = @subshell_hits[script]
      moved = Settled.new(script, command, index, calls, Hash.new(0))
      settled.counts.each do |key, count|
        hit_index, hit_command, stale, holders, called = key
        hits[key] -= count
        hits.delete(key) unless hits[key].positive?
        moved_key = [hit_index, hit_command, stale, holders[...-1] + [index], called]
        hits[moved_key] += count
        moved.counts[moved_key] += count
      end
      # another command of the trap may have held them: the next one may too
      @last_settled[process] = moved
    end

    # Gives the hits waiting at a subshell level above +depth+ the line of
    # this hit, which holds them: Bash traces the command holding a
    # substitution right after the commands of the substitution, one level
    # lower. They are counted once they reach level 0, see {#subshell_hits}.
    # @param [String] process process of the hit: it holds the hits of its
    #   own subshells only
    # @param [Array(Pathname, Integer, Integer, Integer), Array(nil, nil, Integer, nil)] holder
    #   script, line, subshell level and depth of calls of the hit, +nil+s
    #   at the end of the trace
    # @param [String, nil] holder_command +BASH_COMMAND+ of the hit
    # @return [void]
    def settle_subshell_hits!(process, holder, holder_command = nil)
      script, holder_index, depth, holder_calls = holder
      pending_hits = @pending_hits[process]
      settled = Settled.new(script, holder_command, holder_index, holder_calls, Hash.new(0))
      pending_hits.keys.select { |level| level > depth }.each do |level|
        pending_hits.delete(level).each do |(hit_script, index, command, stale, frame, holders), count|
          same_script = hit_script == script
          # told by the command right above it, then kept along
          called = holders.empty? ? (called_function(frame, holder_calls, same_script) if script) : frame
          # a command of another script, called in the substitution
          next if called && !same_script

          key = [hit_script, index, command, stale, called, holders + [(holder_index if same_script)]]
          if depth.zero?
            counted = [index, command, stale, key.last, called]
            (@subshell_hits[hit_script] ||= Hash.new(0))[counted] += count
            settled.counts[counted] += count if same_script
          else
            (pending_hits[depth] ||= Hash.new(0))[key] += count
          end
        end
      end
      return unless script && depth.zero? && !settled.counts.empty?

      # the hits of a substitution run by the trap are on their real holder
      # already, and the ones settled before them still wait for theirs
      suspended = @last_settled[process]
      @last_settled[process] = settled unless suspended && trap_call?(suspended, holder_command, holder_calls)
    end

    # Each command of an +EXIT+ trap is traced with the +BASH_COMMAND+ of
    # the command holding the substitution, before that command, those of a
    # function it calls on their own lines, deeper in the calls.
    # @param [Settled] settled hits settled last at level 0
    # @param [String] command +BASH_COMMAND+ of a later hit at level 0
    # @param [Integer] calls its depth of calls
    # @return [Boolean] whether that hit may be a command of a function
    #   called by a trap whose hits are the settled ones
    def trap_call?(settled, command, calls)
      settled.command == command && calls > settled.calls
    end

    # @param [Array(Integer, String)] frame depth of calls and function of a
    #   hit traced in a substitution
    # @param [Integer] holder_calls depth of calls of the command holding it
    # @param [Boolean] same_script whether they are in the same script
    # @return [String, nil] the function the substitution called which the
    #   hit is in, +nil+ if the hit is a command of the substitution itself
    def called_function(frame, holder_calls, same_script)
      calls, function = frame
      function if !same_script || calls > holder_calls
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
