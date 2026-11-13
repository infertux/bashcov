# frozen_string_literal: true

require "bashcov/scanner"

module Bashcov
  # Reads the text of commands the way Bash traces it in +BASH_COMMAND+, so
  # that a command of a script can be compared with a traced one.
  module CommandText
    # Duplication of a file descriptor (+>&2+, +<&3+, +>&-+)
    DUPLICATION = /(?<![&<>])[<>]&(?=[\d-])/

    # Word which, written right before a redirection, is the file descriptor
    # it sets: a number, or a name in braces
    DESCRIPTOR = /\A(?:\d+|\{[A-Za-z_]\w*\})\z/

    # Words after which a word starts a command, in normalized text
    COMMAND_STARTS = %w[; & | ( $( `].freeze

    # File descriptors which a redirection sets when it names none
    DEFAULT_DESCRIPTORS = { "<" => 0, ">" => 1 }.freeze

    # Word boundaries used to find an explicit file descriptor before a
    # redirection, see {.descriptor_before?}
    WORD_BREAK = /[\s;&|()<>]/

    # Escape sequence in an ANSI-C quoted string (+$'…'+)
    ANSI_C_ESCAPE = /\\(?:(?<octal>[0-7]{1,3})|x(?<hex>\h{1,2})|u(?<short>\h{1,4})|U(?<long>\h{1,8})|c(?<control>.)|(?<other>.))/m

    # Characters of the escape sequences of an ANSI-C quoted string made of
    # a letter or a sign
    ANSI_C_CHARACTERS = {
      "a" => "\a", "b" => "\b", "e" => "\e", "E" => "\e", "f" => "\f", "n" => "\n", "r" => "\r", "t" => "\t", "v" => "\v",
      "\\" => "\\", "'" => "'", '"' => '"', "?" => "?",
    }.freeze

  module_function

    # Bash keeps the words of a command as they were written, but not the
    # blanks around them, around operators and redirections (`>/dev/null`
    # becomes `> /dev/null`), nor line continuations, which it takes out
    # with nothing in their place, even in a word. It writes the file
    # descriptor which the duplication of one leaves out (`>&2` becomes
    # `1>&2`). An escaped operator stays in its word, and +$(+ stays whole,
    # unlike a literal +$ (+.
    # @return [String] +text+ with operators apart and single spaces
    def normalize(text)
      # a backslash escaped itself continues no line
      joined = text.scrub.gsub(/(?<!\\)((?:\\\\)*)\\\n/, '\1')
      with_descriptors = joined.gsub(DUPLICATION) do |duplication|
        descriptor_before?(joined, Regexp.last_match.begin(0)) ? duplication : " #{DEFAULT_DESCRIPTORS.fetch(duplication[0])}#{duplication}"
      end
      with_descriptors.gsub(/\\.|\$\(|[;&|<>()`]/m) { |token| token.start_with?("\\") ? token : " #{token} " }.split.join(" ")
    end

    # @param [String] text text of some lines of a script
    # @return [String] +text+ without its comments, line continuations and
    #   heredoc bodies, keeping a +#+ in quotes, even when they span lines, or
    #   in a word.
    #   Quoted strings which Bash rewrites when parsing them, +$'…'+ and
    #   +$"…"+, are written as Bash traces them.
    def code(text)
      spans = Scanner.spans(text)
      # Joining a continuation can form a quoted string, e.g. $\\\n'foo'.
      if spans.any? { |kind, _| kind == :continuation }
        joined = spans.filter_map { |kind, span| span unless kind == :continuation }.join
        spans = Scanner.spans(joined)
      end
      spans.map do |kind, span|
        case kind
        when :comment, :continuation, :heredoc, :locale then ""
        when :ansi then ansi_c_string(span)
        else span
        end
      end.join
    end

    # Normalizes source for comparison with the text in a trace.
    def normalized_code(source)
      normalize(code(source))
    end

    # @param [Hash{String => Array<Boolean>}] quoted {.quoted_positions} of
    #   the sources read before, which the caller keeps
    # @return [Boolean] whether +text+ appears in +source+ as whole words,
    #   both normalized, out of a quoted string: words in quotes are no
    #   command, unless in a substitution there
    def matches?(source, text, quoted = {})
      pattern = /(?<!\S)#{Regexp.escape(text)}(?!\S)/
      offset = 0
      while (match = source.match(pattern, offset))
        return true unless (quoted[source] ||= quoted_positions(source))[match.begin(0)]

        offset = match.begin(0) + 1
      end
      false
    end

    # @param [String] source normalized text, see {.normalize}
    # @return [Array<Boolean>] for each character of +source+, whether it is
    #   in a quoted string, out of the substitutions there
    def quoted_positions(source)
      Scanner.spans(source).flat_map do |kind, span|
        if kind == :ansi
          [false, false] + Array.new(span.length - 2, true)
        else
          Array.new(span.length, !%i[code locale].include?(kind))
        end
      end
    end

    # @param [String] text normalized text of a command, see {.normalize}
    # @return [Boolean] whether it holds a compound command, or a list, which
    #   Bash rebuilds on more lines than one, e.g. +if a; then b; fi+. A
    #   reserved word is one only where a command starts, unlike in +echo done+.
    def compact?(text)
      quoted = quoted_positions(text)
      words = []
      text.scan(/\S+/) { |word| words << word unless quoted[Regexp.last_match.begin(0)] }
      words.each_with_index.any? do |word, index|
        previous = words[index - 1] if index.positive?
        following = words[index + 1]
        case word
        when ";" then following && !%w[; then do].include?(following) && previous != ";"
        when "then", "do", "else", "{" then following && (previous.nil? || COMMAND_STARTS.include?(previous))
        when "fi", "done", "esac", "}" then COMMAND_STARTS.include?(previous)
        end
      end
    end

    # @return [Boolean] whether the word of +text+ ending at +position+ is
    #   the file descriptor which a redirection there sets, see {DESCRIPTOR}
    def descriptor_before?(text, position)
      start = text.rindex(WORD_BREAK, position - 1) if position.positive?
      return false unless text[(start ? start + 1 : 0)...position].match?(DESCRIPTOR)

      # an escaped blank does not end the word
      !(start && text[0...start][/\\*\z/].length.odd?)
    end

    # Rewrites an ANSI-C quoted string, including its opening +$'+
    # @return [String] the string as Bash traces it: single-quoted, with
    #   blanks for its control characters, at the first of which {Xtrace}
    #   cuts the traced text
    def ansi_c_string(text)
      bytes = text[2..].delete_suffix("'").b.gsub(ANSI_C_ESCAPE) { ansi_c_character(Regexp.last_match) }
      # Bash ends the string at its first NUL
      bytes = bytes[/\A[^\0]*/n]
      # decoded like the trace, see {FieldStream#each_field}
      value = bytes.force_encoding(Encoding.default_external).encode("utf-8", invalid: :replace).scrub
      "'#{value.gsub(/[[:cntrl:]]/, ' ').gsub("'") { "'\\''" }}'"
    end

    # @param [MatchData] escape match of {ANSI_C_ESCAPE}
    # @return [String] the bytes of +escape+: byte escapes make up characters
    #   together. +\c@+ is a NUL, as in Bash.
    def ansi_c_character(escape)
      return ANSI_C_CHARACTERS.fetch(escape[:other], "\\#{escape[:other]}").b if escape[:other]
      return escape[:control] == "?" ? "\x7F".b : (escape[:control].upcase.ord & 0x1F).chr if escape[:control]

      return (escape[:octal].to_i(8) & 0xFF).chr if escape[:octal]
      return escape[:hex].to_i(16).chr if escape[:hex]

      (escape[:short] || escape[:long]).to_i(16).chr(Encoding::UTF_8).b
    rescue RangeError
      "\uFFFD".b
    end

    private_class_method :descriptor_before?, :ansi_c_string, :ansi_c_character
  end
end
