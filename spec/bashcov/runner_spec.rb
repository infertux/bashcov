require 'spec_helper'
require 'benchmark'

describe Bashcov::Runner do
  suite = test_suite
  let(:runner) { Bashcov::Runner.new "bash #{suite}" }

  before :all do
    Dir.chdir File.dirname(test_suite)
  end

  describe "#run" do
    it "finds commands in $PATH" do
      expect(Bashcov::Runner.new('ls -l').run).to be_success
    end

    it "is fast", speed: :slow do
      ratio = 0

      3.times do |iteration|
        t0 = Benchmark.realtime {
          pid = Process.spawn test_suite, out: '/dev/null', err: '/dev/null'
          Process.wait pid
        }
        expect($?).to be_success

        run = nil
        t1 = Benchmark.realtime { run = Bashcov::Runner.new(test_suite).run }
        expect(run).to be_success

        ratio = (ratio * iteration + t1 / t0) / (iteration + 1)
      end

      puts "#{ratio} times longer with Bashcov"
      # XXX no proper assertion - just outputs the ratio
    end

    context "without a SHELLOPTS variable" do
      before do
        ENV['SHELLOPTS'] = nil
      end

      it "adds the flags" do
        runner.run
        expect(ENV['SHELLOPTS']).to eq('xtrace')
      end
    end

    context "with an existing SHELLOPTS variable" do
      before do
        ENV['SHELLOPTS'] = 'posix'
      end

      it "merges the flags" do
        runner.run
        expect(ENV['SHELLOPTS']).to eq('posix:xtrace')
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

