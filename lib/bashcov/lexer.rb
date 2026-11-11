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

    # Constructs spanning multiple lines, as +[regexp, forward]+ pairs tried in
    # order. Regexps are anchored with +\G+ to match from a given line offset.
    MULTILINE_PATTERNS = [
      # multi-line arrays
      [/\G[^\n]*\b=\([^()]*\)/, false],

      # heredoc, possibly with a quoted delimiter (e.g. 'EOF', "EOF" or \EOF) -
      # ends at the first line holding only the delimiter, which `<<-` also
      # allows to be indented with tabs
      [/\G[^\n]+<<[ \t]*\\?['"]?(\w+)['"]?[^\n]*\n(?:[^\n]*\n)*?\1$/, true],
      [/\G[^\n]+<<-[ \t]*\\?['"]?(\w+)['"]?[^\n]*\n(?:[^\n]*\n)*?\t*\1$/, true],

      # multiline string concatenated with backslashes
      [/\G[^\n]+\\$(\s*['"][^'"]*['"]\s*\\$){1,}\s*['"][^'"]*['"]\s*$/, true],

      # multiline string concatenated with newlines, possibly opened after a
      # line continuation (but never after an unescaped newline) - this must
      # come before simple line continuations which would claim the opening
      # line otherwise - unlike single quotes, double quotes may contain escaped
      # characters such as \" - the opening quote must not close a string
      # already open on its line (e.g. `printf '%s: ' "$1"`), so the text
      # before it may only hold complete strings, plus lone quotes of the other
      # kind which may nest in command substitutions, e.g. "$(a 'b')" - this
      # text may only be empty right after the closing quote of another string
      *[false, true].product(["'", '"']).map do |forward, char|
        # complete double-quoted string on one line, command substitutions
        # being free to hold other strings, e.g. "$(a "b")"
        dq = /(?<dq>"(?>(?:[^"\\\n$]|\\[^\n]|\$(?!\()|\$(?<sub>\((?>(?:[^()'"\\\n]|\\[^\n]|'[^'\n]*'|\g<dq>|\g<sub>)*)\)))*)")/
        other = (char == "'" ? '(?!\g<dq>)"' : %q{(?!'[^'\n]*')'})
        prefix = /(?:[^\n'"\\]|\\[^\n]|'[^'\n]*'|#{dq}|#{other})+|(?<=['"])/
        body =
          if char == "'"
            /[^']*/
          else
            # same as above over several lines, or failing that anything up
            # to the next unescaped quote
            /(?<mdq>(?>(?:[^"\\$]|\\.|\$(?!\()|\$(?<msub>\((?>(?:[^()'"\\]|\\.|'[^']*'|"\g<mdq>"|\g<msub>)*)\)))*))|(?>(?:[^"\\]|\\.)*)/m
          end

        [/\G(?:#{prefix})(?:[ \t=]|\\\n[ \t]*)+#{char}(?:#{body})#{char}/m, forward]
      end,

      # simple line continuations with backslashes
      [/\G([^\n&|;]*[^\\&|;](\\\\)*\\\n)+[^\n&|;]*[^\n\\&|;](\\\\)*$/, true],
    ].freeze

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

      lineno = 0
      resume = nil
      while lineno < lines.size
        # skip ahead past a multiline construct once its lines are marked, but
        # recheck its last line as it may open another one, e.g. `a'; b='` -
        # look right after a construct ending mid-line first, so that its
        # closing quote is not read as an opener, then recheck the whole line
        last, stop = (resume && mark_multilines(content, resume, lineno)) || mark_multilines(content, offsets[lineno], lineno)
        last ||= lineno
        lineno.upto(last) { |sub_lineno| mark_line(lines[sub_lineno], sub_lineno) }
        resume = (stop if last > lineno && stop < content.size && content[stop] != $/)
        lineno = (last > lineno ? last : last + 1)
      end
    end

  private

    # @return [Array<Integer>, nil] last line and end offset of the multiline
    #   construct starting at +offset+ on +lineno+, if any
    def mark_multilines(content, offset, lineno)
      MULTILINE_PATTERNS.each do |regexp, forward|
        result = mark_multiline(content, offset, lineno, regexp, forward: forward)
        return result if result
      end

      nil
    end

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

      [last, multiline_match.end(0)] if length.positive?
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
