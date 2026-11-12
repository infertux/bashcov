# frozen_string_literal: true

module Bashcov
  # Reads a Bash script once, from the top, keeping track of quoting, heredocs,
  # command substitutions and line continuations, in order to find the groups
  # of lines that form a single command as far as coverage is concerned.
  #
  # Bash reports a hit for one line of such a group only (e.g. the first line
  # of a multiline string), so {Lexer} copies that hit onto the other lines.
  #
  # This is not a full Bash parser: it only knows enough of the syntax to tell
  # where a string, a heredoc or a substitution starts and ends.
  class Scanner
    # Constructs which keep the following line in the same group: a newline
    # inside one of these is part of the command, unlike a newline inside a
    # command substitution, after which Bash reports the next command on its
    # own line.
    JOINING = %i[single double ansi param array arith].freeze

    # Constructs whose content is quoted, i.e. where heredocs do not start and
    # comments are not recognized
    QUOTED = %i[single double ansi param].freeze

    # Constructs whose first word starts a new command
    COMMANDS = %i[command backtick subshell case].freeze

    # Constructs where +<<+ is a shift, +#+ is not a comment and parentheses
    # only group
    ARITHMETIC = %i[arith paren].freeze

    # Characters after which a word starts
    WORD_BOUNDARY = /[\s;&|()<>]/n

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

    # @return [Array<Range>] groups of line indexes (0-based), covering every
    #   line of the script in order
    def groups
      @groups ||= scan
    end

  private

    def scan
      @groups = []
      @stack = []
      @heredocs = []
      @group_start = 0
      @lineno = 0
      @pos = 0
      @word_start = true
      @command_start = true

      step while @pos < @content.size

      finish
    end

    def finish
      last_line = @content.end_with?("\n") ? @lineno - 1 : @lineno
      return @groups if @content.empty?

      if @stack.empty? && @heredocs.empty?
        @groups << (@group_start..last_line) if @group_start <= last_line
      else
        # the script ends inside a construct, which means the scanner got
        # lost somewhere: rather than gluing all lines up to the end together,
        # leave them on their own
        @group_start.upto(last_line) { |lineno| @groups << (lineno..lineno) }
      end

      @groups
    end

    def step
      char = @content[@pos]

      case @stack.last
      when :single then scan_single(char)
      when :ansi then scan_ansi(char)
      when :double then scan_double(char)
      when :param then scan_param(char)
      else scan_unquoted(char)
      end
    end

    def advance(count = 1)
      count.times do
        newline if @content[@pos] == "\n"
        @pos += 1
      end
    end

    # @return [Boolean] whether the text at the current position starts with
    #   +string+
    def at?(string)
      @content[@pos, string.size] == string
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
      return if scan_dollar

      case char
      when '"' then @stack.pop
      when "`" then push(:backtick)
      end
      advance
    end

    def scan_param(char)
      return advance(2) if char == "\\"
      return if scan_dollar

      case char
      when "}" then @stack.pop
      when '"' then @stack.push(:double)
      when "'" then @stack.push(:single) # even inside double quotes, e.g. "${a%'}'}"
      end
      advance
    end

    # Handles a +$+ which opens a construct.
    # @return [Symbol, nil] the construct entered or skipped, if any
    def scan_dollar
      return unless @content[@pos] == "$"

      if at?("$$")
        advance(2)
        :pid
      elsif at?("$((")
        enter(:arith, 3)
      elsif at?("$(")
        enter(:command, 2)
      elsif at?("${")
        enter(:param, 2)
      elsif at?("$'") && !QUOTED.include?(@stack.last)
        enter(:ansi, 2)
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
      return unless COMMANDS.include?(construct)

      # e.g. `case` right after `"$(`
      @word_start = true
      @command_start = true
    end

    # Scans outside of quotes: at the top level, or inside a command
    # substitution, backticks, an array or an arithmetic expression.
    def scan_unquoted(char)
      top = @stack.last
      word_start = @word_start
      command_start = @command_start
      @word_start = WORD_BOUNDARY.match?(char)
      @command_start = command_start_after(char, top, word_start, command_start)

      return scan_backslash(command_start) if char == "\\"
      return if scan_dollar
      return skip_comment if char == "#" && word_start && !ARITHMETIC.include?(top)
      return if command_start && word_start && scan_keyword(top)

      case char
      when "'" then @stack.push(:single)
      when '"' then @stack.push(:double)
      when "`" then top == :backtick ? @stack.pop : push(:backtick)
      when "(" then return scan_open_paren(top, word_start)
      when ")" then return scan_close_paren(top)
      when "=" then return enter(:array, 2) if at?("=(") && !ARITHMETIC.include?(top)
      when "<" then return scan_redirection(top)
      when "\n" then return scan_newline
      end
      advance
    end

    # @return [Boolean] whether a command starts at the next word, i.e.
    #   whether a reserved word such as +case+ would be recognized there
    def command_start_after(char, top, word_start, command_start)
      case char
      when ";", "|", "(", "\n" then true
      when "&" then !@content[[@pos - 1, 0].max].match?(/[<>]/n) # not a redirection such as 2>&1
      when ")" then %i[case subshell].include?(top) # after a case pattern or the parentheses of a function
      when " ", "\t" then command_start
      when "\\" then at?("\\\n") ? command_start : false
      else
        # a word keeps the state it got from its first character
        word_start ? command_start && @content.match?(RESERVED, @pos) : command_start
      end
    end

    # @param [Boolean] command_start whether a command would start here
    def scan_backslash(command_start)
      @word_start = false
      return advance(2) unless at?("\\\n")

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
      ending = @stack.include?(:backtick) ? /[`\n]/n : "\n"
      @pos = @content.index(ending, @pos) || @content.size
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
      elsif word_start && at?("((")
        return enter(:arith, 2)
      elsif %i[command backtick].include?(top)
        push(:subshell)
      end
      advance
    end

    def scan_close_paren(top)
      case top
      when :arith
        @stack.pop
        return advance(2) if at?("))")
      when :paren, :command, :subshell, :array
        @stack.pop
      end
      advance
    end

    def scan_redirection(top)
      match = @content.match(HEREDOC, @pos) unless ARITHMETIC.include?(top) || at?("<<<")
      return advance(at?("<<<") ? 3 : 1) unless match

      advance(match[0].size)
      delimiter = scan_delimiter
      @heredocs << [delimiter, match[1] == "-"] if delimiter
    end

    # Reads the delimiter word of a heredoc and removes its quotes.
    # @return [String, nil] the delimiter, which is empty for +<<''+, or +nil+
    #   if there is none
    def scan_delimiter
      delimiter = nil
      while (part = @content.match(DELIMITER_PART, @pos))
        ansi, single, double, escaped, plain = part.captures
        delimiter ||= +""
        delimiter << (ansi&.gsub(/\\(.)/mn, '\\1') || single || double&.gsub(/\\([\\"$`])/n, '\\1') || escaped || plain)
        advance(part[0].size)
      end
      delimiter
    end

    def scan_newline
      advance
      skip_heredoc(*@heredocs.shift) until @heredocs.empty?
      end_group unless joined? || @stack.include?(:heredoc)
    end

    # Skips the body of a heredoc, up to and including its closing delimiter.
    def skip_heredoc(delimiter, strip_tabs)
      while @pos < @content.size
        eol = @content.index("\n", @pos) || @content.size
        body = @content[@pos...eol]
        body = body.sub(/\A\t+/n, "") if strip_tabs
        @pos = eol
        advance if @pos < @content.size
        return if body == delimiter
      end

      # unterminated heredoc: let #finish know the scanner got lost
      @stack.push(:heredoc)
    end

    def newline
      @lineno += 1
    end

    def joined?
      @stack.any? { |construct| JOINING.include?(construct) }
    end

    def end_group
      @groups << (@group_start..(@lineno - 1))
      @group_start = @lineno
    end
  end
end
