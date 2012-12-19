module Bashcov
  # Simple lexer which analyzes Bash files in order to get information for
  # coverage
  class Lexer
    # @param [String] filename File to analyze
    # @raise [ArgumentError] if the given +filename+ is invalid.
    def initialize filename
      @filename = File.expand_path(filename)
      raise ArgumentError "#{@filename} is not a file" unless File.file?(@filename)
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
      return true if line.empty?
      return true if start_with.any? { |token| line.start_with? token }
      return true if is.any? { |keyword| line == keyword }
      return true if line =~ /\A\w+\(\) {/ # function declared like this: "foo() {"
      false
    end

    # Lines containing only one of these keywords are irrelevant for coverage
    def is
      %w(esac fi then do done else { } ;;)
    end

    # Lines starting with one of these tokens are irrelevant for coverage
    def start_with
      %w(# function)
    end
  end
end
