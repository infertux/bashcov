require "spec_helper"
require "benchmark"

describe Bashcov::Runner do
  let(:runner) { Bashcov::Runner.new([Bashcov.options.bash_path, test_suite]) }

  around :each do |example|
    # Reset the options to, among other things, pick up on a new working
    # directory.
    Bashcov.set_default_options!

    Dir.chdir File.dirname(test_suite) do
      example.run
    end
  end

  describe "#inject_xtrace_flag!" do
    context "without a SHELLOPTS variable" do
      before do
        ENV["SHELLOPTS"] = nil
      end

      it "adds the flags" do
        runner.send(:inject_xtrace_flag!) do
          expect(ENV["SHELLOPTS"]).to eq("xtrace")
        end
      end
    end

    context "with an existing SHELLOPTS variable" do
      before do
        ENV["SHELLOPTS"] = "posix"
      end

      after do
        ENV["SHELLOPTS"] = nil
      end

      it "merges the flags" do
        runner.send(:inject_xtrace_flag!) do
          expect(ENV["SHELLOPTS"]).to eq("posix:xtrace")
        end
      end
    end
  end

  describe "#run" do
    it "finds commands in $PATH" do
      expect(Bashcov::Runner.new("ls -l").run).to be_success
    end

    it "is fast", speed: :slow do
      ratio = 0

      3.times do |iteration|
        t0 = Benchmark.realtime do
          pid = Process.spawn test_suite, out: "/dev/null", err: "/dev/null"
          Process.wait pid
        end
        expect($?).to be_success

        run = nil
        t1 = Benchmark.realtime { run = Bashcov::Runner.new(test_suite).run }
        expect(run).to be_success

        ratio = (ratio * iteration + t1 / t0) / (iteration + 1)
      end

      puts "#{ratio} times longer with Bashcov"
      # XXX: no proper assertion - just outputs the ratio
    end

    context "given a script that unsets $LINENO" do
      include_context("temporary script", "unset_lineno") do
        # @note "temporary script" context expects +script_text+ to be defined.
        let(:script_text) do
          <<-EOF.gsub(/\A\s+/, "")
            #!/bin/bash

            echo "Hello, world!"
            LINENO= echo "What line is this?"
            echo "Hello? Is anyone there?"
          EOF
        end

        let(:unset_lineno_coverage) { [nil, nil, 1, 0, 0] }
      end

      it "prints an error message" do
        expect { tmprunner.run }.to output(/expected integer.*got.*nil/).to_stderr
      end

      it "returns an incomplete coverage hash" do
        tmprunner.run
        expect(tmprunner.result[tmpscript.path]).to \
          contain_exactly(*unset_lineno_coverage)
      end
    end

    context "given a script whose path contains Xtrace::DELIM" do
      include_context("temporary script", Bashcov::Xtrace::DELIM) do
        # @note "temporary script" context expects +script_text+ to be defined.
        let(:script_text) do
          <<-EOF.gsub(/\A\s+/, "")
            #!/usr/bin/env bash

            echo "Oh no!"
          EOF
        end

        let(:bad_path_coverage) { [nil, nil, 0] }
      end

      context "given a version of Bash from 4.3 and up" do
        before do
          skip "Platform is using a Bash prior to 4.3" if Bashcov.truncated_ps4?
        end

        it "indicates that no lines were executed" do
          tmprunner.run
          expect(tmprunner.result[tmpscript.path]).to \
            contain_exactly(*bad_path_coverage)
        end
      end
    end

    context "given a version of Bash prior to 4.1" do
      include_context("temporary script", "no_stderr") do
        let(:stderr_output) { "AIEEE!" }

        # @note "temporary script" context expects +script_text+ to be defined.
        let(:script_text) do
          <<-EOF.gsub(/\A\s+/, "")
            #!/usr/bin/env bash

            echo #{stderr_output} 1>&2
          EOF
        end

        let(:xtracefd_warning) { Regexp.new(/Warning:.*older Bash version/) }

        around(:each) do |example|
          stored_has_bash_xtracefd = Bashcov.bash_xtracefd?

          Bashcov.module_exec do
            def bash_xtracefd?
              false
            end
            module_function :"bash_xtracefd?"
          end

          example.run

          Bashcov.module_exec do
            define_method :bash_xtracefd? do
              stored_has_bash_xtracefd
            end
            module_function :"bash_xtracefd?"
          end
        end

        after(:all) do
          Bashcov.set_default_options!
        end
      end

      context "when options.mute is true" do
        it "does not print a warning about the lack of BASH_XTRACEFD" do
          Bashcov.options.mute = true
          expect { tmprunner.run }.not_to output(xtracefd_warning).to_stderr
        end
      end

      context "when options.mute is false" do
        it "prints a warning about the lack of BASH_XTRACEFD" do
          Bashcov.options.mute = false
          expect { tmprunner.run }.to output(xtracefd_warning).to_stderr
        end
      end

      it "does not pass script output to standard error" do
        expect { tmprunner.run }.not_to output(stderr_output).to_stderr
      end
    end
  end

  describe "#result" do
    it "returns the expected coverage hash" do
      runner.run
      expect(runner.result).to eq expected_coverage
    end

    it "returns the correct coverage hash" do
      runner.run

      pending # TODO: need a context-aware lexer to parse multiline instructions
      expect(runner.result).to eq correct_coverage
    end

    context "with options.skip_uncovered = true" do
      before do
        Bashcov.options.skip_uncovered = true
      end

      it "does not include uncovered files" do
        runner.run
        expect(runner.result.keys & uncovered_files).to be_empty
      end
    end

    context "with options.mute = true" do
      before do
        Bashcov.options.mute = true
      end

      it "does not print the command output" do
        [$stdout, $stderr].each do |io|
          expect(io).not_to receive :write
        end

        runner.run
      end
    end
  end
end
