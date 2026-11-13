# frozen_string_literal: true

require "strscan"

module Bashcov
  # Reads the text of commands the way Bash traces it in +BASH_COMMAND+, so
  # that a command of a script can be compared with a traced one.
  module CommandText
    # Duplication of a file descriptor (+>&2+, +<&3+, +>&-+) without the
    # descriptor it sets
    DUPLICATION = /(?<![\w$}&<>])[<>]&(?=[\d-])/

    # File descriptors which a redirection sets when it names none
    DEFAULT_DESCRIPTORS = { "<" => 0, ">" => 1 }.freeze

    # Characters after which a +#+ starts a comment, see {.code}
    WORD_BREAK = /[\s;&|()<>]/

    # Quotes, escapes, comments and what opens and closes a substitution,
    # which {.code} looks for
    CODE_SPECIAL = /["'\\#()`]/

    # Escape sequence in an ANSI-C quoted string (+$'…'+)
    ANSI_C_ESCAPE = /\\(?:(?<octal>[0-7]{1,3})|x(?<hex>\h{1,2})|u(?<short>\h{1,4})|U(?<long>\h{1,8})|c(?<control>.)|(?<other>.))/m

    # Characters of the escape sequences of an ANSI-C quoted string made of
    # a letter or a sign
    ANSI_C_CHARACTERS = {
      "a" => "\a", "b" => "\b", "e" => "\e", "E" => "\e", "f" => "\f", "n" => "\n", "r" => "\r", "t" => "\t", "v" => "\v",
      "\\" => "\\", "'" => "'", '"' => '"', "?" => "?",
    }.freeze

    # What is open at the start of a text, see {.quoting_after}
    TOP_LEVEL = [[:code, 0, nil]].freeze

  module_function

    # Bash keeps the words of a command as they were written, but not the
    # blanks around them, around operators and redirections (`>/dev/null`
    # becomes `> /dev/null`), nor line continuations, which it takes out
    # with nothing in their place, even in a word. It writes the file
    # descriptor which the duplication of one leaves out (`>&2` becomes
    # `1>&2`).
    # @return [String] +text+ with operators apart and single spaces
    def normalize(text)
      text.scrub.gsub("\\\n", "").gsub(DUPLICATION) { |duplication| "#{DEFAULT_DESCRIPTORS.fetch(duplication[0])}#{duplication}" }
          .gsub(/([;&|<>()`])/, ' \\1 ').split.join(" ")
    end

    # @param [String] text text of some lines of a script
    # @return [String] +text+ without its comments, keeping a +#+ in quotes,
    #   even when they span lines, or in a word. Quoted strings which Bash
    #   rewrites when parsing them, +$'…'+ and +$"…"+, are written as Bash
    #   traces them.
    def code(text)
      scanner = StringScanner.new(text)
      kept = +""
      contexts = TOP_LEVEL
      escaped_end = nil
      while (run = scanner.scan_until(contexts.last.first == :single ? /'/ : CODE_SPECIAL))
        char = scanner.matched
        kept << run.delete_suffix(char)
        in_code = contexts.last.first == :code
        after_dollar = kept.end_with?("$") && kept.length != escaped_end
        if char == "#" && in_code && (kept.empty? || kept[-1].match?(WORD_BREAK))
          scanner.skip_until(/(?=\n)|\z/)
        elsif char == "\\"
          kept << char << scanner.getch.to_s
          escaped_end = kept.length
        elsif after_dollar && in_code && char == "'"
          kept.chop! << ansi_c_string(scanner)
        else
          kept.chop! if after_dollar && in_code && char == '"'
          kept << char
          contexts = quoting_after(contexts, char, char == "(" && after_dollar)
        end
      end
      kept << scanner.rest
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
      contexts = TOP_LEVEL
      escaped = false
      # the characters before, enough to tell a substitution: +$ (+
      before = +""
      source.each_char.map do |char|
        kind, = contexts.last
        if escaped
          escaped = false
        elsif char == "\\" && kind != :single
          escaped = true
        else
          contexts = quoting_after(contexts, char, char == "(" && before.end_with?("$ ", "$"))
        end
        before = "#{before}#{char}"[-2..] || "#{before}#{char}"
        kind != :code
      end
    end

    # @param [String] text normalized text of a command, see {.normalize}
    # @return [Boolean] whether it holds a compound command, or a list, which
    #   Bash rebuilds on more lines than one, e.g. +if a; then b; fi+
    def compact?(text)
      quoted = quoted_positions(text)
      words = text.to_enum(:scan, /\S+/).map { Regexp.last_match }.reject { |word| quoted[word.begin(0)] }.map(&:to_s)
      words.each_with_index.any? do |word, index|
        following = words[index + 1]
        case word
        when ";" then following && !%w[; then do].include?(following) && words[index - 1] != ";"
        when "then", "do", "else", "{" then following
        when "fi", "done", "esac", "}" then index.positive?
        end
      end
    end

    # @param [Array<Array(Symbol, Integer, String, nil)>] contexts what is
    #   open, the innermost last: a quote (+:single+, +:double+), or code
    #   (+:code+) with the number of parentheses open in it and what closes
    #   it, +)+ or a backquote: a substitution has quotes of its own
    # @param [Boolean] opens_substitution whether +char+ is the parenthesis
    #   of +$(+
    # @return [Array<Array(Symbol, Integer, String, nil)>] the contexts open
    #   after +char+
    def quoting_after(contexts, char, opens_substitution)
      kind, parentheses, closer = contexts.last
      case kind
      when :single
        char == "'" ? contexts[...-1] : contexts
      when :double
        if char == '"' then contexts[...-1]
        elsif opens_substitution then contexts + [[:code, 0, ")"]]
        elsif char == "`" then contexts + [[:code, 0, "`"]]
        else contexts
        end
      else
        if char == "'" then contexts + [[:single, 0, nil]]
        elsif char == '"' then contexts + [[:double, 0, nil]]
        elsif char == closer && (closer == "`" || parentheses.zero?) then contexts[...-1]
        elsif char == "`" then contexts + [[:code, 0, "`"]]
        elsif char == "(" then contexts[...-1] + [[kind, parentheses + 1, closer]]
        elsif char == ")" && parentheses.positive? then contexts[...-1] + [[kind, parentheses - 1, closer]]
        else contexts
        end
      end
    end

    # Reads an ANSI-C quoted string, after its opening quote
    # @return [String] the string as Bash traces it: single-quoted, with
    #   blanks for its control characters, at the first of which {Xtrace}
    #   cuts the traced text
    def ansi_c_string(scanner)
      raw = +""
      while (run = scanner.scan_until(/['\\]/))
        raw << run
        break if scanner.matched == "'"

        raw << scanner.getch.to_s
      end
      bytes = raw.delete_suffix("'").b.gsub(ANSI_C_ESCAPE) { ansi_c_character(Regexp.last_match) }
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

      byte = (escape[:octal]&.to_i(8)&.& 0xFF) || escape[:hex]&.to_i(16)
      return byte.chr if byte

      (escape[:short] || escape[:long]).to_i(16).chr(Encoding::UTF_8).b
    rescue RangeError
      "\uFFFD".b
    end

    private_class_method :quoting_after, :ansi_c_string, :ansi_c_character
  end
end
