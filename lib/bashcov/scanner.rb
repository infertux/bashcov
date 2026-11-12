# frozen_string_literal: true

require "strscan"

module Bashcov
  # Reads a Bash script once, from the top, keeping track of quoting, heredocs,
  # command substitutions and line continuations, in order to find the groups
  # of lines that form a single command as far as coverage is concerned.
  #
  # Bash reports a hit for one line of such a group only (e.g. the first line
  # of a multiline string), so {Lexer} copies that hit onto the other lines.
  #
  # A command substitution spanning several lines belongs to the group of the
  # command which holds it, and the commands inside it form groups of their
  # own: Bash runs them separately, so some of them may never be executed.
  #
  # This is not a full Bash parser: it only knows enough of the syntax to tell
  # where a string, a heredoc or a substitution starts and ends.
  class Scanner
    # Lines forming a single command.
    # @!attribute lines
    #   @return [Range] indexes (0-based) of the lines of the command
    # @!attribute substitutions
    #   @return [Array<Substitution>] command substitutions of the command
    #     which span several lines
    Group = Struct.new(:lines, :substitutions) do
      # @return [Array<Integer>] lines of the command, except those lying
      #   entirely inside one of its substitutions
      def own_lines
        return lines.to_a if substitutions.empty?

        lines.to_a - substitutions.flat_map { |substitution| substitution.inner_lines.to_a }
      end
    end

    # Command substitution spanning several lines.
    # @!attribute lines
    #   @return [Range] indexes (0-based) of the lines of the substitution,
    #     from the line it opens on to the line it closes on
    # @!attribute groups
    #   @return [Array<Group>] commands of the substitution, covering each of
    #     its lines in order. The first and the last ones share a line with
    #     the command which holds the substitution.
    Substitution = Struct.new(:lines, :groups) do
      # @return [Range] lines lying entirely inside the substitution
      def inner_lines
        (lines.first + 1)...lines.last
      end
    end

    # Constructs which keep the following line in the same command: a newline
    # inside one of these is part of the command
    JOINING = %i[single double ansi param array arith].freeze

    # Constructs which hold commands of their own: a newline inside one of
    # these ends such a command, but not the command which holds the construct
    SUBSTITUTIONS = %i[command backtick].freeze

    # How many levels of substitutions spanning several lines are told apart
    MAX_DEPTH = 16

    # Constructs whose content is quoted, i.e. where heredocs do not start and
    # comments are not recognized
    QUOTED = %i[single double ansi param].freeze

    # Constructs whose first word starts a new command
    COMMANDS = %i[command backtick subshell case].freeze

    # Constructs where +<<+ is a shift, +#+ is not a comment and parentheses
    # only group
    ARITHMETIC = %i[arith paren].freeze

    # Characters of the script by byte, which saves creating a string for
    # each character read
    CHARS = Array.new(256) { |byte| byte.chr.freeze }.freeze

    # Characters after which a word starts
    WORD_BOUNDARIES = " \t\n\v\f\r;&|()<>"

    # Character which changes nothing in the middle of a word: neither a
    # boundary, nor a quote, nor the start of a substitution or of an array
    PLAIN_CHAR = /[^\s;&|()<>'"`\\$=]|=(?!\()|\$(?![$({'])/n

    # Text which changes nothing in the middle of a word: a plain character,
    # or a string on a single line without any substitution
    PLAIN = /#{PLAIN_CHAR}|'[^'\n]*'|"(?:[^"\\$`\n]|\$(?![$({]))*"/n

    # Rest of a word, which can be skipped
    WORD = /#{PLAIN}*/n

    # Words which can be skipped once the first word of a command was read,
    # unless they start a comment
    ARGUMENTS = /(?:[ \t]+|(?!\#)#{PLAIN}+)*/n

    # Length from which a line is skipped a piece at a time: the regular
    # expression engine keeps track of each character it matches in a
    # repetition, which takes many times the memory of the text itself
    LONG_LINE = 4096

    # Piece of the rest of a word, on a long line
    WORD_PIECE = /(?:#{PLAIN_CHAR}){0,1024}/n

    # Piece of the words which can be skipped, on a long line
    ARGUMENTS_PIECE = /(?:[ \t]{1,32}|(?!\#)(?:#{PLAIN_CHAR}){1,32}){0,32}/n

    # Characters which end a run of text in a quoted construct
    QUOTED_END = { single: /'/n, ansi: /['\\]/n, double: /["\\$`]/n, param: /[}"'\\$]/n }.freeze

    # Blanks found between words
    BLANKS = " \t"

    # Character which ends a run of blanks
    NON_BLANK = /[^ \t]/n

    # Piece of a comment in backticks, which ends at the first backtick unless
    # it is escaped
    BACKTICK_COMMENT = /(?:[^`\\\n]|\\[^\n]){0,1024}/n

    # Shared by the groups which hold no substitution
    NO_SUBSTITUTIONS = [].freeze

    # Heredoc operator, followed by its delimiter, see the "Here Documents"
    # section of bash(1)
    HEREDOC = /\G<<(-?)[ \t]*/n

    # Parts of a heredoc delimiter, which can be quoted in whole or in part
    # (e.g. 'EOF', "EOF", $'EOF', \EOF or E"OF")
    DELIMITER_PART = /\G(?:\$'((?:\\.|[^'\\])*)'|'([^']*)'|"((?:\\.|[^"\\])*)"|\\(.)|
                         ((?:[^\s;&|()<>'"\\$]|\$(?!'))+))/mnx

    # Reserved words after which a command starts, see the "Compound Commands"
    # section of bash(1)
    RESERVED = /\G(?:then|do|else|elif|if|while|until|time|!|\{)(?=[\s;&|()<>]|\z)/n

    # Line continuation followed by a pipe or a list operator
    CONTINUATION_BEFORE_OPERATOR = /\G\\\n[ \t]*(?:&&|\|)/n

    # @param [String] content Script to scan
    def initialize(content)
      # work on bytes, as indexing characters of a multibyte string is slow
      @content = content.dup.force_encoding(Encoding::BINARY)
    end

    # @return [Array<Group>] commands found at the top level, covering every
    #   line of the script in order
    def groups
      @groups ||= scan
    end

  private

    def scan
      @stack = []
      @heredocs = []
      @depth = 0 # number of substitutions the scanner is in
      @backticks = 0 # number of these which are in backticks
      @lowest_depth = 0 # lowest depth reached on the current line
      @lowest_depths = [] # for each line, the lowest depth reached on it
      @final_depths = [] # for each line, the depth at its end
      @ends = [] # for each line, whether a command ends with it
      @balanced_line = 0 # last line reached outside of any construct
      @lineno = 0
      @pos = 0
      @eol = @content.index("\n") || @content.size # end of the current line
      @long_line = @eol >= LONG_LINE
      @runs = StringScanner.new(@content) # skips runs of characters without creating objects
      @word_start = true
      @command_start = true

      step while @pos < @content.size

      finish
    end

    def finish
      return [] if @content.empty?

      newline unless @content.end_with?("\n")
      give_up unless @stack.empty? && @heredocs.empty?

      build(0, @lineno - 1, 0)
    end

    # The script ends inside a construct, which means the scanner got lost
    # somewhere after the last line it reached outside of any construct:
    # rather than trusting what it found from there on, leave these lines on
    # their own.
    def give_up
      @ends[@balanced_line - 1] = true if @balanced_line.positive?

      @balanced_line.upto(@lineno - 1) do |lineno|
        @lowest_depths[lineno] = 0
        @final_depths[lineno] = 0
        @ends[lineno] = true
      end
    end

    # @return [Array<Group>] commands found at +depth+ from line +first+ to
    #   line +last+
    def build(first, last, depth)
      groups = []
      start = first

      first.upto(last) do |lineno|
        next unless lineno == last || (@ends[lineno] && @final_depths[lineno] == depth)

        substitutions = start == lineno ? NO_SUBSTITUTIONS : build_substitutions(start, lineno, depth)
        groups << Group.new(start..lineno, substitutions)
        start = lineno + 1
      end

      groups
    end

    # @return [Array<Substitution>] substitutions spanning several lines in
    #   the command found at +depth+ from line +first+ to line +last+
    def build_substitutions(first, last, depth)
      substitutions = []
      opening = nil

      first.upto(last) do |lineno|
        if opening && @lowest_depths[lineno] <= depth
          substitutions << Substitution.new(opening..lineno, build(opening, lineno, depth + 1))
          opening = nil
        end

        opening ||= lineno if lineno < last && @final_depths[lineno] > depth
      end

      substitutions
    end

    def step
      top = @stack.last
      ending = QUOTED_END[top]
      return scan_unquoted(top) unless ending

      skip_to(position_of(ending))
      char = char_at(@pos)
      return unless char

      case top
      when :single then scan_single(char)
      when :ansi then scan_ansi(char)
      when :double then scan_double(char)
      when :param then scan_param(char)
      end
    end

    # @return [String, nil] the character at +position+, if any
    def char_at(position)
      byte = @content.getbyte(position)
      CHARS[byte] if byte
    end

    # @return [Integer] the position after the characters matching +pattern+
    #   from the current position on
    def run_end(pattern)
      @runs.pos = @pos
      @runs.skip(pattern)
      @runs.pos
    end

    # Searching for the end of a run, rather than matching the run, takes no
    # memory however long it is, e.g. for a string which holds a whole file.
    # @return [Integer] the position of the first character matching
    #   +pattern+ from the current position on, or the end of the script
    def position_of(pattern)
      @runs.pos = @pos
      @runs.skip_until(pattern) ? @runs.pos - 1 : @content.size
    end

    def advance(count = 1)
      position = @pos + count
      return @pos = position if position <= @eol # still on the current line

      skip_to(position)
    end

    # Moves to +position+, taking note of the lines which end before it.
    def skip_to(position)
      position = @content.size if position > @content.size

      while @eol < position
        @pos = @eol + 1
        newline
        @eol = @content.index("\n", @pos) || @content.size
        @long_line = @eol - @pos >= LONG_LINE
      end

      @pos = position
    end

    def scan_single(char)
      @stack.pop if char == "'"
      advance
    end

    def scan_ansi(char)
      return advance(2) if char == "\\"

      @stack.pop if char == "'"
      advance
    end

    def scan_double(char)
      return advance(2) if char == "\\"
      return if char == "$" && scan_dollar

      case char
      when '"' then @stack.pop
      when "`" then push(:backtick)
      end
      advance
    end

    def scan_param(char)
      return advance(2) if char == "\\"
      return if char == "$" && scan_dollar

      case char
      when "}" then @stack.pop
      when '"' then @stack.push(:double)
      when "'" then @stack.push(:single) # even inside double quotes, e.g. "${a%'}'}"
      end
      advance
    end

    # Handles a +$+ at the current position which opens a construct.
    # @return [Symbol, nil] the construct entered or skipped, if any
    def scan_dollar
      case char_at(@pos + 1)
      when "$"
        advance(2)
        :pid
      when "(" then char_at(@pos + 2) == "(" ? enter(:arith, 3) : enter(:command, 2)
      when "{" then enter(:param, 2)
      when "'" then enter(:ansi, 2) unless QUOTED.include?(@stack.last)
      end
    end

    # Enters +construct+, whose opening token is +length+ characters long.
    # @return [Symbol] +construct+
    def enter(construct, length)
      push(construct)
      advance(length)
      construct
    end

    def push(construct)
      @stack.push(construct)
      @depth += 1 if SUBSTITUTIONS.include?(construct)
      @backticks += 1 if construct == :backtick
      return unless COMMANDS.include?(construct)

      # e.g. `case` right after `"$(`
      @word_start = true
      @command_start = true
    end

    # Scans outside of quotes: at the top level, or inside a command
    # substitution, backticks, an array or an arithmetic expression.
    def scan_unquoted(top)
      @pos = run_end(@long_line ? WORD_PIECE : WORD) unless @word_start
      skip_arguments unless @command_start
      char = char_at(@pos)
      char = skip_blanks if char && BLANKS.include?(char)
      return unless char

      word_start = @word_start
      command_start = @command_start
      @word_start = WORD_BOUNDARIES.include?(char)
      @command_start = command_start_after(char, top, word_start, command_start)

      return scan_backslash(command_start) if char == "\\"
      return if char == "$" && scan_dollar
      return skip_comment if char == "#" && word_start && !ARITHMETIC.include?(top)
      return if command_start && word_start && scan_keyword(top)

      case char
      when "'" then @stack.push(:single)
      when '"' then @stack.push(:double)
      when "`" then top == :backtick ? leave : push(:backtick)
      when "(" then return scan_open_paren(top, word_start)
      when ")" then return scan_close_paren(top)
      when "=" then return enter(:array, 2) if char_at(@pos + 1) == "(" && !ARITHMETIC.include?(top)
      when "<" then return scan_redirection(top)
      when "\n" then return scan_newline
      end
      advance
    end

    # Words and blanks change nothing after the first word of a command,
    # except that a word starts after a blank.
    def skip_arguments
      position = run_end(@long_line ? ARGUMENTS_PIECE : ARGUMENTS)
      return if position == @pos

      @pos = position
      @word_start = BLANKS.include?(char_at(@pos - 1))
    end

    # Blanks start a word, and a command if one could start before them.
    # @return [String, nil] the character after the blanks, if any
    def skip_blanks
      @word_start = true
      @pos = position_of(NON_BLANK)
      char_at(@pos)
    end

    # @return [Boolean] whether a command starts at the next word, i.e.
    #   whether a reserved word such as +case+ would be recognized there
    def command_start_after(char, top, word_start, command_start)
      case char
      when ";", "|", "(", "\n" then true
      when "&" then @pos.zero? || !"<>".include?(char_at(@pos - 1)) # not a redirection such as 2>&1
      when ")" then %i[case subshell].include?(top) # after a case pattern or the parentheses of a function
      when " ", "\t" then command_start
      when "\\" then char_at(@pos + 1) == "\n" ? command_start : false
      else
        # a word keeps the state it got from its first character
        word_start ? command_start && @content.match?(RESERVED, @pos) : command_start
      end
    end

    # @param [Boolean] command_start whether a command would start here
    def scan_backslash(command_start)
      @word_start = false
      return advance(2) unless char_at(@pos + 1) == "\n"

      # a line continuation keeps the next line in the same group when it is
      # in the middle of a command, but not when it sits between two commands
      # (e.g. after +&&+, +;+ or +then+, or before +||+): Bash reports each of
      # them on its own line - except in a substitution, where it does not
      # tell the lines joined by continuations apart
      split = @stack.empty? && (command_start || @content.match?(CONTINUATION_BEFORE_OPERATOR, @pos))
      advance(2)
      end_group if split
    end

    # A comment ends with its line. Bash also ends a backtick substitution at
    # the first backtick, even in a comment.
    def skip_comment
      return @pos = @eol unless @backticks.positive?

      loop do
        position = run_end(BACKTICK_COMMENT)
        break if position == @pos

        @pos = position
      end
    end

    # Recognizes +case+ inside a substitution, so that the +)+ closing a
    # pattern does not end the substitution.
    # @return [Symbol, nil] the keyword found, if any
    def scan_keyword(top)
      if COMMANDS.include?(top) && @content.match?(/\Gcase\s/n, @pos)
        enter(:case, 4)
      elsif top == :case && @content.match?(/\Gesac(?=[\s;&|)`]|\z)/n, @pos)
        @stack.pop
        advance(4)
        :esac
      end
    end

    def scan_open_paren(top, word_start)
      if ARITHMETIC.include?(top) || top == :array
        @stack.push(:paren)
      elsif word_start && char_at(@pos + 1) == "("
        return enter(:arith, 2)
      elsif %i[command backtick subshell].include?(top)
        push(:subshell)
      end
      advance
    end

    def scan_close_paren(top)
      case top
      when :arith
        @stack.pop
        return advance(2) if char_at(@pos + 1) == ")"
      when :paren, :command, :subshell, :array
        leave
      end
      advance
    end

    # Leaves the innermost construct.
    def leave
      construct = @stack.pop
      return unless SUBSTITUTIONS.include?(construct)

      @backticks -= 1 if construct == :backtick
      @depth -= 1
      @lowest_depth = @depth if @depth < @lowest_depth
    end

    def scan_redirection(top)
      here_string = @content.match?(/\G<<</n, @pos)
      match = @content.match(HEREDOC, @pos) unless ARITHMETIC.include?(top) || here_string
      return advance(here_string ? 3 : 1) unless match

      advance(match[0].size)
      delimiter, quoted = scan_delimiter
      @heredocs << [delimiter, match[1] == "-", quoted] if delimiter
    end

    # Reads the delimiter word of a heredoc and removes its quotes.
    # @return [Array(String, Boolean), nil] the delimiter, which is empty for
    #   +<<''+, and whether any part of it is quoted, or +nil+ if there is none
    def scan_delimiter
      delimiter = nil
      quoted = false
      while (part = @content.match(DELIMITER_PART, @pos))
        ansi, single, double, escaped, plain = part.captures
        delimiter ||= +""
        # a line continuation is not part of the delimiter, nor does it quote it
        quoted ||= plain.nil? && escaped != "\n"
        delimiter << (ansi&.gsub(/\\(.)/mn, '\\1') || single || double&.gsub(/\\([\\"$`])/n, '\\1') ||
                      escaped&.delete("\n") || plain)
        advance(part[0].size)
      end
      delimiter && [delimiter, quoted]
    end

    def scan_newline
      advance

      until @heredocs.empty?
        skip_heredoc(*@heredocs.first)
        @heredocs.shift
      end

      end_group unless joined? || @stack.last == :heredoc
    end

    # Skips the body of a heredoc, up to and including its closing delimiter.
    def skip_heredoc(delimiter, strip_tabs, quoted)
      while @pos < @content.size
        body = heredoc_line(quoted)
        body = body.sub(/\A\t+/n, "") if strip_tabs
        return if body == delimiter
      end

      # unterminated heredoc: let #finish know the scanner got lost
      @stack.push(:heredoc)
    end

    # Reads a line of the body of a heredoc. Unless the delimiter is quoted, a
    # line continuation joins a line to the next one, be it the closing
    # delimiter.
    def heredoc_line(quoted)
      body = @content.byteslice(@pos, @eol - @pos)
      skip_to(@eol + 1)
      until quoted || @pos >= @content.size || !body.end_with?("\\") || body[/\\+\z/n].size.even?
        body = body.chop << @content.byteslice(@pos, @eol - @pos)
        skip_to(@eol + 1)
      end
      body
    end

    # Called at the end of each line.
    def newline
      @lowest_depths << [@lowest_depth, MAX_DEPTH].min
      @final_depths << [@depth, MAX_DEPTH].min
      @ends << false
      @lineno += 1
      @lowest_depth = @depth
      @balanced_line = @lineno if @stack.empty? && @heredocs.empty?
    end

    # @return [Boolean] whether a newline here is part of the innermost command
    def joined?
      @stack.reverse_each do |construct|
        return true if JOINING.include?(construct)
        return false if SUBSTITUTIONS.include?(construct)
      end

      false
    end

    # Ends the innermost command with the line which was just read.
    def end_group
      @ends[-1] = true
    end
  end
end
