require "spec_helper"

describe Bashcov::Lexer do
  describe "#initialize" do
    it "raises if the file is invalid" do
      expect do
        Bashcov::Lexer.new "inexistent_file.exe", nil
      end.to raise_error ArgumentError
    end
  end
end
