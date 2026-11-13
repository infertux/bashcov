# frozen_string_literal: true

module Bashcov
  # Class for streaming token-delimited fields
  class FieldStream
    attr_accessor :read

    # @param [IO] read an IO object opened for reading
    def initialize(read = nil)
      @read = read
    end

    # A convenience wrapper around +each_line(delimiter)+ that also does
    # +chomp(delimiter)+ on the yielded line.
    # @param [String, nil] delimiter the field separator for the stream
    # @return [void]
    # @yieldparam [String] field each +chomp+ed line
    def each_field(delimiter)
      return enum_for(__method__, delimiter) unless block_given?

      read.each_line(delimiter) do |line|
        yield line.chomp(delimiter).encode("utf-8", invalid: :replace)
      end
    end

    # Yields fields extracted from an input stream
    # @param [String, nil] delimiter   the field separator
    # @param [Integer]     field_count the number of fields to extract
    # @param [Regexp]      start_match a +Regexp+ that, when matched against the
    #   input stream, signifies the beginning of the next series of fields to
    #   yield
    # @param [Boolean] following whether to also yield, after the fields of
    #   each series, the first line of the text which follows them, up to the
    #   next delimiter or +start_match+ match ("" if there is none)
    # @yieldparam [String] field each field extracted from the stream. Exactly
    #   +field_count+ fields (plus one with +following+) are yielded for each
    #   +start_match+ match followed by fields: if fewer fields follow the
    #   match, yields empty strings until +field_count+ is reached; if more
    #   follow (e.g. a traced command that contains the delimiter), the extra
    #   fields are dropped so the next series of fields stays aligned.
    def each(delimiter, field_count, start_match, following: false, &block)
      return enum_for(__method__, delimiter, field_count, start_match, following:) unless block_given?

      series = nil
      # +next_start+ is the field which starts the next series, +nil+ at the
      # end of the stream
      flush = lambda do |next_start|
        next if series.nil? || series.empty?

        fields = series.first(field_count)
        fields.each(&block)
        (field_count - fields.size).times { block.call("") }
        block.call(first_line(series[field_count] || next_start || "", start_match)) if following
      end

      # skip junk that might appear before the first start-of-fields match
      each_field(delimiter) do |field|
        if field.match?(start_match)
          flush.call(field)
          series = []
        elsif series
          series << field
        end
      end
      flush.call(nil)
    end

  private

    # @return [String] the first line of +field+, without the
    #   +start_match+ match which ends it
    def first_line(field, start_match)
      newline = field.index("\n")
      newline ? field[0, newline] : field.sub(start_match, "")
    end
  end
end
