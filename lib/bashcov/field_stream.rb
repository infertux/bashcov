# frozen_string_literal: true

module Bashcov
  # Classes for streaming token-delimited fields
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

    # Yields fields extracted from a input stream
    # @param [String, nil] delimiter   the field separator
    # @param [Integer]     field_count the number of fields to extract
    # @param [Regexp]      start_match a +Regexp+ that, when matched against the
    #   input stream, signifies the beginning of the next series of fields to
    #   yield
    # @yieldparam [String] field each field extracted from the stream. If
    #   +start_match+ is matched with fewer than +field_count+ fields yielded
    #   since the last match, yields empty strings until +field_count+ is
    #   reached.
    def each(delimiter, field_count, start_match)
      return enum_for(__method__, delimiter, field_count, start_match) unless block_given?

      # The number of fields processed since passing the last start-of-fields
      # match
      seen_fields = 0

      fields = each_field(delimiter)

      # Close over +field_count+ and +seen_fields+ to yield empty strings to
      # the caller when we've already hit the next start-of-fields match
      yield_remaining = -> { (field_count - seen_fields).times { yield "" } }

      # Advance until the first start-of-fields match
      loop { break if fields.next =~ start_match }

      fields.each do |field|
        # If the current field is the start-of-fields match...
        if field =~ start_match
          # Fill out any remaining (unparseable) fields with empty strings
          yield_remaining.call

          seen_fields = 0
        elsif seen_fields < field_count
          yield field
          seen_fields += 1
        end
      end

      # One last filling-out of empty fields if we're at the end of the stream
      yield_remaining.call

      read.close unless read.closed?
    end
  end
end
