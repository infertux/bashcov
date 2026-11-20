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

    # Quoted text, or an escaped character
    QUOTED = /\\.|'[^']*'|"(?:\\.|[^"\\])*"/m

    # A command substitution on one line, which runs even in double quotes,
    # in normalized text
    SUBSTITUTION = /\$ \( [^()]* \)|` [^`]* `/

    # Text before a command which Bash traces: an operator, or reserved words
    # which start a compound command, in normalized text
    COMMAND_START = /(?:\A|[;&|()`] )(?:(?:if|then|else|elif|while|until|do|time|!|\{) )*\z/

    # @param [String] source normalized text of commands, see {.normalize}
    # @param [String] text normalized text of a command
    # @return [Boolean] whether +text+ is in +source+ as whole words where a
    #   command starts, out of quotes
    def self.names?(source, text)
      # quoted text blanked out, so that the operators it holds start nothing
      unquoted = source.gsub(QUOTED) do |quoted|
        case quoted[0]
        when "\\" then quoted
        when '"' then quoted.gsub(/#{SUBSTITUTION}|[^"]/) { |part| part.size > 1 ? part : "\0" }
        else quoted.tr("^'", "\0")
        end
      end
      !text.empty? && source.enum_for(:scan, /(?<!\S)#{Regexp.escape(text)}(?!\S)/).any? do
        unquoted[0...Regexp.last_match.begin(0)].match?(COMMAND_START)
      end
    end

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
    #   lines, comments and heredoc bodies
    def commands(lines, substitutions)
      substitutions.flat_map(&:groups).flat_map do |group|
        own_lines = lines.values_at(*group.own_lines)
        heredoc = own_lines.index { |line| line.match?(/<<(?!<)/) }
        written = (heredoc ? own_lines.first(heredoc + 1) : own_lines).join
        text = self.class.normalize(written.gsub(/#{QUOTED}|(?<!\S)#.*/) { |match| match.start_with?("#") ? "" : match })
        own = text.empty? ? [] : [[group.lines.first, text]]
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
      # hits of another process, such as a background job, may be on any line
      return if hits.filter_map { |(lineno, _, _, process), _| process unless lineno < lines.first }.uniq.size > 1

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
    #   Bash traces as +command+, see {.names?}
    def command_line(commands, command)
      text = self.class.normalize(command)
      targets = commands.select { |_, source| self.class.names?(source, text) }
      targets.first.first if targets.one?
    end
  end
end
