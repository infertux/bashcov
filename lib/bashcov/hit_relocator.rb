# frozen_string_literal: true

require "bashcov/command_text"
require "bashcov/hit_relocator/alignment"
require "bashcov/scanner"

module Bashcov
  # Moves the hits of the commands of a command substitution spanning several
  # lines back to the lines of these commands.
  #
  # Bash does not report these commands on their own lines. Bash 5.2 and later
  # rebuild the text of the substitution from its parsed form, one command
  # per line, and count lines from the line of the command which holds the
  # substitution; older versions count from about the same place in the
  # original text. Either way, the hits land on the lines which follow,
  # whatever they hold.
  #
  # Each hit traced in a subshell comes with the first line of the command
  # Bash ran (+BASH_COMMAND+). A hit landing near a command holding such a
  # substitution is moved to the command of that substitution whose text
  # matches, keeping the order in which the commands appear. A hit whose text
  # matches no command of the substitution stays where it is.
  class HitRelocator
    # How far after the command holding a substitution its hits can land, in
    # lines of that command: rebuilding the text can make it longer, e.g.
    # `if a; then b; fi` takes three lines
    SPREAD = 5

    # How far from its expected position the header of a +for+, +case+ or
    # +select+ command can be, in commands
    HEADER_SLACK = 2

    # Start of a command in a normalized text, see {CommandText.normalize}
    COMMAND_START = /(?:\A|[;&|(`] )/

    # Start of a +for+, +case+ or +select+ command, normalized
    HEADER = /#{COMMAND_START}(?:for|case|select) /

    # Start of a command or process substitution, normalized, see
    # {CommandText.normalize}
    OPENER = /\$\((?! \()|`|[<>] \(/

    # Expressions of the header of an arithmetic +for+ command, normalized
    ARITHMETIC_FOR = /#{COMMAND_START}for \( \( (.*?) \) \)/

    # Arithmetic command, normalized, see {CommandText.normalize}: since Bash 5.3, how
    # each expression of the header of an arithmetic +for+ command is traced
    ARITHMETIC = /\A\( \( (.*) \) \)\z/

    # Command inside a substitution
    # @!attribute lineno
    #   @return [Integer] its first line (0-based)
    # @!attribute text
    #   @return [String] its text, without the lines inside its own
    #     substitutions, see {CommandText.normalize}
    # @!attribute opening
    #   @return [String, nil] its first line if it holds substitutions: Bash
    #     traces the first line of the command as it rebuilt it, which also
    #     holds the first command of the substitution
    # @!attribute rank
    #   @return [Integer] its position among the commands of the substitutions
    #     of the same top-level command, in the lines Bash counts: one per
    #     command from Bash 5.2, its line as written before
    # @!attribute part
    #   @return [Integer] the substitution it is in, counted in the order of
    #     the text: Bash numbers the lines of each substitution on its own
    # @!attribute spread
    #   @return [Integer] how many more lines it spans than its first, not
    #     counting lines joined by a backslash: those of a heredoc or a
    #     quoted string, which Bash keeps when it rebuilds the text
    Candidate = Struct.new(:lineno, :text, :opening, :rank, :part, :spread) do
      def header?
        text.match?(HEADER)
      end
    end

    # Top-level command holding substitutions spanning several lines
    # @!attribute group
    #   @return [Scanner::Group]
    # @!attribute window
    #   @return [Range] lines where the hits of its substitutions can land
    # @!attribute candidates
    #   @return [Array<Candidate>] commands of its substitutions
    # @!attribute holder
    #   @return [String] its text up to the start of its first substitution,
    #     normalized: all of it that comes with a header run first in that
    #     substitution before Bash 5.2, and the start of it since
    # @!attribute loose
    #   @return [Boolean] whether the ranks of its candidates may not be the
    #     lines Bash counts: it keeps the lines of a heredoc or a quoted
    #     string spanning lines, in a layout of its own
    Region = Struct.new(:group, :window, :candidates, :holder, :loose) do
      def first_line
        group.lines.first
      end

      def covers?(lineno)
        group.lines.cover?(lineno)
      end

      # @return [Boolean] whether the traced command +text+ is the command
      #   of the region itself, the one holding the substitutions
      def own_command?(text)
        text.start_with?(holder)
      end
    end

    # Hit traced in a subshell: the fields of a key of
    # {Xtrace#subshell_hits}, the command normalized (see
    # {CommandText.normalize}), and how many times it was traced
    Traced = Data.define(:lineno, :text, :same_as_before, :holders, :function, :count)

    # @param [Array<String>] lines lines of the script
    # @param [Array<Scanner::Group>] groups groups of the script, see {Scanner}
    # @param [Boolean] deparsed whether Bash counts the lines of a
    #   substitution in the text it rebuilds from its parsed form, as from
    #   Bash 5.2, rather than in the text as written
    def initialize(lines, groups, deparsed: Gem::Version.new(Bashcov::BASH_VERSION) >= Gem::Version.new("5.2"))
      @lines = lines
      @groups = groups
      @deparsed = deparsed
      @matching = {}
      @quoted = {}
      @regions = groups.reject { |group| group.substitutions.empty? }.map { |group| region(group) }
    end

    # @param [Array<Integer, nil>] coverage hits by line (0-based)
    # @param [Hash{Array(Integer, String, Boolean, Array<Integer, nil>, String) => Integer}] subshell_hits
    #   number of hits traced in a subshell, see {Xtrace#subshell_hits}
    # @return [Array(Array<Integer, nil>, Array<Integer>)] the coverage with
    #   the hits moved, and the lines of the substitution commands which got
    #   hits from the trace, leaving out the substitutions of a command some
    #   hits of which could not be placed for sure: the commands which got no
    #   hit there may have run all the same
    def relocate(coverage, subshell_hits)
      coverage = coverage.dup
      return [coverage, []] if subshell_hits.empty? || @regions.empty?

      reached = []
      placed, unsure = assignments(subshell_hits)

      placed.each do |lineno, count, target|
        reached << target
        next if lineno == target

        coverage[lineno] = coverage[lineno].to_i - count
        coverage[lineno] = nil unless coverage[lineno].positive?
        coverage[target] = coverage[target].to_i + count
      end

      reached.reject! { |lineno| unsure.any? { |region| region.covers?(lineno) } }
      [coverage, reached.uniq]
    end

  private

    # @return [Array(Array<Array(Integer, Integer, Integer)>, Array<Region>)]
    #   for each hit to place, the line it was traced on, its count and the
    #   line of its command; and the regions some hits of which could not be
    #   placed for sure
    def assignments(subshell_hits)
      traced = subshell_hits.map do |(lineno, command, same_as_before, holders, function), count|
        Traced.new(lineno, CommandText.normalize(command.to_s), same_as_before, holders.to_a, function, count)
      end
      traced_holders = traced_holders(traced)
      # by identity: hashing a region hashes all its candidates
      sorted = {}.compare_by_identity
      unsure = {}.compare_by_identity

      traced.each do |hit|
        region, kind = sort_hit(hit, traced_holders)
        next unless region

        unsure[region] = true if kind == :unsure || (kind == :text && ambiguous?(region, hit.text))
        next if kind == :unsure

        hits = sorted[region] ||= { text: [], repeated: [], leading: [] }
        hits.fetch(kind) << [hit.lineno, hit.count, hit.text]
      end

      placed = sorted.flat_map do |region, hits|
        on_commands, sure = place(region, hits[:text], hits[:repeated], hits[:leading])
        unsure[region] = true unless sure
        on_commands
      end
      [placed, unsure.keys]
    end

    # @param [Traced] hit
    # @param [Array<Region>] traced_holders see {#traced_holders}
    # @return [Array(Region, Symbol), nil] the region +hit+ belongs to, and
    #   how to place it: by its +:text+; as a header, traced with the text of
    #   the command +:repeated+ before it or, +:leading+ its substitution,
    #   with that of the command holding it; or +:unsure+, when it tells that
    #   the hits of the region cannot be placed for sure. +nil+ for a hit to
    #   leave where it is.
    def sort_hit(hit, traced_holders)
      held_region = holder_region_of(hit.holders)
      # Bash traces the commands of a function defined out of the
      # substitution on their own lines, and the others somewhere past it
      if hit.function
        return [held_region, :unsure] if held_region && defines?(held_region, hit.function)

        return
      end

      if held_region
        # Background jobs can be interleaved with a substitution's commands.
        return [held_region, :unsure] if elsewhere?(held_region, hit, traced_holders)
        # A known holder's commands can land anywhere from its start onward.
        return if hit.lineno < held_region.first_line

        scope = [held_region]
      else
        scope = @regions.select { |region| region.window.cover?(hit.lineno) }
      end

      if hit.same_as_before
        header = closest_region(scope) { |region| region.candidates.any?(&:header?) }
        return [header, :repeated] if header
      end
      return if hit.text.empty?

      # Before Bash 5.2 the holder can be just its first line as written,
      # which also matches the opening line of the substitution.
      holder = scope.find { |region| region.own_command?(hit.text) }
      return [holder, held_region ? :leading : :repeated] if holder

      region = closest_region(scope) { |candidate| matching(candidate, hit.text).any? }
      if region
        local = command_at(hit.lineno, hit.text)
        return if !held_region && local && !region.covers?(hit.lineno)

        return [region, local&.substitutions&.empty? ? :unsure : :text]
      end
      [held_region, :unsure] if held_region
    end

    def closest_region(scope, &)
      scope.select(&).max_by(&:first_line)
    end

    # @return [Boolean] whether the command +text+ cannot be told from
    #   another one of +region+: the substitutions of a command are traced
    #   from the same line, and telling the commands of a loose region apart
    #   takes their positions
    def ambiguous?(region, text)
      candidates = matching(region, text)
      return false if candidates.size < 2

      region.loose || candidates.any? { |candidate| candidate.part != candidates.first.part }
    end

    # @param [Array<Array(Integer, Integer, String)>] by_text, repeated, leading
    #   line, count and text of the hits of +region+, see {#sort_hit}
    # @return [Array(Array<Array(Integer, Integer, Integer)>, Boolean)] these
    #   hits with the lines of their commands, and whether all of them could
    #   be placed for sure
    def place(region, by_text, repeated, leading)
      first = leading_header(region, leading)
      others = first.empty? ? repeated + leading : repeated
      placed, anchored = align_by_text(region, by_text, first)
      headers, remaining = place_headers(region, others, placed + first)
      kept = remaining.select do |lineno, _, text|
        !text.empty? && region.window.cover?(lineno) && matching(region, text).any? &&
          (region.covers?(lineno) || !command_at(lineno, text))
      end
      placed, anchored = align_by_text(region, by_text + kept, first) unless kept.empty?
      [placed + headers + first, anchored && kept.size == remaining.size]
    end

    def align_by_text(region, hits, first)
      by_text = hits.group_by(&:last).map { |text, group| [group.sort, matching(region, text)] }
      leading = first.map { |lineno, _, target| [lineno, rank_at(region, target)] }
      Alignment.place(by_text, leading)
    end

    # A header run first in a substitution, traced with the command which
    # holds it, is the first command of the substitutions of +region+, if
    # that is a header: the first candidate past the first line, unless that
    # line holds a header itself.
    # @param [Array<Array(Integer, Integer, String)>] hits such hits
    # @return [Array<Array(Integer, Integer, Integer)>] them placed on that
    #   header, none if it is not one
    def leading_header(region, hits)
      header = region.candidates.find { |candidate| candidate.header? || candidate.lineno > region.first_line }
      return [] unless header&.header?

      hits.map { |lineno, count, _| [lineno, count, header.lineno] }
    end

    # Bash does not update +BASH_COMMAND+ for the header of a +for+, +case+
    # or +select+ command: it traces it with the command traced before. Such
    # a hit goes to the header found at its position, counted from the hit
    # placed first.
    # @return [Array(Array<Array(Integer, Integer, Integer)>, Array)] the hits
    #   placed on a header, and the others
    def place_headers(region, hits, placed)
      return [[], hits] if hits.empty? || placed.empty?

      anchor_line, _, anchor_target = placed.min_by(&:first)
      anchor_rank = rank_at(region, anchor_target)
      headers = region.candidates.select(&:header?)

      hits.each_with_object([[], []]) do |(lineno, count, text), (on_headers, others)|
        expected = anchor_rank + (lineno - anchor_line)
        header = headers.min_by { |candidate| (candidate.rank - expected).abs }
        if header && (header.rank - expected).abs <= HEADER_SLACK
          on_headers << [lineno, count, header.lineno]
        else
          others << [lineno, count, text]
        end
      end
    end

    # @return [Integer] the {Candidate#rank} of the candidate on +lineno+
    def rank_at(region, lineno)
      region.candidates.find { |candidate| candidate.lineno == lineno }.rank
    end

    # @param [Array<Integer, nil>] holders lines of the commands which held
    #   the substitution a hit was traced in, innermost first, see
    #   {Xtrace#subshell_hits}: that of a nested substitution is a line Bash
    #   made up
    # @return [Region, nil] the region of the outermost of these commands
    #   whose substitutions may hold the next one: the line of a command in a
    #   substitution is one Bash made up, which may fall in another region,
    #   and the line of a command after a subshell is no holder of it
    def holder_region_of(holders)
      holders.each_with_index.reverse_each do |line, index|
        region = line && @regions.find { |candidate| candidate.covers?(line) }
        next unless region

        inner = holders[index - 1] if index.positive?
        return region if inner.nil? || inner >= region.first_line
      end
      nil
    end

    # @param [Array<Traced>] traced
    # @return [Array<Region>] the regions whose own command, holding the
    #   substitutions, was traced in a subshell on its own lines
    def traced_holders(traced)
      traced.reject(&:function).flat_map do |hit|
        @regions.select { |region| region.covers?(hit.lineno) && region.own_command?(hit.text) }
      end
    end

    # @param [Array<Region>] traced_holders see {#traced_holders}
    # @return [Boolean] whether +hit+, which +region+ held, may come from
    #   another command holding substitutions, which ran in a subshell: it
    #   is that command, or one of the commands of its substitutions, held
    #   by a line of it
    def elsewhere?(region, hit, traced_holders)
      inner_holders = hit.holders[...-1].compact
      traced_holders.any? do |other|
        next false if other.equal?(region)

        (other.covers?(hit.lineno) && other.own_command?(hit.text)) ||
          (inner_holders.any? { |holder| other.covers?(holder) } && matching(other, hit.text).any?)
      end
    end

    # @return [Boolean] whether the text of +region+ may define the function
    #   +name+
    def defines?(region, name)
      name = Regexp.escape(name)
      definition = /(?:\A|[\s;&|(){}])(?:function\s+#{name}(?=[\s(]|\z)|#{name}\s*\(\s*\))/
      @lines[region.group.lines].join.gsub("\\\n", "").match?(definition)
    end

    # @return [Scanner::Group, nil] the top-level command on +lineno+ if it
    #   is the traced command +text+: Bash may trace a command spanning
    #   lines, such as one with a quoted string, on its last line
    def command_at(lineno, text)
      group = @groups.find { |candidate| candidate.lines.cover?(lineno) }
      group if group && matches?(CommandText.normalized_code(@lines[group.lines].join), text)
    end

    def region(group)
      window = group.lines.first..(group.lines.last + (SPREAD * group.lines.size))
      candidates = commands(group.substitutions).sort_by(&:lineno).uniq(&:lineno)
      # Bash rebuilds the text one command per line, comments and blank
      # lines dropped; before, it keeps the lines as written
      candidates.each_with_index { |candidate, rank| candidate.rank = @deparsed ? rank : candidate.lineno }
      loose = @deparsed && candidates.any? { |candidate| candidate.spread.positive? || CommandText.compact?(candidate.text) }
      Region.new(group, window, candidates, holder(group), loose)
    end

    # @return [String] see {Region#holder}
    def holder(group)
      first_substitution = group.substitutions.map { |substitution| substitution.lines.first }.min
      text = CommandText.normalize(@lines[group.lines.first..first_substitution].join)
      opener = text.match(OPENER)
      opener ? opener.pre_match + opener[0] : text
    end

    # @return [Array<Candidate>] the commands of +substitutions+, nested ones
    #   included
    # @param [Enumerator] parts numbers for {Candidate#part}
    def commands(substitutions, parts = (0..).each)
      substitutions.flat_map do |substitution|
        part = parts.next
        substitution.groups.flat_map do |group|
          own = candidate(group, part)
          nested = commands(group.substitutions, parts)
          own ? nested.unshift(own) : nested
        end
      end
    end

    def candidate(group, part)
      own_lines = group.own_lines
      text = CommandText.normalized_code(@lines.values_at(*own_lines).join)
      opening = CommandText.normalize(@lines[group.lines.first]) unless group.substitutions.empty?
      # Bash drops comments and blank lines while rebuilding a substitution.
      return if text.empty? && opening.nil?

      spread = own_lines[...-1].count { |lineno| !@lines[lineno].end_with?("\\\n") }
      Candidate.new(group.lines.first, text, opening, nil, part, spread)
    end

    # @return [Array<Candidate>] the candidates of +region+ which the traced
    #   command +text+ can be
    def matching(region, text)
      @matching[[region.object_id, text]] ||= region.candidates.select { |candidate| candidate_matches?(candidate, text) }
    end

    # @return [Boolean] whether the traced command +text+ is +candidate+
    def candidate_matches?(candidate, text)
      matches?(candidate.text, text) || (candidate.opening && text.start_with?(candidate.opening)) ||
        arithmetic_for_expression?(candidate, text)
    end

    # @return [Boolean] whether the traced command +text+ is an expression of
    #   +candidate+, an arithmetic +for+ command
    def arithmetic_for_expression?(candidate, text)
      expression = text[ARITHMETIC, 1]
      clauses = candidate.text[ARITHMETIC_FOR, 1] if expression
      return false unless clauses

      # Bash traces an omitted expression as `((1))`
      clauses.split(/ ?; ?/, -1).map { |clause| clause.empty? ? "1" : clause }.include?(expression)
    end

    # @return [Boolean] see {CommandText.matches?}
    def matches?(source, text)
      CommandText.matches?(source, text, @quoted)
    end
  end
end
