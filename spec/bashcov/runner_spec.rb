# frozen_string_literal: true

require "spec_helper"
require "benchmark"

describe Bashcov::Runner do
  let(:runner) { Bashcov::Runner.new([Bashcov.bash_path, test_suite]) }

  around(:each) do |example|
    Dir.chdir File.dirname(test_suite) do
      example.run
    end
  end

  describe "#with_xtrace_flag" do
    context "without a SHELLOPTS variable" do
      before do
        ENV["SHELLOPTS"] = nil
      end

      it "adds the flags" do
        runner.send(:with_xtrace_flag) do
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
        runner.send(:with_xtrace_flag) do
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
      include_context "temporary script", "unset_lineno" do
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

    context "given a script whose path contains Xtrace.delimiter" do
      # @note Due to the way that RSpec orders evaluation of contexts,
      # examples, and example hooks, {Bashcov::Xtrace.delimiter} in:
      #   +include_context "temporary script", Bashcov::Xtrace.delimiter+
      # gets expanded prior to setting Bashcov.bash_path in +spec_helper.rb+,
      # which causes an inappropriate value for {Bashcov::Xtrace.delimiter} if the
      # default Bash (+/bin/bash+) does not suffer from the truncated +PS4+ bug
      # but the Bash keyed to the +BASHCOV_BASH_PATH+ environment variable
      # does. We therefore have to run the same code block here to ensure the
      # value is set properly at the time the temporary script is created.
      Bashcov.bash_path = ENV["BASHCOV_BASH_PATH"] unless ENV["BASHCOV_BASH_PATH"].nil?

      include_context "temporary script", Bashcov::Xtrace.delimiter do
        # @note "temporary script" context expects +script_text+ to be defined.
        let(:script_text) do
          <<-EOF.gsub(/\A\s+/, "")
            #!/usr/bin/env bash

            echo "Oh no!"
          EOF
        end

        let(:bad_path_coverage) { [nil, nil, 0] }
      end

      context "given a version of Bash from 4.3 and up", if: BASHVER >= "4.3" do
        it "indicates that no lines were executed" do
          tmprunner.run

          # Hack to execute this line (and get it counted in the coverage
          # stats) even if we're on Bash 4.2
          expect(tmprunner.result[tmpscript.path]).to \
            contain_exactly(*bad_path_coverage) unless Bashcov.truncated_ps4?
        end
      end
    end

    context "given a version of Bash prior to 4.1", if: BASHVER < "4.1" do
      include_context "temporary script", "no_stderr" do
        let(:stderr_output) { "AIEEE!" }

        # @note "temporary script" context expects +script_text+ to be defined.
        let(:script_text) do
          <<-EOF.gsub(/\A\s+/, "")
            #!/usr/bin/env bash

            echo #{stderr_output} 1>&2
          EOF
        end

        let(:xtracefd_warning) { Regexp.new(/warning:.*version of Bash/) }
      end

      context "when mute is true" do
        it "does not print a warning about the lack of BASH_XTRACEFD" do
          allow(Bashcov).to receive(:bash_xtracefd?).and_return(false)
          allow(Bashcov).to receive(:mute).and_return(true)
          expect { tmprunner.run }.not_to output(xtracefd_warning).to_stderr
        end
      end

      context "when mute is false" do
        it "prints a warning about the lack of BASH_XTRACEFD" do
          allow(Bashcov).to receive(:bash_xtracefd?).and_return(false)
          allow(Bashcov).to receive(:mute).and_return(false)
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

    context "with skip_uncovered = true" do
      before do
        Bashcov.skip_uncovered = true
      end

      it "does not include uncovered files" do
        runner.run
        expect(runner.result.keys & uncovered_files).to be_empty
      end
    end

    context "with mute = true" do
      before do
        Bashcov.mute = true
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
