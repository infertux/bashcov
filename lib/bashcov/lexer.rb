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
    IGNORE_IS = %w[esac if then else elif fi while do done { } ;;].freeze

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

      lines.each_with_index do |line, lineno|
        # multi-line arrays
        mark_multiline(
          lines, lineno,
          /\A[^\n]*\b=\([^()]*\)/,
          forward: false
        )

        # heredoc
        mark_multiline(
          lines, lineno,
          /\A[^\n]+<<-?'?(\w+)'?.*$.*\1/m
        )

        # multiline string concatenated with backslashes
        mark_multiline(
          lines, lineno,
          /\A[^\n]+\\$(\s*['"][^'"]*['"]\s*\\$){1,}\s*['"][^'"]*['"]\s*$/
        )

        # simple line continuations with backslashes
        mark_multiline(
          lines, lineno,
          /\A([^\n&|;]*[^\\&|;](\\\\)*\\\n)+[^\n&|;]*[^\n\\&|;](\\\\)*$/
        )

        # multiline string concatenated with newlines
        %w[' "].each do |char|
          mark_multiline(
            lines, lineno,
            /\A[^\n]+[\s=]+#{char}[^#{char}]*#{char}/m,
            forward: false
          )
        end

        mark_line(line, lineno)
      end
    end

  private

    def mark_multiline(lines, lineno, regexp, forward: true)
      seek_forward = lines[lineno..].join
      return unless (multiline_match = seek_forward.match(regexp))

      length = multiline_match.to_s.count($/)
      first, last = lineno + 1, lineno + length
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

      relevant = true

      relevant &= false if line.empty? ||
                           IGNORE_IS.include?(line) ||
                           line.start_with?(*IGNORE_START_WITH) ||
                           line.end_with?(*IGNORE_END_WITH)

      relevant &= false if line =~ /\A[a-zA-Z_][a-zA-Z0-9_:]*\(\)/ # function declared without the `function` keyword
      relevant &= false if line =~ /\A[^)]+\)\Z/ # case statement selector, e.g. `--help)`

      relevant
    end
  end
end
