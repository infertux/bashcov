require 'spec_helper'
require 'benchmark'

describe Bashcov::Runner do
  let(:runner) { Bashcov::Runner.new test_suite }
  let(:bash_files_glob) { "#{Bashcov.root_directory}/**/*.sh" }

  describe "#run" do
    it "finds commands in $PATH" do
      Bashcov::Runner.new('ls -l').run.should be_success
    end

    it "is less than 3 times slower with Bashcov" do
      ratio = 0

      3.times do |iteration|
        t0 = Benchmark.realtime { %x[#{test_suite} 2>&1] }
        $?.should be_success

        run = nil
        t1 = Benchmark.realtime { run = Bashcov::Runner.new(test_suite).run }
        run.should be_success

        ratio = (ratio * iteration + t1 / t0) / (iteration + 1)
      end

      puts "#{ratio} times longer with Bashcov"
      ratio.should be < 3
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

  describe "#find_bash_files" do
    let(:files) { runner.find_bash_files bash_files_glob }
    subject { files }

    it { should be_a Hash }

    it "contains bash files" do
      subject.keys.should =~ bash_files
    end

    it "marks files as uncovered" do
      subject.values.each do |lines|
        lines.each { |line| line.should == Bashcov::Line::UNCOVERED }
      end
    end
  end

  describe "#add_coverage_result" do
    let(:files) {
      runner.run
      files = runner.find_bash_files bash_files_glob
      runner.add_coverage_result files
    }
    subject { files }

    it { should be_a Hash }

    it "contains all files" do
      subject.keys.should =~ bash_files | executed_files
    end

    it "adds correct coverage results" do
      subject.each do |file, lines|
        lines.each_with_index do |line, lineno|
          [
            Bashcov::Line::UNCOVERED,
            expected_coverage[file][lineno]
          ].should include line
        end
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

