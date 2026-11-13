# frozen_string_literal: true

require "bashcov/command_text"
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

    # Distance added for a candidate out of the ranks a hit can have, see
    # {#expected_rank}, so that it is used only if no other one fits
    OUT_OF_BOUNDS = 1_000

    # Start of a +for+, +case+ or +select+ command, see {CommandText.normalize}
    HEADER = /(?:\A|[;&|(`] )(?:for|case|select) /

    # Start of a command or process substitution, normalized, see
    # {#normalize}
    OPENER = /\$ \((?! \()|`|[<>] \(/

    # Expressions of the header of an arithmetic +for+ command, normalized,
    # see {CommandText.normalize}
    ARITHMETIC_FOR = /(?:\A|[;&|(`] )for \( \( (.*?) \) \)/

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
    Candidate = Struct.new(:lineno, :text, :opening, :rank, :part, :spread)

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
    Region = Struct.new(:group, :window, :candidates, :holder, :loose)

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
      reached = []
      placed, unsure = assignments(subshell_hits)

      placed.each do |lineno, count, target|
        reached << target
        next if lineno == target

        coverage[lineno] = coverage[lineno].to_i - count
        coverage[lineno] = nil unless coverage[lineno].positive?
        coverage[target] = coverage[target].to_i + count
      end

      reached.reject! { |lineno| unsure.any? { |region| region.group.lines.cover?(lineno) } }
      [coverage, reached.uniq]
    end

  private

    # @return [Array(Array<Array(Integer, Integer, Integer)>, Array<Region>)]
    #   for each hit to place, the line it was traced on, its count and the
    #   line of its command; and the regions some hits of which could not be
    #   placed for sure
    def assignments(subshell_hits)
      # by identity: hashing a region hashes all its candidates
      sorted = Hash.new { |hash, region| hash[region] = Hash.new { |kinds, kind| kinds[kind] = [] } }.compare_by_identity
      unsure = {}.compare_by_identity
      traced_holders = traced_holders(subshell_hits)

      subshell_hits.each do |(lineno, command, same_as_before, holders, function), count|
        text = normalize(command.to_s)
        region, kind = sort_hit(lineno, text, same_as_before, holders, function, traced_holders)
        next unless region

        unsure[region] = true if kind == :unsure || (kind == :text && ambiguous?(region, text))
        sorted[region][kind] << [lineno, count, text] unless kind == :unsure
      end

      placed = sorted.flat_map do |region, hits|
        on_commands, sure = place(region, hits[:text], hits[:repeated], hits[:leading])
        unsure[region] = true unless sure
        on_commands
      end
      [placed, unsure.keys]
    end

    # @param [Boolean] same_as_before whether the hit was traced with the
    #   text of the command before it, as the header of a +for+, +case+ or
    #   +select+ command is
    # @return [Array(Region, Symbol), nil] the region a hit belongs to, and
    #   how to place it: by its +:text+; as a header, traced with the text of
    #   the command +:repeated+ before it or, +:leading+ its substitution,
    #   with that of the command holding it; or +:unsure+, when it tells that
    #   the hits of the region cannot be placed for sure. +nil+ for a hit to
    #   leave where it is.
    def sort_hit(lineno, text, same_as_before, holders, function, traced_holders)
      held_region = holder_region_of(holders)
      held = !held_region.nil?
      # Bash traces the commands of a function defined out of the
      # substitution on their own lines, and the others somewhere past it
      return ([held_region, :unsure] if held && defines?(held_region, function)) if function
      # a command which ran in another process, such as a background job,
      # is traced among those of the substitutions and held like them
      return [held_region, :unsure] if held && elsewhere?(held_region, lineno, text, holders, traced_holders)

      scope = held ? [held_region] : @regions
      header_region = header_region_for(lineno, scope, held:) if same_as_before
      return [header_region, :repeated] if header_region
      return if text.empty?

      # a header run first in a substitution comes with the command which
      # holds the substitution. Before Bash 5.2, that is only its first
      # line as written, which also matches the first line of the
      # substitution.
      holder_region = holder_region_for(lineno, text, scope, held:)
      return [holder_region, held ? :leading : :repeated] if holder_region

      region = region_for(lineno, text, scope, held:)
      if region
        # another process, such as a background job, may trace its own
        # commands among those of the substitutions: a hit on the lines of
        # the same command, which holds no substitution spanning lines,
        # stays there
        [region, command_at(lineno, text)&.substitutions&.empty? ? :unsure : :text]
      elsif held && reach?(held_region, lineno, held)
        [held_region, :unsure]
      end
    end

    # @return [Boolean] whether the command +text+ cannot be told from
    #   another one of +region+: the substitutions of a command are traced
    #   from the same line, and telling the commands of a loose region apart
    #   takes their positions
    def ambiguous?(region, text)
      candidates = matching(region, text)
      candidates.uniq(&:part).size > 1 || (region.loose && candidates.size > 1)
    end

    # @param [Array<Array(Integer, Integer, String)>] by_text, repeated, leading
    #   line, count and text of the hits of +region+, see {#sort_hit}
    # @return [Array(Array<Array(Integer, Integer, Integer)>, Boolean)] these
    #   hits with the lines of their commands, and whether all of them could
    #   be placed for sure
    def place(region, by_text, repeated, leading)
      first = leading_header(region, leading)
      others = first.empty? ? repeated + leading : repeated
      placed = align_by_text(region, by_text, first)
      headers, others = place_headers(region, others, placed + first)
      kept = others.select { |lineno, _, text| !text.empty? && region_for(lineno, text, [region]) }
      placed = align_by_text(region, by_text + kept, first) unless kept.empty?
      [placed + headers + first, kept.size == others.size && !guessed?(region, by_text + kept, first)]
    end

    # A header run first in a substitution, traced with the command which
    # holds it, is the first command of the substitutions of +region+, if
    # that is a header: the first candidate past the first line, unless that
    # line holds a header itself.
    # @param [Array<Array(Integer, Integer, String)>] hits such hits
    # @return [Array<Array(Integer, Integer, Integer)>] them placed on that
    #   header, none if it is not one
    def leading_header(region, hits)
      header = region.candidates.find { |candidate| header?(candidate) || candidate.lineno > region.group.lines.first }
      return [] unless header && header?(header)

      hits.map { |lineno, count, _| [lineno, count, header.lineno] }
    end

    # @param [Array<Array(Integer, Integer, String)>] hits line, count and
    #   text of the hits of +region+
    # @param [Array<Array(Integer, Integer, Integer)>] first hits placed on
    #   the first command of the substitutions, see {#leading_header}
    # @return [Array<Array(Integer, Integer, Integer)>]
    def align_by_text(region, hits, first = [])
      return [] if hits.empty?

      by_text = hits.group_by(&:last).map do |text, hits_of_text|
        candidates = matching(region, text)
        [hits_of_text.map { |lineno, count, _| [lineno, count] }.sort, candidates]
      end
      leading = first.map { |lineno, _, target| [lineno, rank_at(region, target)] }
      anchors = (anchors(by_text) + leading).sort
      anchors = [[hits.map(&:first).min, 0]] if anchors.empty?

      by_text.flat_map do |hits_of_text, candidates|
        expected = hits_of_text.map { |lineno, _| expected_rank(anchors, lineno) }
        align(hits_of_text, candidates, expected)
      end
    end

    # @return [Boolean] whether there is no telling where the +hits+ of
    #   +region+ go: none of them matches a single candidate, which the
    #   others are placed from, see {#align_by_text}
    def guessed?(region, hits, first)
      return false unless first.empty?

      candidates = hits.map(&:last).uniq.map { |text| matching(region, text).size }
      candidates.any? { |count| count > 1 } && candidates.none?(1)
    end

    # @return [Array<Array(Integer, Integer)>] the line and the rank of the
    #   candidate of each hit whose text matches a single candidate
    def anchors(by_text)
      by_text.select { |_, candidates| candidates.one? }.flat_map do |hits_of_text, (candidate)|
        hits_of_text.map { |lineno, _| [lineno, candidate.rank] }
      end
    end

    # Bash traces the commands of a substitution in the order of the text,
    # about one per line, so a hit is expected as many commands after the
    # closest anchor before it as it is lines after it, and between the
    # anchors around it.
    # @return [Array(Integer, Range)] the rank of the candidate expected for
    #   a hit on +lineno+, and the ranks it can have
    def expected_rank(anchors, lineno)
      before = anchors.select { |line, _| line <= lineno }
      after = anchors.select { |line, _| line > lineno }
      anchor_line, anchor_rank = before.last || anchors.first
      lowest = before.empty? ? 0 : before.last.last
      highest = after.empty? ? Float::INFINITY : after.first.last - 1

      [anchor_rank + (lineno - anchor_line), lowest..highest]
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
      headers = region.candidates.select { |candidate| header?(candidate) }

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

    # @return [Boolean] whether +candidate+ starts a +for+, +case+ or
    #   +select+ command
    def header?(candidate)
      candidate.text.match?(HEADER)
    end

    # @return [Region, nil] the closest region holding a header whose hits
    #   may land on +lineno+
    def header_region_for(lineno, scope, held: false)
      scope.select { |region| reach?(region, lineno, held) && region.candidates.any? { |candidate| header?(candidate) } }
           .max_by { |region| region.group.lines.first }
    end

    # @return [Region, nil] the region whose own command, holding the
    #   substitutions, is +text+
    def holder_region_for(lineno, text, scope, held: false)
      scope.find { |region| reach?(region, lineno, held) && text.start_with?(region.holder) }
    end

    # @param [Boolean] held whether the hit is known to have +region+ as its
    #   holder
    # @return [Boolean] whether a hit of the substitutions of +region+ can
    #   land on +lineno+: its window is only a guess of how far Bash spreads
    #   them, e.g. it rebuilds a +case+ command written on one line on three
    #   lines for each of its clauses, so a hit which the command held can be
    #   anywhere after its start
    def reach?(region, lineno, held)
      held ? lineno >= region.group.lines.first : region.window.cover?(lineno)
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
      lines = holders.to_a
      lines.each_index.reverse_each do |index|
        line = lines[index]
        region = @regions.find { |candidate| candidate.group.lines.cover?(line) } if line
        next unless region

        inner = lines[index - 1] if index.positive?
        return region if inner.nil? || reach?(region, inner, true)
      end
      nil
    end

    # @return [Array<Region>] the regions whose own command, holding the
    #   substitutions, was traced in a subshell on its own lines
    def traced_holders(subshell_hits)
      subshell_hits.each_key.flat_map do |lineno, command, _, _, function|
        next [] if function

        text = normalize(command.to_s)
        @regions.select { |region| region.group.lines.cover?(lineno) && text.start_with?(region.holder) }
      end
    end

    # @param [Array<Integer, nil>] holders see {#holder_region_of}
    # @param [Array<Region>] traced_holders see {#traced_holders}
    # @return [Boolean] whether a hit which +region+ held may come from
    #   another command holding substitutions, which ran in a subshell: it
    #   is that command, or one of the commands of its substitutions, held
    #   by a line of it
    def elsewhere?(region, lineno, text, holders, traced_holders)
      inner_holders = holders.to_a[...-1].compact
      traced_holders.any? do |other|
        next false if other.equal?(region)

        lines = other.group.lines
        (lines.cover?(lineno) && text.start_with?(other.holder)) ||
          (inner_holders.any? { |holder| lines.cover?(holder) } && !matching(other, text).empty?)
      end
    end

    # @return [Boolean] whether the text of +region+ may define the function
    #   +name+
    def defines?(region, name)
      name = Regexp.escape(name)
      definition = /(?:\A|[\s;&|(){}])(?:function\s+#{name}(?=[\s(]|\z)|#{name}\s*\(\s*\))/
      @lines[region.group.lines].join.gsub("\\\n", "").match?(definition)
    end

    # @param [Boolean] held whether the hit is known to come from the
    #   substitutions of the region of +scope+
    # @return [Region, nil] the region of +scope+ whose substitutions may
    #   hold the command +text+ traced on +lineno+: the closest one starting
    #   at or before that line
    def region_for(lineno, text, scope = @regions, held: false)
      region = scope.select { |candidate| reach?(candidate, lineno, held) && !matching(candidate, text).empty? }
                    .max_by { |candidate| candidate.group.lines.first }
      return unless region
      # a command outside the region which matches is a command of its own,
      # e.g. a part of a pipeline, traced on its own line
      return if !held && !region.group.lines.cover?(lineno) && command_at(lineno, text)

      region
    end

    # @return [Scanner::Group, nil] the top-level command on +lineno+ if it
    #   is the traced command +text+: Bash may trace a command spanning
    #   lines, such as one with a quoted string, on its last line
    def command_at(lineno, text)
      group = @groups.find { |candidate| candidate.lines.cover?(lineno) }
      group if group && matches?(normalize(CommandText.code(@lines[group.lines].join)), text)
    end

    # Pairs the hits, sorted by line, with the matching candidates in order,
    # so that the expected ranks of the hits and the ranks of their commands
    # stay as close as possible.
    # @param [Array<Array(Integer, Range)>] expected see {#expected_rank},
    #   for each hit
    # @return [Array<Array(Integer, Integer, Integer)>]
    def align(hits, candidates, expected)
      return [] if candidates.empty?

      distances = expected.map do |rank, bounds|
        candidates.map { |candidate| (rank - candidate.rank).abs + (bounds.cover?(candidate.rank) ? 0 : OUT_OF_BOUNDS) }
      end
      choice = cheapest_alignment(distances, hits.size > candidates.size)

      hits.zip(choice).map { |(lineno, count), index| [lineno, count, candidates[index].lineno] }
    end

    # @param [Array<Array<Integer>>] distances distance between each hit and
    #   each candidate
    # @param [Boolean] shared whether several hits may go to the same
    #   candidate, when there are more hits than candidates
    # @return [Array<Integer>] for each hit, the index of its candidate, in
    #   increasing order, which minimizes the sum of the distances
    def cheapest_alignment(distances, shared)
      # for each candidate, the lowest cost of placing the hits read so far
      # with the last one on it, and the candidates of these hits, the last
      # one first, as a linked list
      costs = distances.first.each_with_index.map { |distance, candidate| [distance, [candidate, nil]] }
      distances.drop(1).each do |row|
        before = costs
        lowest = nil
        costs = row.each_with_index.map do |distance, candidate|
          reachable = shared ? before[candidate] : (before[candidate - 1] if candidate.positive?)
          lowest = reachable if reachable && (lowest.nil? || reachable.first < lowest.first)
          [lowest.first + distance, [candidate, lowest.last]] if lowest
        end
      end

      path = costs.compact.min_by(&:first).last
      Array.new(distances.size) { path.first.tap { path = path.last } }.reverse
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

    # @return [Integer] see {Candidate#spread}
    def spread(group)
      group.own_lines[...-1].count { |lineno| !@lines[lineno].end_with?("\\\n") }
    end

    # @return [String] see {Region#holder}
    def holder(group)
      first_substitution = group.substitutions.map { |substitution| substitution.lines.first }.min
      text = normalize(@lines[group.lines.first..first_substitution].join)
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
          text = normalize(CommandText.code(@lines.values_at(*group.own_lines).join))
          opening = normalize(@lines[group.lines.first]) unless group.substitutions.empty?
          # a comment is no command, and Bash drops it when rebuilding the text
          own = text.empty? && opening.nil? ? [] : [Candidate.new(group.lines.first, text, opening, nil, part, spread(group))]
          own + commands(group.substitutions, parts)
        end
      end
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

    # @return [String] see {CommandText.normalize}
    def normalize(text)
      CommandText.normalize(text)
    end
  end
end
