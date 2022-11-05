# frozen_string_literal: true

require "spec_helper"

describe Bashcov::Xtrace do
  describe ".ps4" do
    let!(:subshell_ps4) do
      dirname = '$(cd $(dirname "$BASH_SOURCE"); pwd -P)'
      basename = '$(basename "$BASH_SOURCE")'
      described_class.make_ps4(*%W[${LINENO-} #{[dirname, basename].join('/')} $(PWD-) ${OLDPWD-}])
    end

    let(:case_script) { test_app("scripts/case.sh") }
    let(:case_runner) { Bashcov::Runner.new([Bashcov.bash_path, case_script]) }

    def case_result
      case_runner.tap(&:run).result[case_script].dup
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
