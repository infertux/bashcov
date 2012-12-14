require 'spec_helper'

shared_examples "a fatal error" do
  it "outputs to stderr" do
    $stderr.should_receive(:write).at_least(:once)
    ignore_exception { subject }
  end

  it "exits with non-zero" do
    expect { subject }.to raise_error { |error|
      error.should be_a SystemExit
      error.status.should_not == 0
    }
  end
end

describe Bashcov do
  describe ".parse_options!" do
    before { @args = [] }

    subject { Bashcov.parse_options! @args }

    context "without any options" do
      it_behaves_like "a fatal error"
    end

    context "with a filename" do
      before { @args << 'script.sh' }

      context "with the --skip-uncovered flag" do
        before { @args << '--skip-uncovered' }

        it "sets it properly" do
          subject
          Bashcov.options.skip_uncovered.should be_true
        end
      end

      context "with the --mute flag" do
        before { @args << '--mute' }

        it "sets it properly" do
          subject
          Bashcov.options.mute.should be_true
        end
      end

      context "with the --help flag" do
        before { @args << '--help' }

        it_behaves_like "a fatal error"
      end

      context "with the --version flag" do
        before { @args << '--version' }

        it "outputs to stdout" do
          $stdout.should_receive(:write).at_least(:once)
          ignore_exception { subject }
        end

        it "exits with zero" do
          expect { subject }.to raise_error { |error|
            error.should be_a SystemExit
            error.status.should == 0
          }
        end
      end
    end
  end

  describe ".link" do
    it "includes the version" do
      Bashcov.link.should include Bashcov::VERSION
    end
  end
end

