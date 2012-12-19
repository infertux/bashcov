require 'spec_helper'

shared_examples "a bash file" do
  describe "#irrelevant_lines" do
    it "returns irrelevant lines" do
      coverage = expected_coverage[filename]
      irrelevant_lines = 0.upto(coverage.size - 1).select do |idx|
        coverage[idx].nil?
      end

      lexer = Bashcov::Lexer.new filename
      lexer.irrelevant_lines.should =~ irrelevant_lines
    end
  end
end

describe Bashcov::Lexer do
  describe "#initialize" do
    it "raises if the file is invalid" do
      expect {
        Bashcov::Lexer.new 'inexistent_file.exe'
      }.to raise_error ArgumentError
    end
  end

  expected_coverage.keys.each do |filename|
    context filename do
      it_behaves_like "a bash file" do
        let(:filename) { filename }
      end
    end
  end
end

