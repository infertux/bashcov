# frozen_string_literal: true

require "json"
require "open3"

# Uses the parser of shfmt (https://github.com/mvdan/sh) as a reference to
# check where {Bashcov::Scanner} groups lines together. shfmt is only needed to
# run this check, which happens in CI, never to run Bashcov.
#
# What is compared is how each line is tied to the line before: the number of
# command substitutions which hold both of them, and whether they belong to
# the same command of the innermost one.
module ShfmtOracle
  # Node types whose content keeps the following line in the same command, as
  # +Bashcov::Scanner::JOINING+ does
  JOINING_TYPES = %w[SglQuoted DblQuoted ParamExp ArithmExp ArithmCmd].freeze

  # Node type whose content is made of commands of its own, as
  # +Bashcov::Scanner::SUBSTITUTIONS+
  SUBSTITUTION_TYPE = "CmdSubst"

  # Lines which no substitution holds and which belong to different commands
  APART = [0, false].freeze

  # Redirection operators which start a heredoc, as shfmt names them
  HEREDOC_OPERATORS = %w[<< <<-].freeze

module_function

  # @return [String] path to the shfmt executable
  def shfmt
    ENV.fetch("SHFMT", "shfmt")
  end

  # @return [Boolean] whether shfmt can be run
  def available?
    _, status = Open3.capture2e(shfmt, "--version")
    status.success?
  rescue SystemCallError
    false
  end

  # @param [String] filename script to check
  # @return [Array<String>, nil] lines which shfmt and the scanner do not tie
  #   to the line before in the same way, or +nil+ if shfmt cannot parse the
  #   script
  def mismatches(filename)
    source = File.binread(filename)
    expected = ties(source)
    return unless expected

    lines = source.lines
    found = scanner_ties(Bashcov::Scanner.new(source).groups)

    1.upto(lines.size - 1).filter_map do |lineno|
      shfmt_tie = expected.fetch(lineno, APART)
      scanner_tie = found.fetch(lineno, APART)
      next if shfmt_tie == scanner_tie
      # shfmt has no node for line continuations
      next if scanner_tie == [shfmt_tie.first, true] && continuation?(lines[lineno - 1])

      "#{filename}:#{lineno + 1}: #{describe(scanner_tie)} by the scanner, " \
        "#{describe(shfmt_tie)} by shfmt: #{lines[lineno].strip[0, 60]}"
    end
  end

  def describe((depth, joined))
    "#{joined ? 'joined' : 'not joined'} to the line before in #{depth} substitution(s)"
  end

  # @param [Array<Bashcov::Scanner::Group>] groups
  # @return [Hash{Integer => Array(Integer, Boolean)}] for each line (0-based)
  #   which the scanner ties to the line before, the number of substitutions
  #   holding both lines and whether they belong to the same command there
  def scanner_ties(groups, depth = 0, ties = {})
    groups.each do |group|
      (group.lines.first + 1).upto(group.lines.last) { |lineno| ties[lineno] = [depth, true] }

      group.substitutions.each do |substitution|
        (substitution.lines.first + 1).upto(substitution.lines.last) { |lineno| ties[lineno] = [depth + 1, false] }
        scanner_ties(substitution.groups, depth + 1, ties)
      end
    end

    ties
  end

  # @return [Boolean] whether +line+ ends with a line continuation
  def continuation?(line)
    line.chomp[/\\+\z/].to_s.size.odd?
  end

  # @return [Hash{Integer => Array(Integer, Boolean)}, nil] the same as
  #   {scanner_ties}, according to shfmt
  def ties(source)
    json, status = Open3.capture2(shfmt, "--to-json", "--language-dialect=bash", stdin_data: source)
    return unless status.success?

    ties = {}
    # nodes are visited before the nodes they hold, so the innermost node
    # spanning two lines is the one which has the last word
    walk(JSON.parse(json)) do |node|
      first, last = span(node, source)
      next unless first && last

      (first + 1).upto(last) do |lineno|
        depth, = ties.fetch(lineno, APART)
        ties[lineno] = node["Type"] == SUBSTITUTION_TYPE ? [depth + 1, false] : [depth, true]
      end
    end
    ties
  end

  def walk(node, &)
    case node
    when Hash
      yield node
      # the body of a heredoc is text as far as the scanner is concerned,
      # even when it holds substitutions
      node.each { |key, value| walk(value, &) unless key == "Hdoc" }
    when Array
      node.each { |value| walk(value, &) }
    end
  end

  # @return [Array(Integer, Integer), nil] first and last lines (0-based) of
  #   +node+ if it ties lines together
  def span(node, source)
    if JOINING_TYPES.include?(node["Type"]) || node["Type"] == SUBSTITUTION_TYPE
      [line(node["Pos"]), line(node["End"])]
    elsif node["Array"].is_a?(Hash)
      # an array is joined from its opening to its closing parenthesis, even
      # when it is empty and has no elements
      array = node["Array"]
      [line(array["Lparen"]), line(array["Rparen"])]
    elsif HEREDOC_OPERATORS.include?(node["Op"]) && node["Word"]
      heredoc_span(node, source)
    end
  end

  # A heredoc goes from its operator to its closing delimiter, which shfmt
  # does not include in the body. An empty heredoc has no body at all.
  def heredoc_span(node, source)
    first = line(node["OpPos"])
    return unless first

    word = node["Word"]
    delimiter = unquote(source.byteslice(word["Pos"]["Offset"]...word["End"]["Offset"]))
    lines = source.lines
    start = [first + 1, node["Hdoc"] ? line(node["Hdoc"]["End"]).to_i : 0].max
    last = start.upto(lines.size - 1).find do |lineno|
      body = lines[lineno].chomp
      body = body.sub(/\A\t+/, "") if node["Op"] == "<<-"
      body == delimiter
    end
    [first, last || (lines.size - 1)]
  end

  # Parts of a heredoc delimiter: $'…', '…', "…", an escaped character or
  # plain text
  DELIMITER_PART = /\$'((?:\\.|[^'\\])*)'|'([^']*)'|"((?:\\.|[^"\\])*)"|\\(.)|((?:[^'"\\$]|\$(?!'))+)/m

  # Removes quotes from a heredoc delimiter, e.g. +'a"b'+ gives +a"b+ and
  # +E"OF"+ gives +EOF+.
  def unquote(word)
    word.scan(DELIMITER_PART).map do |ansi, single, double, escaped, plain|
      ansi&.gsub(/\\(.)/m, '\\1') || single || double&.gsub(/\\([\\"$`])/, '\\1') || escaped&.delete("\n") || plain
    end.join
  end

  def line(pos)
    pos && pos["Line"].to_i.positive? ? pos["Line"] - 1 : nil
  end
end
