# frozen_string_literal: true

require "bashcov/line"

module Bashcov
  # Simple lexer which analyzes Bash files in order to get information for
  # coverage
  class Lexer
    # Lines starting with one of these tokens are irrelevant for coverage
    IGNORE_START_WITH = %w(# function).freeze

    # Lines ending with one of these tokens are irrelevant for coverage
    IGNORE_END_WITH = %w|(|.freeze

    # Lines containing only one of these keywords are irrelevant for coverage
    IGNORE_IS = %w(esac if then else elif fi while do done { } ;;).freeze

    # @param [String] filename File to analyze
    # @param [Hash] coverage Coverage with executed lines marked
    # @raise [ArgumentError] if the given +filename+ is invalid.
    def initialize(filename, coverage)
      @filename = filename
      @coverage = coverage

      unless File.file?(@filename) # rubocop:disable Style/GuardClause
        raise ArgumentError, "#{@filename} is not a file"
      end
    end

    # Yields uncovered relevant lines.
    # @note Uses +@coverage+ to avoid wasting time parsing executed lines.
    # @return [void]
    def uncovered_relevant_lines
      lineno = 0
      File.open(@filename, "rb").each_line do |line|
        if @coverage[lineno] == Bashcov::Line::IGNORED && relevant?(line)
          yield lineno
        end
        lineno += 1
      end
    end

  private

    def relevant?(line)
      line.sub!(/ #.*\Z/, "") # remove comments
      line.strip!

      !line.empty? &&
        !IGNORE_IS.include?(line) &&
        !line.start_with?(*IGNORE_START_WITH) &&
        !line.end_with?(*IGNORE_END_WITH) &&
        line !~ /\A\w+\(\)/ # function declared without the 'function' keyword
    end
  end
end
