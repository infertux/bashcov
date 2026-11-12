# frozen_string_literal: true

require "spec_helper"

describe Bashcov::Scanner do
  # @return [Array<Range>] groups spanning several lines, 1-based
  def multiline_groups(script)
    described_class.new(script).groups.map(&:lines).reject(&:one?).map { |lines| one_based(lines) }
  end

  # @return [Array] groups spanning several lines, 1-based. A group holding
  #   substitutions is a hash giving the groups of each of them.
  def multiline_commands(script)
    outline(described_class.new(script).groups.reject { |group| group.lines.one? })
  end

  def outline(groups)
    groups.map do |group|
      next one_based(group.lines) if group.substitutions.empty?

      substitutions = group.substitutions.to_h do |substitution|
        [one_based(substitution.lines), outline(substitution.groups)]
      end
      { one_based(group.lines) => substitutions }
    end
  end

  def one_based(lines)
    (lines.first + 1)..(lines.last + 1)
  end

  it "covers every line in order" do
    script = File.read(File.expand_path("../scanner_corpus/constructs.sh", __dir__))
    groups = described_class.new(script).groups

    expect(groups.flat_map { |group| group.lines.to_a }).to eq (0...script.lines.size).to_a
  end

  it "groups the lines of multiline constructs" do
    script = File.read(File.expand_path("../scanner_corpus/constructs.sh", __dir__))

    expect(multiline_groups(script)).to eq [
      5..6, 7..9, 10..11, 12..13, 14..15, 16..20, 21..22, 25..27, 28..30, 31..33, 34..36,
      37..40, 41..45, 48..50, 59..64, 65..66, 72..73, 75..78,
    ]
  end

  it "returns no groups for an empty script" do
    expect(described_class.new("").groups).to eq []
  end

  it "handles a script without a final newline" do
    expect(described_class.new("echo 'a\nb'").groups.map(&:lines)).to eq [0..1]
  end

  it "keeps quotes in comments from opening strings" do
    expect(multiline_groups("# don't\necho a\n# it's\n")).to eq []
  end

  it "does not end a command substitution at a case pattern" do
    script = <<~BASH
      x=$(case $1 in
        a) echo 'one
      two' ;;
      esac)
    BASH

    expect(multiline_commands(script)).to eq [{ 1..4 => { 1..4 => [1..1, 2..3, 4..4] } }]
  end

  it "recognizes case right at the start of a quoted command substitution" do
    script = <<~BASH
      x="$(case $1 in a) echo "it's" ;; esac)"
      echo 'a
      b'
    BASH

    expect(multiline_groups(script)).to eq [2..3]
  end

  it "does not read a left shift as a heredoc" do
    expect(multiline_groups("(( x = 1 << 2 ))\necho 2\n2\n")).to eq []
  end

  it "splits line continuations next to a pipe or a list operator" do
    script = <<~'BASH'
      echo 1 && \
        echo 2 \
        || echo 3
      echo 4 \
        5
    BASH

    expect(multiline_groups(script)).to eq [4..5]
  end

  it "splits line continuations after a semicolon or a background operator" do
    script = <<~'BASH'
      true; \
        echo 1
      sleep 1 & \
        echo 2
      echo 3 2>& \
        1
      find . -exec rm {} \; \
        -print
    BASH

    expect(multiline_groups(script)).to eq [5..6, 7..8]
  end

  it "reads heredoc delimiters which are partly quoted" do
    script = <<~'BASH'
      cat <<E"OF"
      OF
      EOF
      cat <<"a b"
      x
      a b
      cat <<\E'O'F
      y
      EOF
      cat <<'a"b'
      z
      a"b
    BASH

    expect(multiline_groups(script)).to eq [1..3, 4..6, 7..9, 10..12]
  end

  it "recognizes case only where a command starts" do
    script = <<~BASH
      x="$(echo case foo)"
      echo 'a
      b'
      y=$(if true; then case a in a) echo ;; esac; fi)
      echo 'c
      d'
    BASH

    expect(multiline_groups(script)).to eq [2..3, 5..6]
  end

  it "splits line continuations after a reserved word such as then" do
    script = <<~'BASH'
      if false; then \
        echo never; \
      fi
      for i in 1 2; do \
        echo "$i" \
          "$i"; \
      done
      exit;                                        \
      echo never
    BASH

    expect(multiline_groups(script)).to eq [5..6]
  end

  it "keeps line continuations together in a substitution" do
    script = <<~'BASH'
      check=$(echo "$check" | \
        sed -e 's/a/b/g' && \
        echo done)
    BASH

    expect(multiline_groups(script)).to eq [1..3]
  end

  it "reads heredoc delimiters which are empty or in ANSI-C quotes" do
    script = <<~BASH
      cat <<''
      text

      cat <<$'EOF'
      text
      EOF
    BASH

    expect(multiline_groups(script)).to eq [1..3, 4..6]
  end

  # each of these is valid Bash, after which the scanner must be back at the
  # top level to find the string which follows
  {
    "a shift in arithmetic parentheses" => "(( z = (1 << 2) ))",
    "double parentheses in arithmetic" => %q[x="$(echo $(( ((1 + 2)) * 2 )) "it's")"],
    "a comment in backticks" => "y=`echo a # it's`",
    "case in backticks" => "y=`case a in yes) echo no;; *) echo yes;; esac`",
    "case in a subshell of a substitution" => %q[y="$( (case a in a) echo "it's" ;; esac) )"],
    "case in a function of a substitution" => %q[y="$(f() { case a in a) echo "it's" ;; esac; }; f)"],
    "single quotes in a parameter expansion in double quotes" => %q[echo "${x%'"c"'}" "${x//'}'/}" "$(echo ${x%'}'})"],
    "an extended glob in an array" => %q[arr=( !(*.txt|"it's") )],
    "an escaped backslash before a separator" => %q(echo \\\; echo "it's"),
    "an escaped backtick in a comment in backticks" => %q(y=`echo a # it's \` here`),
  }.each do |name, script|
    it "keeps track after #{name}" do
      expect(multiline_groups("#{script}\necho 'a\nb'\n")).to eq [2..3]
    end
  end

  it "reads a heredoc delimiter which follows a line continuation" do
    script = <<~'BASH'
      cat <<\
      EOF
      it's
      EOF
      echo 'a
      b'
    BASH

    expect(multiline_groups(script)).to eq [1..4, 5..6]
  end

  it "joins the lines of a heredoc which end with a line continuation, unless its delimiter is quoted" do
    script = <<~'BASH'
      cat <<EOF
      text \
      EOF
      echo "still in the heredoc"
      EO\
      F
      cat <<'EOF'
      text \
      EOF
      cat <<EOF
      text \\
      EOF
      echo 'a
      b'
    BASH

    expect(multiline_groups(script)).to eq [1..6, 7..9, 10..12, 13..14]
  end

  it "splits a line continuation after a separator which follows an escaped backslash" do
    script = <<~'BASH'
      exit \\; \
      echo 'never
      never'
    BASH

    expect(multiline_groups(script)).to eq [2..3]
  end

  context "with a command substitution spanning several lines" do
    it "keeps its commands apart, in the group of the command which holds it" do
      script = <<~BASH
        echo before
        x="$(
          if false; then
            echo never
          fi
          echo yes
        )"
        echo after
      BASH

      expect(multiline_commands(script)).to eq [{ 2..7 => { 2..7 => [2..2, 3..3, 4..4, 5..5, 6..6, 7..7] } }]
    end

    it "groups the lines of each of its commands" do
      script = <<~BASH
        x=$(cat <<EOF
        text
        EOF
          echo 'a
        b'
          echo c)
      BASH

      expect(multiline_commands(script)).to eq [{ 1..6 => { 1..6 => [1..3, 4..5, 6..6] } }]
    end

    it "finds the substitutions of its commands" do
      script = <<~BASH
        x=$(echo "$(
          echo a
        )" b
          echo c)
      BASH

      inner = { 1..3 => { 1..3 => [1..1, 2..2, 3..3] } }
      expect(multiline_commands(script)).to eq [{ 1..4 => { 1..4 => [inner, 4..4] } }]
    end

    it "tells apart two substitutions of the same command" do
      script = <<~BASH
        x=`echo a
          echo b
        ` y=$(echo c
          echo d
        )
      BASH

      expect(multiline_commands(script)).to eq [{ 1..5 => { 1..3 => [1..1, 2..2, 3..3], 3..5 => [3..3, 4..4, 5..5] } }]
    end

    it "ends at its closing parenthesis after nested subshells" do
      script = <<~BASH
        x=$(
          (echo 1) |
            ( (echo 2) |
            cat)
        )
        echo 'a
        b'
      BASH

      expect(multiline_commands(script)).to eq [{ 1..5 => { 1..5 => [1..1, 2..2, 3..3, 4..4, 5..5] } }, 6..7]
    end

    it "keeps the string which holds it in one group" do
      script = <<~BASH
        echo "a $(
          echo b
        ) c
        d"
      BASH

      expect(multiline_commands(script)).to eq [{ 1..4 => { 1..3 => [1..1, 2..2, 3..3] } }]
    end

    it "leaves the remaining lines on their own if the script ends inside it" do
      script = "echo a\nx=$(\necho b\necho c\n"

      expect(multiline_commands(script)).to eq []
    end
  end

  it "leaves the remaining lines on their own if the script ends inside a construct" do
    script = "echo a\necho 'b\nc\nd\n"

    expect(described_class.new(script).groups.map(&:lines)).to eq [0..0, 1..1, 2..2, 3..3]
  end

  it "leaves the remaining lines on their own if a heredoc is not terminated" do
    script = "cat <<EOF\na\nb\n"

    expect(described_class.new(script).groups.map(&:lines)).to eq [0..0, 1..1, 2..2]
  end

  context "with shfmt as a reference", :shfmt do
    before { skip "shfmt is not installed (only needed in CI)" unless ShfmtOracle.available? }

    it "groups lines like shfmt's parser" do
      corpus = File.expand_path("../scanner_corpus/constructs.sh", __dir__)
      expect(ShfmtOracle.mismatches(corpus)).not_to be_nil, "shfmt could not parse #{corpus}"

      scripts = Dir[File.expand_path("../{scanner_corpus,test_app}/**/*", __dir__)].select do |file|
        File.file?(file) && Bashcov::Detective.new(Bashcov.bash_path).shellscript?(file)
      end
      scripts += ENV.fetch("SHFMT_CORPUS", "").split.flat_map { |pattern| Dir[pattern] }.select do |file|
        File.file?(file) && Bashcov::Detective.new(Bashcov.bash_path).shellscript?(file)
      end

      checked = scripts.uniq.filter_map { |file| ShfmtOracle.mismatches(file) }
      warn "checked #{checked.size} of #{scripts.uniq.size} scripts against shfmt"

      expect(checked.flatten).to eq []
    end
  end
end
