require "spec_helper"

shared_context "delimited stream" do |field_count, start = "START>"|
  let(:field_count) { field_count }
  let(:start) { start }
  let(:start_match) { /#{Regexp.escape(start)}$/ }
  let(:delim) { SecureRandom.uuid }
  let(:token_length) { 4 }
  let(:taken) { 10 }
  # @note +(taken + 1) * 2+ to account for the start-of-fields signifier and
  # for the delimiters -- i.e., if we want to yield 10 actual fields, we have
  # to take 22 from the generator because 10 of these will be +delim+ and
  # 2 will be +start+.
  let(:input) { generator.take((taken + 1) * 2).join }
  let(:read)  { StringIO.new(input).tap(&:close_write) }
  let(:stream) { Bashcov::FieldStream.new(read) }

  # Generate a series of fields delimited by +delim+
  let(:generator) do
    Enumerator.new do |y|
      b = true
      fields_yielded = 0

      loop do
        if b
          # << is higher-precedence than ternary operator
          y << (fields_yielded == 0 ? start : SecureRandom.base64(token_length))
          fields_yielded = fields_yielded == field_count + 1 ? 0 : fields_yielded + 1
        else
          y << delim
        end

        b ^= true
      end
    end
  end
end

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
