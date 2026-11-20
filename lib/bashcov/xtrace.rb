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
    # @!attribute holder
    #   @return [Hit] that command
    # @!attribute counts
    #   @return [Hash{Array => Integer}] the hits, as keys of {#subshell_hits},
    #     with their counts
    Settled = Data.define(:holder, :counts) do
      # An EXIT trap can call a function before its real holder appears.
      def trap_call?(next_holder)
        holder.command == next_holder.command && next_holder.calls > holder.calls
      end
    end

    # Each Bash process has its own sequence of commands and pending holders.
    ProcessState = Struct.new(:last_commands, :pending, :settled) do
      def initialize
        super({}, {}, nil)
      end
    end

    # A traced command and its known holders, innermost first. The first
    # holder resolves the function name using call depth. Later holders
    # carry that decision along, so call depth can be discarded.
    Hit = Data.define(:script, :index, :command, :stale, :calls, :function, :holders) do
      def held_by(holder)
        same_script = holder && holder.script == script
        called = function
        called = nil if holders.empty? && (!holder || (same_script && calls <= holder.calls))
        return if called && !same_script

        with(calls: nil, function: called, holders: holders + [(holder.index if same_script)])
      end

      def coverage_key
        [index, command, stale, holders, function]
      end
    end
    private_constant :Settled, :Hit, :ProcessState

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
      @processes = Hash.new { |states, process| states[process] = ProcessState.new }
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

      width = field_count + 1 # expanded PS4 fields plus the trace text
      fields.each_slice(width) { |hit| parse_hit!(*hit) if hit.size == width }
      @processes.each_value { |state| settle_subshell_hits!(state, 0) }

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

      state = @processes[process]
      stale = stale_header?(state.last_commands[depth], script, index, command, trace)
      hit = Hit.new(script, index, command, stale, calls.to_i, function, [])
      state.last_commands.delete_if { |level, _| level > depth }
      state.last_commands[depth] = hit unless stale

      # A stale header repeats the previous command and cannot be its holder.
      restore_holder!(state, hit) if depth.zero? && !stale
      settle_subshell_hits!(state, depth, hit)
      (state.pending[depth] ||= Hash.new(0))[hit] += 1 if depth.positive?
    end

    # Bash keeps BASH_COMMAND from the previous command at this depth when
    # tracing a for, case or select header. An arithmetic command repeated
    # on another line has the same trace as its own text apart from blanks.
    def stale_header?(last, script, index, command, trace)
      !last.nil? && last.script == script && last.command == command && last.index != index &&
        HEADER_TRACE.match?(trace) && command.delete(" ") != trace.delete(" ")
    end

    # Before Bash 5.2, the commands of an +EXIT+ trap set in a substitution
    # are traced at subshell level 0, on the first lines, with the
    # +BASH_COMMAND+ of the command holding the substitution, which is traced
    # after them: the hits which the first command of the trap was given
    # follow each of these, up to the last one, their real holder. Bash
    # traces the commands of a substitution on the line of its holder or
    # past it, so a command traced past them, even with the same text, holds
    # none of them.
    def restore_holder!(state, holder)
      settled = state.settled
      return unless settled
      return if settled.trap_call?(holder)

      held = settled.holder
      same_command = held.script == holder.script && held.command == holder.command
      return if same_command && held.index == holder.index

      state.settled = nil
      return unless same_command && state.pending.empty?
      # The commands of a function are on its own lines.
      return unless settled.counts.each_key.all? { |index, *, called| called || index >= holder.index }

      hits = @subshell_hits[holder.script]
      moved = Hash.new(0)
      settled.counts.each do |key, count|
        index, command, stale, holders, called = key
        hits[key] -= count
        hits.delete(key) unless hits[key].positive?
        moved_key = [index, command, stale, holders[...-1] + [holder.index], called]
        hits[moved_key] += count
        moved[moved_key] += count
      end
      # Another command of the trap may hold these hits next.
      state.settled = Settled.new(holder, moved)
    end

    # Gives the hits waiting at a subshell level above +depth+ the line of
    # this hit, which holds them: Bash traces the command holding a
    # substitution right after the commands of the substitution, one level
    # lower. They are counted once they reach level 0, see {#subshell_hits}.
    # A nil holder flushes outstanding hits at the end of the trace.
    def settle_subshell_hits!(state, depth, holder = nil)
      return if state.pending.empty?

      counts = Hash.new(0)
      state.pending.keys.select { |level| level > depth }.each do |level|
        state.pending.delete(level).each do |pending, count|
          hit = pending.held_by(holder)
          next unless hit

          if depth.zero?
            key = hit.coverage_key
            (@subshell_hits[hit.script] ||= Hash.new(0))[key] += count
            counts[key] += count if holder && hit.script == holder.script
          else
            (state.pending[depth] ||= Hash.new(0))[hit] += count
          end
        end
      end
      # Hits settled by a trap's function already have their real holder.
      # Preserve any older batch still waiting for the trap to finish.
      return if counts.empty? || state.settled&.trap_call?(holder)

      state.settled = Settled.new(holder, counts)
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
