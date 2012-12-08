require 'spec_helper'

describe Bashcov::Xtrace do
  before do
    @runner ||= Bashcov::Runner.new test_suite
    @runner.run

    @xtrace ||= Bashcov::Xtrace.new @runner.output
  end

  describe "#files" do
    it "returns a list of executed files" do
      files = @xtrace.files
      files.class.should == Hash
      files.keys.should =~ executed_files + [test_suite]
    end
  end
end
