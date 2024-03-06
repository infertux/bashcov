# frozen_string_literal: true

require "spec_helper"

shared_examples "a fatal error" do
  it "outputs to stderr" do
    expect($stderr).to receive(:write).at_least(:once)
    ignore_exception(SystemExit) { subject }
  end

  it "exits with non-zero" do
    expect { subject }.to raise_error do |error|
      expect(error).to be_a SystemExit
      expect(error.status).not_to eq(0)
    end
  end
end

describe Bashcov do
  it "preserves the exit status" do
    system("./bin/bashcov --root ./spec/test_app ./spec/test_app/scripts/exit_non_zero.sh")
    expect($?.exitstatus).not_to eq(0)
  end

  describe ".fullname" do
    it "includes the version" do
      expect(described_class.fullname).to include Bashcov::VERSION
    end
  end

  describe ".command_name" do
    before { described_class.command = ["touch", "/tmp/a/file"] }

    it "includes .command stringified" do
      expect(described_class.command_name).to eq described_class.command.compact.join(" ")
    end
  end

  describe ".mute" do
    it "delegates to .options" do
      described_class.options.mute = true
      expect(described_class).to respond_to(:mute)
      expect(described_class.mute).to be true

      expect { described_class.foo }.to raise_error(NoMethodError)
    end
  end

  describe ".parse_options!" do
    subject { described_class.parse_options! @args }

    before { @args = [] }

    context "without any options" do
      it_behaves_like "a fatal error"
    end

    context "with a filename" do
      before { @args << "script.sh" }

      context "with the --skip-uncovered flag" do
        before { @args << "--skip-uncovered" }

        it "sets it properly" do
          subject
          expect(described_class.skip_uncovered).to be true
        end
      end

      context "with the --mute flag" do
        before { @args << "--mute" }

        it "sets it properly" do
          subject
          expect(described_class.mute).to be true
        end
      end

      context "with the --bash-path option" do
        context "with an existing path" do
          before { @args += ["--bash-path", "/bin/bash"] }

          it "sets it properly" do
            skip("/bin/bash does not exist") unless File.executable?("/bin/bash")
            subject
            expect(described_class.bash_path).to eq("/bin/bash")
          end
        end

        context "with an non-existing path" do
          before { @args += ["--bash-path", "/pretty/sure/this/is/not/bash"] }

          it_behaves_like "a fatal error"
        end
      end

      context "with the --root option" do
        context "with an existing path" do
          before { @args += ["--root", "/etc"] }

          it "sets it properly" do
            subject
            expect(described_class.root_directory).to eq("/etc")
          end
        end

        context "with an non-existing path" do
          before { @args += ["--root", "/confident/this/does/not/exist/either"] }

          it_behaves_like "a fatal error"
        end
      end

      context "with the --command-name option" do
        context "with a command name name" do
          before { @args += ["--command-name", "mytestsuite"] }

          it "sets it properly" do
            subject
            expect(described_class.command_name).to eq("mytestsuite")
          end
        end

        context "with no command name" do
          before { @args << "--command-name" }

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
          expect { subject }.to raise_error do |error|
            expect(error).to be_a SystemExit
            expect(error.status).to eq(0)
          end
        end
      end
    end
  end
end
