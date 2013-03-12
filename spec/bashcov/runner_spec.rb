require 'spec_helper'
require 'benchmark'

describe Bashcov::Runner do
  let(:runner) { Bashcov::Runner.new test_suite }

  before do
    # 'Bashcov.options.command' is normally set through 'Bashcov.parse_options!'
    # so we need to stub it
    Bashcov.options.stub(:command).and_return(test_suite)
  end

  describe "#run" do
    it "finds commands in $PATH" do
      Bashcov::Runner.new('ls -l').run.should be_success
    end

    it "is fast", speed: :slow do
      # XXX it's usually 2 to 3 times slower but can be up to 6 on Travis boxes
      # - not sure why :(
      ratio = 0

      3.times do |iteration|
        t0 = Benchmark.realtime {
          pid = Process.spawn test_suite, out: '/dev/null', err: '/dev/null'
          Process.wait pid
        }
        $?.should be_success

        run = nil
        t1 = Benchmark.realtime { run = Bashcov::Runner.new(test_suite).run }
        run.should be_success

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
        ENV['SHELLOPTS'].should == 'xtrace'
      end
    end

    context "with an existing SHELLOPTS variable" do
      before do
        ENV['SHELLOPTS'] = 'posix'
      end

      it "merges the flags" do
        runner.run
        ENV['SHELLOPTS'].should == 'posix:xtrace'
      end
    end
  end

  describe "#result" do
    it "returns a valid coverage hash" do
      runner.run

      runner.result.should == expected_coverage
    end

    context "with options.skip_uncovered = true" do
      before do
        Bashcov.options.skip_uncovered = true
      end

      it "does not include uncovered files" do
        runner.run
        (runner.result.keys & uncovered_files).should be_empty
      end
    end

    context "with options.mute = true" do
      before do
        Bashcov.options.mute = true
      end

      it "does not print the command output" do
        [$stdout, $stderr].each do |io|
          io.should_not_receive :write
        end

        runner.run
      end
    end
  end
end

