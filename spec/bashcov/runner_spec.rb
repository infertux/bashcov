require 'spec_helper'

describe Bashcov::Runner do
  before do
    @runner ||= Bashcov::Runner.new test_suite
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
      result.size.should == 8 # FIXME shouldn't be hardcoded
    end
  end
end
