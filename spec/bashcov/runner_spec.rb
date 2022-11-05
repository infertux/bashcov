# frozen_string_literal: true

require "spec_helper"
require "benchmark"

describe Bashcov::Runner do
  let(:runner) { described_class.new([Bashcov.bash_path, test_suite]) }

  around do |example|
    Dir.chdir File.dirname(test_suite) do
      example.run
    end
  end

  before do
    # SimpleCov uses a block-based filter to reject from the coverage results
    # any files that do not live under SimpleCov.root by matching filenames
    # against a regular expression containing the value of SimpleCov.root.
    # This regular expression is memoized during the first use of the filter in
    # question, and is not re-initialized if SimpleCov.root changes. By mocking
    # up an empty filter list, we ensure that no files are omitted from the
    # runner's coverage results because they don't live under whatever
    # directory happens to have been the value of SimpleCov.root at the time
    # the filter was first run.
    allow(SimpleCov).to receive(:filters).and_return([])
  end

  describe "#with_xtrace_flag" do
    context "without a SHELLOPTS variable" do
      before do
        ENV["SHELLOPTS"] = nil
      end

      it "adds the flags" do
        runner.send(:with_xtrace_flag) do
          expect(ENV.fetch("SHELLOPTS", nil)).to eq("xtrace")
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
          expect(ENV.fetch("SHELLOPTS", nil)).to eq("posix:xtrace")
        end
      end
    end
  end

  describe "#run" do
    it "finds commands in $PATH" do
      expect(described_class.new("ls -l").run).to be_success
    end

    it "is fast", :slow do
      ratio = 0

      3.times do |iteration|
        t0 = Benchmark.realtime do
          pid = Process.spawn test_suite, out: "/dev/null", err: "/dev/null"
          Process.wait pid
        end
        expect($?).to be_success

        run = nil
        t1 = Benchmark.realtime { run = described_class.new(test_suite).run }
        expect(run).to be_success

        ratio = ((ratio * iteration) + (t1 / t0)) / (iteration + 1)
      end

      puts "#{ratio} times slower with Bashcov"
      # XXX: no proper assertion - just outputs the ratio
    end

    context "with a script that unsets $LINENO" do
      include_context "with a temporary script", "unset_lineno" do
        # @note "with a temporary script" context expects +script_text+ to be defined.
        let(:script_text) do
          <<-BASH.gsub(/\A\s+/, "")
            #!/bin/bash

            echo "Hello, world!"
            LINENO= echo "What line is this?"
            echo "Hello? Is anyone there?"
          BASH
        end

        let(:unset_lineno_coverage) { [nil, nil, 1, 0, 0] }
      end

      it "prints an error message" do
        expect { tmprunner.run }.to output(/expected integer.*got.*""/).to_stderr
      end

      it "returns an incomplete coverage hash" do
        tmprunner.run
        expect(tmprunner.result[tmpscript.path]).to \
          match_array(unset_lineno_coverage)
      end
    end

    context "with a script whose path contains Xtrace.delimiter" do
      # @note Due to the way that RSpec orders evaluation of contexts,
      # examples, and example hooks, {Bashcov::Xtrace.delimiter} in:
      #   +include_context "with a temporary script", Bashcov::Xtrace.delimiter+
      # gets expanded prior to setting Bashcov.bash_path in +spec_helper.rb+,
      # which causes an inappropriate value for {Bashcov::Xtrace.delimiter} if the
      # default Bash (+/bin/bash+) does not suffer from the truncated +PS4+ bug
      # but the Bash keyed to the +BASHCOV_BASH_PATH+ environment variable
      # does. We therefore have to run the same code block here to ensure the
      # value is set properly at the time the temporary script is created.
      Bashcov.bash_path = ENV["BASHCOV_BASH_PATH"] unless ENV["BASHCOV_BASH_PATH"].nil?

      include_context "with a temporary script", Bashcov::Xtrace.delimiter do
        # @note "with a temporary script" context expects +script_text+ to be defined.
        let(:script_text) do
          <<~BASH
            #!/usr/bin/env bash

            echo "Oh no!"
          BASH
        end

        let(:bad_path_coverage) { [nil, nil, 0] }
      end

      it "indicates that no lines were executed" do
        tmprunner.run

        expect(tmprunner.result[tmpscript.path]).to \
          match_array(bad_path_coverage)
      end
    end

    context "with an empty script" do
      include_context "with a temporary script", "empty_script" do
        let(:script_text) { "" }
      end

      it "returns empty coverage results" do
        expect { tmprunner.run }.not_to raise_error
        expect(tmprunner.result).to include(tmpscript.path)
        expect(tmprunner.result[tmpscript.path]).to be_empty
      end
    end
  end

  describe "#result" do
    it "returns the expected coverage hash" do
      runner.run
      result = runner.result

      expect(result.count).to eq(expected_coverage.count), "expected coverage for #{expected_coverage.count} files, got #{result.count}"

      expected_coverage.each do |file, expected_hits|
        expect(result).to include(file), "#{file} expected coverage stats but got none"

        actual_hits = result[file]

        expect(actual_hits.count).to eq(expected_hits.count), "#{file} expected coverage for #{expected_hits.count} line(s), got #{actual_hits.count}"

        actual_hits.each_with_index do |actual_hit, lineno|
          expected = expected_hits.fetch(lineno)
          expect(actual_hit).to eq(expected), "#{file}:#{lineno.succ} expected #{expected.inspect}, got #{actual_hit.inspect}"
        end
      end

      expected_missing.each do |file|
        expect(result).not_to include(file), "#{file} should be absent from coverage stats but was not"
      end
    end

    context "with skip_uncovered = true" do
      before do
        Bashcov.skip_uncovered = true
      end

      it "does not include uncovered files" do
        runner.run
        expect(runner.result.keys & uncovered_files).to be_empty
      end

      context "when SimpleCov.tracked_files is defined" do
        it "includes matching files even if they are uncovered" do
          expect(SimpleCov).to receive(:tracked_files).at_least(:once).and_return(uncovered_files.first)
          runner.run
          expect(runner.result.keys & uncovered_files).to match_array(uncovered_files.first)
        end
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

    context "with SimpleCov filters in effect" do
      before do
        SimpleCov.configure do
          expected_omitted.each_key { |filter| add_filter(filter) }
        end
      end

      it "omits files matching one or more SimpleCov filters from the results hash" do
        runner.run
        result = runner.result
        expect(result.keys).to match_array((expected_coverage.keys - expected_omitted.values.flatten))
      end
    end
  end
end
