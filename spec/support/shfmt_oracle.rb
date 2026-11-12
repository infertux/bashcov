# frozen_string_literal: true

require "json"
require "open3"

# Uses the parser of shfmt (https://github.com/mvdan/sh) as a reference to
# check where {Bashcov::Scanner} groups lines together. shfmt is only needed to
# run this check, which happens in CI, never to run Bashcov.
module ShfmtOracle
  # Node types whose content keeps the following line in the same command, as
  # +Bashcov::Scanner::JOINING+ does
  JOINING_TYPES = %w[SglQuoted DblQuoted ParamExp ArithmExp ArithmCmd].freeze

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
  # @return [Array<String>, nil] lines where shfmt and the scanner disagree on
  #   whether a line belongs to the same command as the line before, or +nil+
  #   if shfmt cannot parse the script
  def mismatches(filename)
    source = File.binread(filename)
    expected = joins(source)
    return unless expected

    lines = source.lines
    groups = Bashcov::Scanner.new(source).groups
    group_of = {}
    groups.each_with_index { |group, index| group.each { |lineno| group_of[lineno] = index } }

    1.upto(lines.size - 1).filter_map do |lineno|
      shfmt_joined = expected.include?(lineno)
      scanner_joined = group_of[lineno - 1] == group_of[lineno]
      next if shfmt_joined == scanner_joined
      # shfmt has no node for line continuations
      next if scanner_joined && continuation?(lines[lineno - 1])

      "#{filename}:#{lineno + 1}: #{scanner_joined ? 'joined' : 'not joined'} to the line before " \
        "by the scanner, #{shfmt_joined ? 'joined' : 'not joined'} by shfmt: #{lines[lineno].strip[0, 60]}"
    end
  end

  # @return [Boolean] whether +line+ ends with a line continuation
  def continuation?(line)
    line.chomp[/\\+\z/].to_s.size.odd?
  end

  # @return [Set<Integer>, nil] indexes (0-based) of the lines which belong to
  #   the same command as the line before, according to shfmt
  def joins(source)
    json, status = Open3.capture2(shfmt, "--to-json", "--language-dialect=bash", stdin_data: source)
    return unless status.success?

    joined = Set.new
    walk(JSON.parse(json)) do |node|
      first, last = span(node, source)
      next unless first && last

      (first + 1).upto(last) { |lineno| joined << lineno }
    end
    joined
  end

  def walk(node, &)
    case node
    when Hash
      yield node
      node.each_value { |value| walk(value, &) }
    when Array
      node.each { |value| walk(value, &) }
    end
  end

  # @return [Array(Integer, Integer), nil] first and last lines (0-based) of
  #   +node+ if it joins lines together
  def span(node, source)
    if JOINING_TYPES.include?(node["Type"])
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
      ansi&.gsub(/\\(.)/m, '\\1') || single || double&.gsub(/\\([\\"$`])/, '\\1') || escaped || plain
    end.join
  end

  def line(pos)
    pos && pos["Line"].to_i.positive? ? pos["Line"] - 1 : nil
  end
end
