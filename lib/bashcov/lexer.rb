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
      lines = File.read(@filename).encode("utf-8", invalid: :replace).lines
      count = lines.size
      lineno = 0

      while lineno < count
        line = lines[lineno]
        match = false

        # multi-line arrays
        match ||= mark_multiline(
          lines, lineno,
          /\A[^\n]*\b=\([^()]*\)/,
          forward: false,
        )

        # heredoc
        match ||= mark_multiline(
          lines, lineno,
          /\A[^\n]+<<-?\s*'?(\w+)'?.*$.*\1/m,
        )

        # multiline string concatenated with backslashes
        match ||= mark_multiline(
          lines, lineno,
          /\A[^\n]+\\$(\s*['"][^'"]*['"]\s*\\$){1,}\s*['"][^'"]*['"]\s*$/,
        )

        # simple line continuations with backslashes
        match ||= mark_multiline(
          lines, lineno,
          /\A([^\n&|;]*[^\\&|;](\\\\)*\\\n)+[^\n&|;]*[^\n\\&|;](\\\\)*$/,
        )

        # multiline string concatenated with newlines
        %w[' "].each do |char|
          match ||= mark_multiline(
            lines, lineno,
            /\A[^\s]+=#{char}[^#{char}]*#{char}/m,
            forward: false,
          )

          match ||= mark_multiline(
            lines, lineno,
            /\A[^\n]+[\s=]#{char}[^#{char}]*#{char}/m,
            forward: true,
          )
        end

        if match
          lineno = match # skip ahead if we match a multiline regexp
        else
          mark_line(line, lineno)
        end

        lineno += 1
      end
    end

  private

    def mark_multiline(lines, lineno, regexp, forward: true)
      seek_forward = lines[lineno..].join
      return unless (multiline_match = seek_forward.match(regexp))

      length = multiline_match.to_s.count($/)
      return if length.zero? # ignore false positive multiline match

      first, last = lineno + 1, lineno + length
      range = (forward ? first.upto(last) : (last - 1).downto(first - 1))
      reference_lineno = (forward ? first - 1 : last)

      range.each do |sub_lineno|
        # mark related lines with the same coverage as the reference line
        @coverage[sub_lineno] ||= @coverage[reference_lineno]
      end

      last
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
