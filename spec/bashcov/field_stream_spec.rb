# frozen_string_literal: true

require "spec_helper"

RSpec::Matchers.define_negated_matcher :not_end_with, :end_with

describe Bashcov::FieldStream do
  include_context "delimited stream", 10

  describe "#each_field" do
    it "removes the field delimiter" do
      expect(stream.each_field(delimiter).to_a).to all(not_end_with(delimiter))
    end

    context "given a block" do
      it "yields each field in the stream" do
        expected = [start] + [String] * taken
        expect { |e| stream.each_field(delimiter, &e) }.to yield_successive_args(*expected)
      end
    end

    context "without a block" do
      it "returns an enumerator" do
        expect(stream.each_field(delimiter)).to be_an(Enumerator)
      end
    end
  end

  describe "#each" do
    context "given a block" do
      it "yields each field in the stream" do
        expected = [String] * taken
        expect { |e| stream.each(delimiter, field_count, start_match, &e) }.to \
          yield_successive_args(*expected)
      end
    end

    context "without a block" do
      it "returns an enumerator" do
        expect(stream.each(delimiter, field_count, start_match)).to be_an(Enumerator)
      end
    end

    context "with fewer than expected fields between start-of-fields matches" do
      let(:taken) { 5 }
      let(:empty_count) { field_count - taken }

      it "returns empty strings for the remaining fields" do
        expected = [String] * taken + [""] * empty_count
        expect { |e| stream.each(delimiter, field_count, start_match, &e) }.to \
          yield_successive_args(*expected)
      end
    end

    context "when the stream is empty or already fully consumed" do
      let(:read) { StringIO.new }

      it "short-circuits without yielding anything" do
        expect { |e| stream.each(delimiter, field_count, start_match, &e) }.not_to yield_control
      end
    end

    context "when stream contains fields prior to the first start-of-fields match" do
      let(:before_start) { %w[some junk data] }
      let(:after_start)  { %w[the good stuff] }
      let(:field_count)  { 3 }
      let(:input)        { (before_start + [start] + after_start).join(delimiter) }

      it "discards them" do
        expect { |e| stream.each(delimiter, field_count, start_match, &e) }.to \
          yield_successive_args(*after_start)
      end
    end
  end
end
