require "spec_helper"

shared_examples "a fatal error" do
  it "outputs to stderr" do
    expect($stderr).to receive(:write).at_least(:once)
    ignore_exception(SystemExit) { subject }
  end

  it "exits with non-zero" do
    expect { subject }.to raise_error { |error|
      expect(error).to be_a SystemExit
      expect(error.status).not_to eq(0)
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
      before { @args << "script.sh" }

      context "with the --skip-uncovered flag" do
        before { @args << "--skip-uncovered" }

        it "sets it properly" do
          subject
          expect(Bashcov.options.skip_uncovered).to be true
        end
      end

      context "with the --mute flag" do
        before { @args << "--mute" }

        it "sets it properly" do
          subject
          expect(Bashcov.options.mute).to be true
        end
      end

      context "with the --help flag" do
        before { @args << "--help" }

        it_behaves_like "a fatal error"
      end

      context "with the --version flag" do
        before { @args << "--version" }

        it "outputs to stdout" do
          expect($stdout).to receive(:write).at_least(:once)
          ignore_exception(SystemExit) { subject }
        end

        it "exits with zero" do
          expect { subject }.to raise_error { |error|
            expect(error).to be_a SystemExit
            expect(error.status).to eq(0)
          }
        end
      end
    end
  end

  describe ".name" do
    it "includes the version" do
      expect(Bashcov.name).to include Bashcov::VERSION
    end
  end
end
