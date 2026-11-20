# frozen_string_literal: true

require "bashcov/hit_relocator"
require "bashcov/line"
require "bashcov/scanner"

module Bashcov
  # Simple lexer which analyzes Bash files in order to get information for
  # coverage
  class Lexer
    # Lines starting with one of these tokens are irrelevant for coverage
    IGNORE_START_WITH = %w[#].freeze

    # Lines starting with one of these keywords are irrelevant for coverage
    IGNORE_KEYWORDS = /\Afunction\s/

    # Lines ending with one of these tokens are irrelevant for coverage
    IGNORE_END_WITH = %w[(].freeze

    # Lines containing only one of these keywords are irrelevant for coverage
    IGNORE_IS = %w[esac if then else elif fi while do done { } ;; ( )].freeze

    # @param [String] filename File to analyze
    # @param [Array<Integer, nil>] coverage Coverage with executed lines marked
    # @param [Hash{Array(Integer, String, Boolean) => Integer}] subshell_hits hits
    #   traced in a subshell, see {Xtrace#subshell_hits}
    # @raise [ArgumentError] if the given +filename+ is invalid.
    def initialize(filename, coverage, subshell_hits = {})
      @filename = filename
      @coverage = coverage
      @subshell_hits = subshell_hits

      raise ArgumentError, "#{@filename} is not a file" unless File.file?(@filename)
    end

    # Process and complete initial coverage.
    # @return [void]
    def complete_coverage
      content = File.read(@filename).encode("utf-8", invalid: :replace)
      lines = content.lines

      groups = Bashcov::Scanner.new(content).groups

      relocated, @reached = Bashcov::HitRelocator.new(lines, groups).relocate(@coverage, @subshell_hits)
      # hits which Bash traced past the end of the file have no line to go to
      @coverage.replace(relocated.first(lines.size))

      groups.each { |group| mark_group(lines, group) }
    end

  private

    # Marks the lines of a command with the same coverage, since Bash reports
    # the hit of a command spanning several lines (e.g. a multiline string or
    # a heredoc) on one of them only: the first one, or the last one for some
    # commands such as `readonly` before Bash 5.3.
    #
    # The commands of a substitution spanning several lines get the hits
    # which {HitRelocator} moved back to them. If none of them got any, they
    # are marked like the command which holds the substitution when that
    # command ran, since there is then no telling which of them ran.
    # @param [Array<String>] lines Lines of the file
    # @param [Scanner::Group] group Lines of the command
    # @param [Integer, nil] inherited Hit of the command which holds this
    #   one in a substitution, if it ran
    def mark_group(lines, group, inherited = nil)
      own_lines = group.own_lines
      hit = own_lines.filter_map { |lineno| @coverage[lineno] }.first
      hit ||= inherited || Bashcov::Line::UNCOVERED if relevant?(lines[group.lines.first])

      if hit
        own_lines.each { |lineno| @coverage[lineno] ||= hit }
      else
        # the command starts on a line which is not relevant itself, e.g.
        # `function f() { echo "a` - judge each line on its own
        own_lines.each { |lineno| mark_line(lines[lineno], lineno) }
      end

      inherited = hit if hit&.positive?
      group.substitutions.each do |substitution|
        fallback = inherited unless reached?(substitution)
        substitution.groups.each { |nested| mark_group(lines, nested, fallback) }
      end
    end

    # @return [Boolean] whether a command of +substitution+ got a hit from the
    #   trace
    def reached?(substitution)
      @reached.any? { |lineno| substitution.lines.cover?(lineno) }
    end

    def mark_line(line, lineno)
      return unless @coverage[lineno] == Bashcov::Line::IGNORED

      @coverage[lineno] = Bashcov::Line::UNCOVERED if relevant?(line)
    end

    def relevant?(line)
      line = line.sub(/\s#.*\Z/, "").strip # remove comments

      return false if line.empty? ||
                      IGNORE_IS.include?(line) ||
                      line.start_with?(*IGNORE_START_WITH) ||
                      line.match?(IGNORE_KEYWORDS) ||
                      line.end_with?(*IGNORE_END_WITH)

      return false if line =~ /\A[a-zA-Z_@][a-zA-Z0-9_@\-:.]*\(\)/ # function declared without the `function` keyword
      return false if line =~ /\A[^)]+\)\Z/ # case statement selector, e.g. `--help)`

      true
    end
  end
end
