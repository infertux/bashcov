require "bashcov"

module Bashcov
  # Classes for streaming token-delimited fields
  module FieldStream
    # Base class for interfaces streaming token-delimited fields
    class Base
      attr_accessor :read

      # @param [IO] read an IO object opened for reading
      def initialize(read = nil)
        @read = read
      end

      # Yield a series of fields extracted from an +IO+ stream
      # @note to be implemented by child classes
      def each(*args)
        raise NoMethodError, "you need to define ##{__method__}"
      end

      # A convenience wrapper around +each_line(sep)+ that also does
      # +chomp(sep)+ on the yielded line.
      # @param [String, nil] delim the field separator for the stream
      # @return [void]
      # @yieldparam [String] field each +chomp+ed line
      def each_field(delim)
        return enum_for(__method__, delim) unless block_given?

        @read.each_line(delim) do |line|
          yield line.chomp(delim)
        end
      end
    end

    # Class for handling Bash 4.2 limited-length PS4 output
    class Truncated < Base
      # Yields fields extracted from a input stream
      # @param [String, nil] delim   the field separator
      # @param [Integer] field_count the number of fields to extract
      # @param [Regexp] start_match  a +Regexp+ that, when matched against the
      #   input stream, signifies the beginning of the next series of fields to
      #   yield
      # @yieldparam [String] field each field extracted from the stream.  If
      #   +start_match+ is matched with fewer than +field_count+ fields yielded
      #   since the last match, yields empty strings until +field_count+ is
      #   reached.
      def each(delim, field_count, start_match)
        return enum_for(__method__, delim, field_count, start_match) unless block_given?

        # Whether the current field is the start-of-fields match
        matched_start = nil

        # The number of fields processed since passing the last start-of-fields
        # match
        seen_fields = 0

        fields = each_field(delim)

        # Advance until the first start-of-fields match
        loop { break if fields.next =~ start_match }

        fields.each do |field|
          # If the current field is the start-of-fields match...
          if field =~ start_match
            # Fill out any remaining (unparseable) fields with empty strings
            (field_count - seen_fields).times { yield "" }

            matched_start = nil
            seen_fields = 0
          else
            if seen_fields < field_count
              yield field
              seen_fields += 1
            end
          end
        end

        @read.close unless @read.closed?
      end
    end

    # Class for handling Bash versions that don't suffer from the PS4
    # truncation bug
    class Unlimited < Base
      # (see Truncated#each)
      def each(delim, field_count, start_match)
        return enum_for(__method__, delim, field_count, start_match) unless block_given?

        fields = each_field(delim)

        loop do
          # Skip fields until we have a match
          nil until fields.next =~ start_match

          field_count.times { yield fields.next }
        end

        @read.close unless @read.closed?
      end
    end
  end
end
