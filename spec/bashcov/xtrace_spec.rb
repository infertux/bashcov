require "spec_helper"

require "tempfile"

describe Bashcov::Xtrace do
  ORIGINAL_PS4 = Bashcov::Xtrace::PS4.dup
  SUBSHELL_PS4 = (
      dirname = '$(cd $(dirname "$BASH_SOURCE"); pwd -P)'
      basename = '$(basename "$BASH_SOURCE")'
      %(#{Bashcov::Xtrace::PREFIX}#{dirname}/#{basename}/${LINENO}: )
  )

  let(:case_script) { test_app("scripts/case.sh") }
  let(:case_runner) { Bashcov::Runner.new "bash #{case_script}" }

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

  describe ".realpath" do
    context "given a path that does not exist" do
      it "returns the path cleaned of excess dots and slashes" do
        expect(Bashcov::Xtrace.realpath("/this//./is///a/path")).to eq("/this/is/a/path")
      end
    end

    context "given a path that contains symlinks" do
      it "resolves the symlinks to produce the on-disk path" do
        begin
          tempfile = Tempfile.new("bashcov")

          symlink_path = Dir::Tmpname.create("bashcov") do |path|
            File.symlink(tempfile.path, path)
          end

          expect(Bashcov::Xtrace.realpath(symlink_path)).to eq(tempfile.path)
        ensure
          tempfile.close unless tempfile.closed?
          tempfile.unlink
          File.unlink(symlink_path)
        end
      end
    end
  end

  describe "#realpath" do
    context "given a path" do
      it "caches the path" do
        xtrace = Bashcov::Xtrace.new
        path = "//hey/./././//a/path"
        resolved = xtrace.send(:realpath, path)
        expect(xtrace.instance_variable_get(:@path_cache)[path]).to eq(resolved)
      end
    end
  end
end
