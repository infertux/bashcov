# frozen_string_literal: true

require "spec_helper"

describe Bashcov::HitRelocator do
  # Relocates the hits of +traced+ in +script+, in the coverage Bash reports
  # for it: each traced hit on the line it was traced on, and one hit for
  # each command holding them.
  # @param [Hash{Array(Integer, String, Integer, Integer) => Integer}] traced
  #   number of hits traced in a subshell by line, command, line of the
  #   command holding them and process, see {Bashcov::Xtrace#subshell_hits},
  #   lines 1-based
  # @return [Array(Hash{Integer => Integer}, Array<Integer>)] hits by line,
  #   and the lines hits were moved to, 1-based
  def relocate(script, traced)
    reported = Hash.new(0)
    traced.each { |(lineno, *), count| reported[lineno] += count }
    traced.keys.map { |_, _, holder| holder }.uniq.each { |holder| reported[holder] += 1 }
    coverage = Array.new(reported.keys.max) { |index| reported[index + 1] if reported.key?(index + 1) }

    relocator = described_class.new(script.lines, Bashcov::Scanner.new(script).groups)
    zero_based = traced.transform_keys { |lineno, command, holder, process| [lineno - 1, command, holder - 1, process] }
    relocated, reached = relocator.relocate(coverage, zero_based)

    [relocated.each_with_index.filter_map { |hit, index| [index + 1, hit] if hit }.to_h, reached.map(&:succ).sort]
  end

  let(:script) do
    <<~BASH
      echo before | cat
      out=$(
        if [ -n "$HOME" ]; then
          echo set
        else
          echo unset
        fi
        echo last >&2
      )
    BASH
  end

  {
    # from the line of the command holding the substitution, one command per line
    "as Bash 5.2 traces them" => { [9, '[ -n "$HOME" ]', 9] => 1, [10, "echo set", 9] => 1, [13, "echo last 1>&2", 9] => 1 },
    # from about the last line of that command, counting lines as written
    "as Bash traces them before 5.2" => { [10, '[ -n "$HOME" ]', 9] => 1, [11, "echo set", 9] => 1, [15, "echo last >&2", 9] => 1 },
  }.each do |layout, traced|
    it "moves each hit to the one command with its text, #{layout}" do
      expect(relocate(script, traced)).to eq [{ 3 => 1, 4 => 1, 8 => 1, 9 => 1 }, [3, 4, 8]]
    end
  end

  it "leaves a hit traced before the substitution on its line, whatever its process" do
    traced = { [1, "echo before", 9, 0] => 1, [1, "cat", 9, 1] => 1, [10, "echo set", 9, 2] => 1 }

    expect(relocate(script, traced)).to eq [{ 1 => 2, 4 => 1, 9 => 1 }, [4]]
  end

  it "moves no hit of a substitution when another process, such as a background job, traced in it" do
    traced = { [9, '[ -n "$HOME" ]', 9, 0] => 1, [10, "echo set", 9, 0] => 1, [13, "echo last 1>&2", 9, 1] => 1 }

    expect(relocate(script, traced).last).to eq []
  end

  {
    "matches no command" => "echo other",
    "matches several commands" => "echo",
  }.each do |reason, command|
    it "moves no hit of a substitution when one #{reason}" do
      traced = { [10, "echo set", 9] => 1, [11, command, 9] => 1 }

      expect(relocate(script, traced)).to eq [{ 9 => 1, 10 => 1, 11 => 1 }, []]
    end
  end

  {
    "a loop" => "for word in a; do\n    echo hi\n  done",
    "a case command" => "case a in\n    a) echo hi ;;\n  esac",
    "a function" => "greet() {\n    echo hi\n  }\n  greet",
    "a process substitution" => "cat <(\n    echo hi\n  )",
    "an ANSI-C quoted string" => "echo $'\\t'\n  echo hi",
    # where no command starts
    "the text in a quoted argument" => "printf '%s\\n' 'before echo hi after'",
    "the text in a double-quoted argument" => "printf '%s\\n' \"before; echo hi after\"",
    "the text in a comment" => "true # before; echo hi",
    "the text in a heredoc body" => "cat <<EOF\nbefore; echo hi\nEOF",
  }.each do |construct, commands|
    it "moves no hit of a substitution holding #{construct}, which Bash traces out of order, rewritten or not at all" do
      script = "x=$(\n  #{commands}\n)\n"
      holder = script.lines.size

      expect(relocate(script, { [holder + 1, "echo hi", holder] => 1 }).last).to eq []
    end
  end

  it "moves no hit of a substitution on whose lines hits of another were left" do
    script = "x=$(\n  echo one\n  echo one\n)\ny=$(\n  echo two\n)\n"
    traced = { [4, "echo one", 4] => 1, [5, "echo one", 4] => 1, [7, "echo two", 7] => 1 }

    expect(relocate(script, traced).last).to eq []
  end

  it "moves the hits of a substitution nested on one line to it" do
    script = "x=$(\n  echo \"$(date)\"\n  # date\n)\n"

    expect(relocate(script, { [4, "date", 4] => 1, [5, 'echo "$(date)"', 4] => 1 })).to eq [{ 2 => 2, 4 => 1 }, [2]]
  end

  it "joins the lines of a command continued with a backslash" do
    script = "x=$(\n  echo one \\\n    two\n)\n"

    expect(relocate(script, { [4, "echo one two", 4] => 1 })).to eq [{ 2 => 1, 4 => 1 }, [2]]
  end

  it "leaves the hits of a command which holds no substitution where they are" do
    expect(relocate(script, { [10, "echo set", 1] => 1 })).to eq [{ 1 => 1, 10 => 1 }, []]
  end
end
