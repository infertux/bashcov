# frozen_string_literal: true

require "bashcov/line"

module Bashcov
  # Simple lexer which analyzes Bash files in order to get information for
  # coverage
  class Lexer
    # Lines starting with one of these tokens are irrelevant for coverage
    IGNORE_START_WITH = %w[# function].freeze

    # Lines ending with one of these tokens are irrelevant for coverage
    IGNORE_END_WITH = %w[(].freeze

    # Lines containing only one of these keywords are irrelevant for coverage
    IGNORE_IS = %w[esac if then else elif fi while do done { } ;; ( )].freeze

    # @param [String] filename File to analyze
    # @param [Hash] coverage Coverage with executed lines marked
    # @raise [ArgumentError] if the given +filename+ is invalid.
    def initialize(filename, coverage)
      @filename = filename
      @coverage = coverage

      raise ArgumentError, "#{@filename} is not a file" unless File.file?(@filename)
    end

    # Process and complete initial coverage.
    # @return [void]
    def complete_coverage
      content = File.read(@filename).encode("utf-8", invalid: :replace)
      lines = content.lines
      offsets = lines.each_with_object([0]) { |line, memo| memo << (memo.last + line.size) }

      lines.each_with_index do |line, lineno|
        # multi-line arrays
        mark_multiline(
          content, offsets[lineno], lineno,
          /\G[^\n]*\b=\([^()]*\)/,
          forward: false,
        )

        # heredoc
        mark_multiline(
          content, offsets[lineno], lineno,
          /\G[^\n]+<<-?\s*'?(\w+)'?.*$.*\1/m,
        )

        # multiline string concatenated with backslashes
        mark_multiline(
          content, offsets[lineno], lineno,
          /\G[^\n]+\\$(\s*['"][^'"]*['"]\s*\\$){1,}\s*['"][^'"]*['"]\s*$/,
        )

        # simple line continuations with backslashes
        mark_multiline(
          content, offsets[lineno], lineno,
          /\G([^\n&|;]*[^\\&|;](\\\\)*\\\n)+[^\n&|;]*[^\n\\&|;](\\\\)*$/,
        )

        # multiline string concatenated with newlines
        [false, true].each do |direction|
          %w[' "].each do |char|
            mark_multiline(
              content, offsets[lineno], lineno,
              /\G[^\n]+[ \t=]+#{char}[^#{char}]*#{char}/m,
              forward: direction,
            )
          end
        end

        mark_line(line, lineno)
      end
    end

  private

    def mark_multiline(content, offset, lineno, regexp, forward: true)
      # +regexp+ is anchored with \G so it only matches from +offset+
      return unless (multiline_match = content.match(regexp, offset))

      length = multiline_match.to_s.count($/)
      first, last = lineno + 1, lineno + length

      # skip if we are already inside marked multiline string - only inner
      # lines are checked since Bash may report the hit on the last line
      # (e.g. `readonly` before Bash 5.3), which is also the next line when
      # the string spans only two lines
      return unless first.upto(last - 1).all? { |i| @coverage[i].nil? }

      range = (forward ? first.upto(last) : (last - 1).downto(first - 1))
      reference_lineno = (forward ? first - 1 : last)

      # don't seek backward if first line is already covered
      return if !forward && @coverage[first - 1]

      range.each do |sub_lineno|
        # mark related lines with the same coverage as the reference line
        @coverage[sub_lineno] ||= @coverage[reference_lineno]
      end
    end

    def mark_line(line, lineno)
      return unless @coverage[lineno] == Bashcov::Line::IGNORED

      @coverage[lineno] = Bashcov::Line::UNCOVERED if relevant?(line)
    end

    def relevant?(line)
      line.sub!(/\s#.*\Z/, "") # remove comments
      line.strip!

      return false if line.empty? ||
                      IGNORE_IS.include?(line) ||
                      line.start_with?(*IGNORE_START_WITH) ||
                      line.end_with?(*IGNORE_END_WITH)

      return false if line =~ /\A[a-zA-Z_@][a-zA-Z0-9_@\-:.]*\(\)/ # function declared without the `function` keyword
      return false if line =~ /\A[^)]+\)\Z/ # case statement selector, e.g. `--help)`

      true
    end
  end
end
