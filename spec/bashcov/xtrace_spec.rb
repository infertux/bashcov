# frozen_string_literal: true

require "spec_helper"

describe Bashcov::Xtrace do
  describe ".delimiter" do
    around(:each) do |example|
      stored_delimiter = Bashcov::Xtrace.delimiter
      Bashcov::Xtrace.delimiter = nil
      example.run
      Bashcov::Xtrace.delimiter = stored_delimiter
    end

    context "on Bash 4.2 and prior", if: Bashcov::BASH_VERSION <= "4.2" do
      it "is the ASCII record separator character" do
        expect(Bashcov::Xtrace.delimiter).to eq("\x1E")
      end
    end

    context "on Bash 4.3 and later", if: Bashcov::BASH_VERSION >= "4.3" do
      let(:uuid_match) { /\A[\dA-F]{8}-[\dA-F]{4}-4[\dA-F]{3}-[89AB][\dA-F]{3}-[\dA-F]{12}\z/i }

      it "is a UUID" do
        expect(Bashcov::Xtrace.delimiter).to match(uuid_match)
      end
    end
  end

  describe ".ps4" do
    let!(:subshell_ps4) do
      dirname = '$(cd $(dirname "$BASH_SOURCE"); pwd -P)'
      basename = '$(basename "$BASH_SOURCE")'
      Bashcov::Xtrace.make_ps4(*%W[${LINENO} #{[dirname, basename].join('/')} $(pwd) ${OLDPWD}])
    end

    let(:case_script) { test_app("scripts/case.sh") }
    let(:case_runner) { Bashcov::Runner.new([Bashcov.bash_path, case_script]) }

    def case_result
      case_runner.tap(&:run).result[case_script].dup
    end

    before :each do
      Dir.chdir File.dirname(test_suite)
    end

    context "when shell expansion triggers subshell execution" do
      it "causes extra hits to be reported" do
        result_without_subshell = case_result

        allow(Bashcov).to receive(:skip_uncovered).and_return(true)
        allow(Bashcov::Xtrace).to receive(:ps4).and_return(subshell_ps4)

        result_with_subshell = case_result

        satisfy_msg = "have at least one line with fewer hits than #{result_with_subshell}"
        expect(result_without_subshell).to satisfy(satisfy_msg) do |r|
          result_with_subshell.zip(r).any? { |with, without| with.to_i > without.to_i }
        end
      end
    end
  end
end
