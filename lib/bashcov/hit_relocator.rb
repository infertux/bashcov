# frozen_string_literal: true

module Bashcov
  # Moves the hits of the commands of command substitutions spanning several
  # lines back to their own lines. Bash reports these commands on shifted
  # lines, counted from about the last line of the command which holds the
  # substitution, so Bashcov matches them by their text instead: a hit goes
  # to the one command of the substitutions of its holder (see
  # {Xtrace#subshell_hits}) which has that text. When any hit of a holder
  # cannot be placed so, none is: the {Lexer} then marks the commands of its
  # substitutions like the command which holds them. Neither is any hit of
  # a holder on whose lines hits of another holder were left.
  class HitRelocator
    # Commands which Bash traces with the text of the command before them
    # (loop and +case+ headers), with another text (+$'...'+ and +$"..."+
    # strings), whose commands it traces on lines of their own (functions)
    # or not right before the command holding them (process substitutions),
    # in normalized text, see {.normalize}
    UNTRACEABLE = /(?:\A|[;&|(] )(?:for|case|select|function) |(?:\A|[;&|] )[\w.:-]+ \( \)|[<>] \(|\$['"]/

    # @param [String] text text of a command, as written or as Bash traces it
    # @return [String] +text+ with line continuations joined, operators
    #   apart and single blanks, as Bash 5.2 rebuilds it, and without the
    #   default file descriptor of a duplication (+1>&2+ is +>&2+)
    def self.normalize(text)
      text.scrub
          .gsub(/(?<!\\)((?:\\\\)*)\\\n/, '\1')
          .gsub(/(?<!\S)(?:1(?=>&)|0(?=<&))/, "")
          .gsub(/[;&|<>()`]/) { |operator| " #{operator} " }
          .split.join(" ")
    end

    # @param [Array<String>] lines lines of the script
    # @param [Array<Scanner::Group>] groups commands of the script, see
    #   {Scanner#groups}
    def initialize(lines, groups)
      # for each command holding substitutions, the line and text of each
      # command they hold, nested ones included
      @holders = groups.reject { |group| group.substitutions.empty? }.to_h do |group|
        [group.lines, commands(lines, group.substitutions)]
      end
    end

    # @param [Array<Integer, nil>] coverage hits by line (0-based)
    # @param [Hash{Array(Integer, String, Integer) => Integer}] subshell_hits
    #   see {Xtrace#subshell_hits}
    # @return [Array(Array<Integer, nil>, Array<Integer>)] the coverage with
    #   the hits moved, and the lines they were moved to
    def relocate(coverage, subshell_hits)
      coverage = coverage.dup
      reached = []
      by_holder = subshell_hits.group_by { |(_, _, holder), _| @holders.find { |lines, _| lines.cover?(holder) } }
      placed = settle(by_holder, by_holder.to_h { |holder, hits| [holder, placements(holder, hits)] })

      placed.each_value do |moves|
        moves&.each do |lineno, count, target|
          coverage[lineno] -= count
          coverage[lineno] = nil if coverage[lineno].zero?
          coverage[target] = coverage[target].to_i + count
          reached << target
        end
      end
      [coverage, reached.uniq]
    end

  private

    # @return [Array<Array(Integer, String)>] the line and text of the
    #   commands of +substitutions+, nested ones included, leaving out blank
    #   lines and comments
    def commands(lines, substitutions)
      substitutions.flat_map(&:groups).flat_map do |group|
        text = self.class.normalize(lines.values_at(*group.own_lines).join)
        own = text.empty? || text.start_with?("#") ? [] : [[group.lines.first, text]]
        own + commands(lines, group.substitutions)
      end
    end

    # @param [Array(Range, Array<Array(Integer, String)>), nil] holder lines
    #   of the command which holds the hits and its commands, see {#commands}
    # @param [Array<Array(Array(Integer, String, Integer), Integer)>] hits
    # @return [Array<Array(Integer, Integer, Integer)>, nil] the line, count
    #   and line of the command of each hit, nil if one cannot be placed
    def placements(holder, hits)
      lines, commands = holder
      return if lines.nil? || commands.any? { |_, text| text.match?(UNTRACEABLE) }

      placed = hits.filter_map do |(lineno, command, _), count|
        # a hit traced before the substitution, e.g. of a pipeline, is on its
        # own line
        [lineno, count, command_line(commands, command)] unless lineno < lines.first
      end
      placed if placed.all?(&:last)
    end

    # @param [Hash{Array => Array<Array>}] by_holder hits by holder
    # @param [Hash{Array => Array<Array>, nil}] placed placements by holder,
    #   see {#placements}
    # @return [Hash{Array => Array<Array>, nil}] +placed+ without the
    #   placements of the holders on whose lines hits were left: these lines
    #   hold hits of other commands
    def settle(by_holder, placed)
      left = by_holder.flat_map { |holder, hits| placed[holder] ? [] : hits.map { |(lineno, *), _| lineno } }
      settled = placed.to_h do |holder, moves|
        [holder, (moves if moves && left.none? { |lineno| holder.first.cover?(lineno) })]
      end
      settled == placed ? settled : settle(by_holder, settled)
    end

    # @return [Integer, nil] the line of the one command of +commands+ which
    #   Bash traces as +command+, as whole words
    def command_line(commands, command)
      text = self.class.normalize(command)
      targets = commands.select { |_, source| source.match?(/(?<!\S)#{Regexp.escape(text)}(?!\S)/) }
      targets.first.first if targets.one? && !text.empty?
    end
  end
end
