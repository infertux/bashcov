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
    # @param [Array<Array<String>>] records fields of each record: line,
    #   script, subshell level, depth of calls and command
    def subshell_hits(records)
      xtrace = described_class.new(Bashcov::FieldStream.new)
      writer = IO.for_fd(xtrace.file_descriptor, autoclose: false)
      records.each do |lineno, script, subshell, calls, command|
        writer.write("#{described_class.make_ps4(lineno, script, '/', '', subshell, calls, command)}\n")
      end
      writer.flush
      xtrace.close
      Timeout.timeout(2) { xtrace.read }

      xtrace.subshell_hits.transform_keys(&:to_s)
    ensure
      writer&.close
    end

    it "keeps the hits traced in a subshell with the next command of their script traced out of any" do
      records = [
        %w[7 /a.sh 1 1 true], %w[8 /a.sh 2 1 date], %w[2 /b.sh 0 1 other], %w[7 /a.sh 1 1 true], %w[5 /a.sh 0 1 x=],
      ]

      expect(subshell_hits(records)).to eq("/a.sh" => { [6, "true", 4] => 2, [7, "date", 4] => 1 })
    end

    it "leaves out the hits of functions called from the subshell" do
      records = [%w[2 /a.sh 1 2 helper], %w[7 /a.sh 1 1 true], %w[5 /a.sh 0 1 x=]]

      expect(subshell_hits(records)).to eq("/a.sh" => { [6, "true", 4] => 1 })
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
