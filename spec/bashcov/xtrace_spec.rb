require 'spec_helper'

describe Bashcov::Xtrace do
  let(:xtrace) {
    runner = Bashcov::Runner.new test_suite
    runner.run
    Bashcov::Xtrace.new runner.stderr
  }

  describe "#files" do
    let(:files) { xtrace.files }
    subject { files }

    it { should be_a Hash }

    it "contains expected files" do
      subject.keys.should =~ executed_files
    end
  end
end
