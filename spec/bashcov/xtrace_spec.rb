# frozen_string_literal: true

require "spec_helper"
require "stringio"
require "timeout"

describe Bashcov::Xtrace do
  describe "#file_descriptor" do
    it "exposes a blocking write end" do
      xtrace = described_class.new(StringIO.new)
      writer = IO.for_fd(xtrace.file_descriptor, autoclose: false)

      expect(writer.nonblock?).to be(false)
    ensure
      writer&.close
      xtrace&.close
      read = xtrace&.instance_variable_get(:@read)
      read&.close unless read&.closed?
    end
  end

  describe "#read" do
    it "raises a buffered parse error after close even if another writer remains open" do
      xtrace = described_class.new(Bashcov::FieldStream.new)
      allow(xtrace).to receive(:find_script).and_raise(Errno::EACCES)
      writer = IO.for_fd(xtrace.file_descriptor, autoclose: false)
      background_writer = writer.dup
      record = "#{described_class.make_ps4('1', 'script.sh', '/', '')}\n"
      background_writer.write(record * 2)
      background_writer.flush
      xtrace.close

      expect do
        Timeout.timeout(2) { xtrace.read }
      end.to raise_error(Errno::EACCES)
    ensure
      background_writer&.close
      writer&.close
    end

    it "skips malformed records and keeps parsing" do
      xtrace = described_class.new(Bashcov::FieldStream.new)
      writer = IO.for_fd(xtrace.file_descriptor, autoclose: false)
      bad = "#{described_class.make_ps4('\\${LINENO-}', '', '', '')}\n"
      good = "#{described_class.make_ps4('3', '/script.sh', '/', '')}\n"
      writer.write(good + bad + good)
      writer.flush
      xtrace.close

      files = Timeout.timeout(2) { xtrace.read }

      expect(files.values).to eq([[nil, nil, 2]])
      expect(xtrace.skipped_count).to eq(1)
    ensure
      writer&.close
    end
  end

  describe "#subshell_hits" do
    # @param [Array<Array(String, String, String, String, String, String)>]
    #   records line, subshell level, command, traced text and, optionally,
    #   depth of calls, function, script and process of each record
    def subshell_hits(*records)
      xtrace = described_class.new(Bashcov::FieldStream.new)
      writer = IO.for_fd(xtrace.file_descriptor, autoclose: false)
      writer.write(records.map do |lineno, subshell, command, trace, calls = "1", function = "", script = "/script.sh", process = "1"|
        "#{described_class.make_ps4(lineno, script, '/', '', subshell, calls, process, function, command)}#{trace}\n"
      end.join)
      writer.flush
      xtrace.close

      Timeout.timeout(2) { xtrace.read }
      xtrace.subshell_hits.fetch(Pathname.new("/script.sh"))
    ensure
      writer&.close
    end

    it "counts the hits traced in a subshell by line and command, with the line of the command holding them" do
      hits = subshell_hits(
        ["2", "0", "echo a", "echo a"],
        ["5", "1", "echo b", "echo b"],
        ["5", "2", "echo b", "echo b"],
        ["6", "1", "echo c", "echo c"],
        ["6", "0", "x=$(echo b", "x=c"],
        ["9", "1", "echo d", "echo d"],
      )

      expect(hits).to eq(
        [4, "echo b", false, [5], nil] => 1, [4, "echo b", false, [5, 5], nil] => 1, [5, "echo c", false, [5], nil] => 1,
        [8, "echo d", false, [nil], nil] => 1,
      )
    end

    it "tells a header which Bash traced with the command run before" do
      hits = subshell_hits(
        ["3", "1", "x=$(for i in 1 2; do", "for i in 1 2"],
        ["4", "1", 'echo "$i"', "echo 1"],
        ["3", "1", 'echo "$i"', "for i in 1 2"],
        ["4", "1", 'echo "$i"', "echo 2"],
        ["4", "0", "x=$(for i in 1 2; do", "x=$'1\\n2'"],
      )

      expect(hits).to eq(
        [2, "x=$(for i in 1 2; do", false, [3], nil] => 1, [3, 'echo "$i"', false, [3], nil] => 2, [2, 'echo "$i"', true, [3], nil] => 1,
      )
    end

    it "tells an arithmetic command run again on another line from a header" do
      hits = subshell_hits(
        ["3", "1", "((i++))", "(( i++ ))"],
        ["4", "1", "((i++))", "(( i++ ))"],
        ["2", "0", "x=$(i=0", "x="],
      )

      expect(hits).to eq([2, "((i++))", false, [1], nil] => 1, [3, "((i++))", false, [1], nil] => 1)
    end

    it "keeps the hits of a substitution for its command when it runs another Bash" do
      hits = subshell_hits(
        ["3", "1", "echo start", "echo start"],
        ["1", "0", "echo child", "echo child", "1", "", "/child.sh", "2"],
        ["5", "1", "echo end", "echo end"],
        ["3", "0", "x=$(echo start", "x=start"],
      )

      expect(hits).to eq([2, "echo start", false, [2], nil] => 1, [4, "echo end", false, [2], nil] => 1)
    end

    it "gives the hits which the command of an EXIT trap held to the command traced next with the same text" do
      # Bash 4.4 traces the trap of a substitution out of it, on the first line
      hits = subshell_hits(
        ["10", "1", "echo hi", "echo hi"],
        ["1", "0", "x=$(", "echo bye"],
        ["9", "0", "x=$(", "x=hi"],
      )

      expect(hits).to eq([9, "echo hi", false, [8], nil] => 1)
    end

    it "gives the hits which the commands of an EXIT trap held to the command traced after them" do
      hits = subshell_hits(
        ["10", "1", "echo hi", "echo hi"],
        ["1", "0", "x=$(", ":"],
        ["1", "0", "x=$(", ":"],
        ["9", "0", "x=$(", "x=hi"],
      )

      expect(hits).to eq([9, "echo hi", false, [8], nil] => 1)
    end

    it "keeps the hits which an EXIT trap held for the command traced after the function it calls" do
      hits = subshell_hits(
        ["7", "1", "echo yes", "echo yes"],
        ["1", "0", "x=$(", "cleanup"],
        ["3", "0", "x=$(", ":", "2", "cleanup"],
        ["8", "0", "x=$(", "x=yes"],
      )

      expect(hits).to eq([6, "echo yes", false, [7], nil] => 1)
    end

    it "keeps the hits which an EXIT trap held when the function it calls runs a substitution" do
      hits = subshell_hits(
        ["7", "1", "echo yes", "echo yes"],
        ["1", "0", "x=$(", "cleanup"],
        ["3", "1", "x=$(", "echo clean", "2", "cleanup"],
        ["3", "0", "x=$(", "ignored=clean", "2", "cleanup"],
        ["8", "0", "x=$(", "x=yes"],
      )

      expect(hits).to eq([6, "echo yes", false, [7], nil] => 1, [2, "x=$(", false, [2], nil] => 1)
    end

    it "keeps the hits which an EXIT trap of several lines held for the command traced after it" do
      hits = subshell_hits(
        ["10", "1", "echo yes", "echo yes"],
        ["2", "0", "x=$(", "cleanup"],
        ["3", "0", "x=$(", ":", "2", "cleanup"],
        ["3", "0", "x=$(", ":"],
        ["11", "0", "x=$(", "x=yes"],
      )

      expect(hits).to eq([9, "echo yes", false, [10], nil] => 1)
    end

    it "leaves the hits of a substitution on its command when a loop header is traced next with its text" do
      hits = subshell_hits(
        ["10", "1", "echo run", "echo run"],
        ["8", "0", "x=$(:; :; :", "x=run"],
        ["2", "0", "x=$(:; :; :", "for iteration in 1 2"],
        ["8", "1", ":", ":"],
        ["8", "0", "x=$(:; :; :", "x="],
      )

      expect(hits).to eq([9, "echo run", false, [7], nil] => 1, [7, ":", false, [7], nil] => 1)
    end

    it "tells a command run again on another line from a header" do
      hits = subshell_hits(
        ["2", "1", "echo a", "echo a"],
        ["3", "1", "echo a", "echo a"],
        ["4", "1", "echo a", "for i in 1"],
        ["4", "0", "x=$(echo a", "x=a"],
      )

      expect(hits).to eq([1, "echo a", false, [3], nil] => 1, [2, "echo a", false, [3], nil] => 1, [3, "echo a", true, [3], nil] => 1)
    end

    it "tells a command run again at the end of the trace from a header" do
      hits = subshell_hits(
        ["3", "1", "echo a", "echo a"],
        ["4", "1", "echo a", "echo a"],
      )

      expect(hits).to eq([2, "echo a", false, [nil], nil] => 1, [3, "echo a", false, [nil], nil] => 1)
    end

    it "tells a header which Bash traced with the command run before, after the substitutions of the header" do
      hits = subshell_hits(
        ["2", "1", "echo previous", "echo previous"],
        ["3", "1", "echo previous", 'case "$(echo nested)" in'],
        ["3", "2", "echo nested", "echo nested"],
        ["3", "1", "echo previous", 'case "$(echo nested)" in'],
        ["4", "1", "echo matched", "echo matched"],
      )

      expect(hits).to eq(
        [1, "echo previous", false, [nil], nil] => 1, [2, "echo previous", true, [nil], nil] => 2,
        [2, "echo nested", false, [2, nil], nil] => 1, [3, "echo matched", false, [nil], nil] => 1,
      )
    end

    it "gives the hits of a substitution the line of its command when that command runs in a subshell" do
      hits = subshell_hits(
        %w[5 2 true true],
        ["5", "2", "echo same", "echo same"],
        ["5", "1", "x=$(true", "x=same"],
        ["8", "2", "echo same", "echo same"],
        ["8", "1", "y=$(echo same)", "y=same"],
      )

      expect(hits).to eq(
        [4, "true", false, [4, nil], nil] => 1, [4, "echo same", false, [4, nil], nil] => 1, [4, "x=$(true", false, [nil], nil] => 1,
        [7, "echo same", false, [7, nil], nil] => 1, [7, "y=$(echo same)", false, [nil], nil] => 1,
      )
    end

    it "tells the commands of a function called in a substitution" do
      hits = subshell_hits(
        ["5", "1", "echo same", "echo same", "2", "main"],
        ["2", "1", "echo same", "echo same", "3", "helper"],
        ["8", "1", "echo same", "echo same", "3", "main"],
        ["5", "0", "x=$(echo same; helper; main)", "x=same", "2", "main"],
        ["8", "1", "echo same", "echo same"],
        ["8", "0", "y=$(echo same)", "y=same"],
      )

      expect(hits).to eq(
        [4, "echo same", false, [4], nil] => 1, [1, "echo same", false, [4], "helper"] => 1,
        [7, "echo same", false, [4], "main"] => 1, [7, "echo same", false, [7], nil] => 1,
      )
    end

    it "leaves out the commands of another script called in a substitution" do
      hits = subshell_hits(
        ["2", "1", "echo lib", "echo lib", "2", "source", "/lib.sh"],
        ["5", "1", "echo same", "echo same"],
        ["5", "0", "x=$(. ./lib.sh; echo same)", "x=same"],
      )

      expect(hits).to eq([4, "echo same", false, [4], nil] => 1)
    end
  end

  describe ".ps4" do
    let!(:subshell_ps4) do
      dirname = '$(cd $(dirname "$BASH_SOURCE"); pwd -P)'
      basename = '$(basename "$BASH_SOURCE")'
      described_class.make_ps4(*%W[${LINENO-} #{[dirname, basename].join('/')} $(PWD-) ${OLDPWD-}])
    end

    let(:case_script) { test_app("scripts/case.sh") }
    let(:case_runner) { Bashcov::Runner.new([Bashcov.bash_path, case_script]) }

    def case_result
      case_runner.tap(&:run).result[case_script].dup.fetch("lines")
    end

    before do
      Dir.chdir File.dirname(test_suite)
    end

    context "when shell expansion triggers subshell execution" do
      it "causes extra hits to be reported" do
        allow(Bashcov).to receive(:skip_uncovered).at_least(:once).and_return(true)
        result_without_subshell = case_result

        allow(described_class).to receive(:ps4).and_return(subshell_ps4)
        result_with_subshell = case_result

        satisfy_msg = "have at least one line with fewer hits than #{result_with_subshell}"
        expect(result_without_subshell).to satisfy(satisfy_msg) do |r|
          result_with_subshell.zip(r).any? { |with, without| with.to_i > without.to_i }
        end
      end
    end
  end
end
