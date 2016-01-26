require "bashcov"

module Bashcov
  module FieldStream
    class Base
      attr_accessor :read

      # Create an
      def initialize(read=nil)
        @read = read
      end

      def each(*args)
        raise NoMethodError, "you need to define ##{__method__}"
      end

      def each_line(delim)
        return enum_for(__method__, delim) unless block_given?

        @read.each_line(delim) do |line|
          yield line.chomp(delim)
        end
      end
    end

    class Truncated < Base
      def each(delim, field_count, start_match)
        return enum_for(__method__, delim, field_count, start_match) unless block_given?

        # To account for the presence of a token matching +start_match+ in the
        # stream.
        field_count += 1

        lines = each_line(delim)

        # Advance to first matching token
        nil until lines.next =~ start_match

        seen_fields = 1

        loop do
          have_start_match = lines.peek =~ start_match

          if seen_fields == field_count
            # Drop this field -- it either the start-of-fields match or something
            # else we don't care about.
            lines.next

            # Reset the field counter only if we've seen the start of the
            # fields; otherwise ignore this line.
            next unless have_start_match
            seen_fields = 0
          else
            # If we've seen the start-of-fields match but haven't yet yielded all
            # fields, yield an empty string.
            yield have_start_match ? "" : lines.next
          end

          seen_fields += 1
        end

        @read.close
      end
    end

    class Unlimited < Base
      def each(delim, field_count, start_match)
        return enum_for(__method__, delim, field_count, start_match) unless block_given?

        lines = each_line(delim)

        loop do
          # Skip fields until we have a match
          nil until lines.next =~ start_match

          field_count.times { yield lines.next }
        end

        @read.close
      end
    end
  end
end
