# frozen_string_literal: true

require "spec_helper"

describe Bashcov::Lexer do
  describe "#initialize" do
    it "raises if the file is invalid" do
      expect do
        described_class.new "inexistent_file.exe", nil
      end.to raise_error ArgumentError
    end
  end

  describe "#complete_coverage" do
    it "marks relevant lines" do
      file = "#{test_app}/scripts/nested/simple.sh"
      coverage = {}
      expected = expected_coverage.fetch(file).each_with_index.map do |line, index|
        index unless line.nil?
      end.compact

      described_class.new(file, coverage).complete_coverage

      expect(coverage.keys).to match_array expected
    end
  end
end
