require "spec_helper"

RSpec::Matchers.define_negated_matcher :not_end_with, :end_with

describe Bashcov::FieldStream do
  include_context "delimited stream", 10

  describe "#each_field" do
    it "removes the field delimiter" do
      expect(stream.each_field(delim).to_a).to all(not_end_with(delim))
    end

    context "given a block" do
      it "yields each field in the stream" do
        expected = [start] + [String] * taken
        expect { |e| stream.each_field(delim, &e) }.to yield_successive_args(*expected)
      end
    end

    context "without a block" do
      it "returns an enumerator" do
        expect(stream.each_field(delim)).to be_an(Enumerator)
      end
    end
  end

  describe "#each" do
    context "given a block" do
      it "yields each field in the stream" do
        expected = [String] * taken
        expect { |e| stream.each(delim, field_count, start_match, &e) }.to \
          yield_successive_args(*expected)
      end
    end

    context "without a block" do
      it "returns an enumerator" do
        expect(stream.each(delim, field_count, start_match)).to be_an(Enumerator)
      end
    end

    context "with fewer than expected fields between start-of-fields matches" do
      let(:taken) { 5 }
      let(:empty_count) { field_count - taken }

      it "returns empty strings for the remaining fields" do
        expected = [String] * taken + [""] * empty_count
        expect { |e| stream.each(delim, field_count, start_match, &e) }.to \
          yield_successive_args(*expected)
      end
    end
  end
end
