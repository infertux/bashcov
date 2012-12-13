require 'spec_helper'

shared_examples "a bash file" do
  describe "#irrelevant_lines" do
    it "returns irrelevant lines" do
      lexer = Bashcov::Lexer.new File.join(scripts, filename)
      lexer.irrelevant_lines.should =~ irrelevant_lines
    end
  end
end

describe Bashcov::Lexer do
  it_behaves_like "a bash file" do
    let(:filename) { 'simple.sh' }
    let(:irrelevant_lines) { [0, 1, 2, 3, 6, 8, 9, 11, 12] }
  end

  it_behaves_like "a bash file" do
    let(:filename) { 'function.sh' }
    let(:irrelevant_lines) { [0, 1, 2, 4, 5, 6, 9, 10, 13] }
  end

  it_behaves_like "a bash file" do
    let(:filename) { 'sourced.txt' }
    let(:irrelevant_lines) { [0, 1, 3] }
  end
end

