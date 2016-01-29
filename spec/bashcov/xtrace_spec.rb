require "spec_helper"

require "tempfile"

describe Bashcov::Xtrace do
  ORIGINAL_PS4 = Bashcov::Xtrace::PS4.dup
  SUBSHELL_PS4 = (
      dirname = '$(cd $(dirname "$BASH_SOURCE"); pwd -P)'
      basename = '$(basename "$BASH_SOURCE")'
      PS4 = %W(
        ${LINENO}
        #{[dirname, basename].join('/')}
        $(pwd)
        ${OLDPWD}
      ).reduce(Bashcov::Xtrace::DEPTH_CHAR + Bashcov::Xtrace::PREFIX) do |a, e|
        a + Bashcov::Xtrace::DELIM + e
      end + Bashcov::Xtrace::DELIM
  )

  let(:case_script) { test_app("scripts/case.sh") }
  let(:case_runner) { Bashcov::Runner.new "#{Bashcov.options.bash_path} #{case_script}" }

  before :all do
    Dir.chdir File.dirname(test_suite)
  end

  describe "Bashcov::Xtrace::PS4" do
    context "when shell expansion triggers subshell execution" do
      after do
        Bashcov::Xtrace.const_redefine(:PS4, ORIGINAL_PS4)
      end

      it "causes extra hits to be reported" do
        Bashcov.options.skip_uncovered = true

        case_runner.run
        result_without_subshell = case_runner.result[case_script].dup

        Bashcov::Xtrace.const_redefine(:PS4, SUBSHELL_PS4)
        case_runner.instance_variable_set(:@result, nil)
        case_runner.run
        result_with_subshell = case_runner.result[case_script].dup

        satisfy_msg = "have at least one line with fewer hits than #{result_with_subshell}"
        expect(result_without_subshell).to satisfy(satisfy_msg) do |r|
          result_with_subshell.zip(r).any? { |with, without| with.to_i > without.to_i }
        end
      end
    end
  end
end
