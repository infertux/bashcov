require 'spec_helper'

describe Bashcov::Runner do
  before do
    @runner ||= Bashcov::Runner.new test_suite
  end

  describe "#run" do
    context "without a SHELLOPTS variable" do
      before do
        ENV['SHELLOPTS'] = nil
      end

      it "adds the flags" do
        @runner.run
        ENV['SHELLOPTS'].should == 'verbose:xtrace'
      end
    end

    context "with an existing SHELLOPTS variable" do
      before do
        ENV['SHELLOPTS'] = 'posix:verbose'
      end

      it "merges the flags" do
        @runner.run
        ENV['SHELLOPTS'].should == 'posix:verbose:xtrace'
      end
    end
  end

  describe "#find_bash_files" do
    it "returns the list of .sh files in the root directory" do
      files = @runner.find_bash_files
      files.class.should == Hash
      files.values.each do |lines|
        lines.each { |line| line.should == Bashcov::Line::UNCOVERED }
      end
    end
  end

  describe "#result" do
    it "returns a valid hash" do
      @runner.run
      result = @runner.result

      result.class.should == Hash
      result.should have(all_files.size).items
    end
  end
end
