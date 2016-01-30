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
  it "preserves the exit status" do
    system("./bin/bashcov ./spec/test_app/scripts/exit_non_zero.sh")
    expect($?.exitstatus).not_to eq(0)
  end

  describe ".fullname" do
    it "includes the version" do
      expect(Bashcov.fullname).to include Bashcov::VERSION
    end
  end

  describe ".respond_to_missing?" do
    it "delegates to .options" do
      allow(Bashcov.options).to receive(:foo).and_return("bar")
      expect(Bashcov).to respond_to(:foo)

      expect(Bashcov.options).not_to respond_to(:bar)
      expect(Bashcov).not_to respond_to(:bar)
    end
  end

  describe ".method_missing" do
    it "delegates to .options" do
      allow(Bashcov.options).to receive(:foo).and_return("bar")
      expect(Bashcov).to respond_to(:foo)
      expect(Bashcov.foo).to eq("bar")

      expect(Bashcov.options.bar).to be nil
      expect(Bashcov.bar).to be nil

      allow(Bashcov.options).to receive(:baz).and_raise(NoMethodError, "whoops")
      expect { Bashcov.baz }.to raise_error do |error|
        expect(error).to be_a(NoMethodError)
        expect(error.message).to eq("whoops")
      end
    end
  end

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
          expect(Bashcov.skip_uncovered).to be true
        end
      end

      context "with the --mute flag" do
        before { @args << "--mute" }

        it "sets it properly" do
          subject
          expect(Bashcov.mute).to be true
        end
      end

      context "with the --bash-path option" do
        context "given an existing path" do
          before { @args += ["--bash-path", "/bin/bash"] }

          it "sets it properly" do
            subject
            expect(Bashcov.bash_path).to eq("/bin/bash")
          end
        end

        context "given an non-existing path" do
          before(:each) { @args += ["--bash-path", "/pretty/sure/this/is/not/bash"] }

          it_behaves_like "a fatal error"
        end
      end

      context "with the --root option" do
        context "given an existing path" do
          before { @args += ["--root", "/etc"] }

          it "sets it properly" do
            subject
            expect(Bashcov.root_directory).to eq("/etc")
          end
        end

        context "given an non-existing path" do
          before(:each) { @args += ["--root", "/confident/this/does/not/exist/either"] }

          it_behaves_like "a fatal error"
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
end
