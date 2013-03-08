module Bashcov
  # Simple lexer which analyzes Bash files in order to get information for
  # coverage
  class Lexer
    # @param [String] filename File to analyze
    # @raise [ArgumentError] if the given +filename+ is invalid.
    def initialize filename
      @filename = File.expand_path(filename)

      unless File.file?(@filename)
        raise ArgumentError, "#{@filename} is not a file"
      end
    end

    # @return [Array] Irrelevant lines
    def irrelevant_lines
      lines = []
      lineno = 0
      File.foreach(@filename) do |line|
        lines << lineno if is_irrevelant? line
        lineno +=1
      end
      lines
    end

  private

    def is_irrevelant? line
      line.strip!

      line.empty? or
      is_keywords.include? line or
      line.start_with?(*start_with_tokens) or
      line.end_with?(*end_with_tokens) or
      line =~ /\A\w+\(\)\s*{/ # function declared like this: "foo() {"
    end

    # Lines containing only one of these keywords are irrelevant for coverage
    def is_keywords
      %w|esac fi then do done else { } ;;|
    end

    # Lines starting with one of these tokens are irrelevant for coverage
    def start_with_tokens
      %w|# function|
    end

    # Lines ending with one of these tokens are irrelevant for coverage
    def end_with_tokens
      %w|(|
    end
  end
end
