require 'spec_helper'

describe Bashcov::Lexer do
  describe "#irrelevant_lines" do
    [
      ['simple.sh', [0, 1, 2, 3, 6, 8, 9, 11, 12]],
      ['function.sh', [0, 1, 2, 4, 5, 6, 9, 10, 13]],
      ['sourced.txt', [0, 1, 3]]

    ].each do |filename, lines|
      context "for #{filename}" do
        it "returns irrelevant lines" do
          lexer = Bashcov::Lexer.new File.join(scripts, filename)
          lexer.irrelevant_lines.should =~ lines
        end
      end
    end
  end
end

