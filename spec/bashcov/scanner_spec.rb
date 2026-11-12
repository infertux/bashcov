# frozen_string_literal: true

require "spec_helper"

describe Bashcov::Scanner do
  # @return [Array<Range>] groups spanning several lines, 1-based
  def multiline_groups(script)
    described_class.new(script).groups.reject(&:one?).map { |group| (group.first + 1)..(group.last + 1) }
  end

  it "covers every line in order" do
    script = File.read(File.expand_path("../scanner_corpus/constructs.sh", __dir__))
    groups = described_class.new(script).groups

    expect(groups.flat_map(&:to_a)).to eq (0...script.lines.size).to_a
  end

  it "groups the lines of multiline constructs" do
    script = File.read(File.expand_path("../scanner_corpus/constructs.sh", __dir__))

    expect(multiline_groups(script)).to eq [
      5..6, 7..9, 10..11, 12..13, 14..15, 16..20, 21..22, 25..27, 28..30, 31..33, 34..36,
      37..39, 41..45, 48..50, 65..66, 72..73, 75..77,
    ]
  end

  it "returns no groups for an empty script" do
    expect(described_class.new("").groups).to eq []
  end

  it "handles a script without a final newline" do
    expect(described_class.new("echo 'a\nb'").groups).to eq [0..1]
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

    expect(multiline_groups(script)).to eq [2..3]
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

  it "leaves the remaining lines on their own if the script ends inside a construct" do
    script = "echo a\necho 'b\nc\nd\n"

    expect(described_class.new(script).groups).to eq [0..0, 1..1, 2..2, 3..3]
  end

  it "leaves the remaining lines on their own if a heredoc is not terminated" do
    script = "cat <<EOF\na\nb\n"

    expect(described_class.new(script).groups).to eq [0..0, 1..1, 2..2]
  end

  context "with shfmt as a reference", :shfmt do
    before { skip "shfmt is not installed (only needed in CI)" unless ShfmtOracle.available? }

    it "groups lines like shfmt's parser" do
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
