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
      IO.readlines(@filename).each_with_index do |line, lineno|
        lines << lineno if is_irrevelant? line
      end
      lines
    end

  private

    def is_irrevelant? line
      line.strip!

      line.empty? or
      start_with.any? { |token| line.start_with? token } or
      end_with.any? { |token| line.end_with? token } or
      is.any? { |keyword| line == keyword } or
      line =~ /\A\w+\(\) {/ # function declared like this: "foo() {"
    end

    # Lines containing only one of these keywords are irrelevant for coverage
    def is
      %w(esac fi then do done else { } ;;)
    end

    # Lines starting with one of these tokens are irrelevant for coverage
    def start_with
      %w(# function)
    end

    # Lines ending with one of these tokens are irrelevant for coverage
    def end_with
      %w(\()
    end
  end
end
