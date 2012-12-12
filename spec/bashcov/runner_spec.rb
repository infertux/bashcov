require 'spec_helper'

describe Bashcov::Runner do
  let(:runner) { Bashcov::Runner.new test_suite }
  let(:bash_files_glob) { "#{Bashcov.root_directory}/**/*.sh" }

  describe "#run" do
    context "without a SHELLOPTS variable" do
      before do
        ENV['SHELLOPTS'] = nil
      end

      it "adds the flags" do
        runner.run
        ENV['SHELLOPTS'].should == 'verbose:xtrace'
      end
    end

    context "with an existing SHELLOPTS variable" do
      before do
        ENV['SHELLOPTS'] = 'posix:verbose'
      end

      it "merges the flags" do
        runner.run
        ENV['SHELLOPTS'].should == 'posix:verbose:xtrace'
      end
    end
  end

  describe "#find_bash_files" do
    let(:files) { runner.find_bash_files bash_files_glob }
    subject { files }

    it { should be_a Hash }

    it "contains bash files" do
      subject.keys.should =~ bash_files
    end

    it "marks files as uncovered" do
      subject.values.each do |lines|
        lines.each { |line| line.should == Bashcov::Line::UNCOVERED }
      end
    end
  end

  describe "#add_coverage_result" do
    let(:files) {
      runner.run
      files = runner.find_bash_files bash_files_glob
      runner.add_coverage_result files
    }
    subject { files }

    it { should be_a Hash }

    it "contains all files" do
      subject.keys.should =~ all_files
    end

    it "adds correct coverage results" do
      subject.each do |file, lines|
        lines.each_with_index do |line, lineno|
          [
            Bashcov::Line::UNCOVERED,
            expected_coverage[file][lineno]
          ].should include line
        end
      end
    end
  end

  describe "#result" do
    it "returns a valid coverage hash" do
      runner.run

      runner.result.should == expected_coverage
    end
  end
end
