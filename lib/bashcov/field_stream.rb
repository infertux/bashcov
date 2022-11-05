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

    # Yields fields extracted from an input stream
    # @param [String, nil] delimiter   the field separator
    # @param [Integer]     field_count the number of fields to extract
    # @param [Regexp]      start_match a +Regexp+ that, when matched against the
    #   input stream, signifies the beginning of the next series of fields to
    #   yield
    # @yieldparam [String] field each field extracted from the stream. If
    #   +start_match+ is matched with fewer than +field_count+ fields yielded
    #   since the last match, yields empty strings until +field_count+ is
    #   reached.
    def each(delimiter, field_count, start_match, &block)
      return enum_for(__method__, delimiter, field_count, start_match) unless block_given?

      chunked = each_field(delimiter).chunk(&chunk_matches(start_match))

      yield_fields = lambda do |(_, chunk)|
        chunk.each(&block)
        (field_count - chunk.size).times { yield "" }
      end

      # Skip junk that might appear before the first start-of-fields match
      begin
        n, chunk = chunked.next
        yield_fields.call([n, chunk]) unless n.zero?
      rescue StopIteration
        return
      end

      chunked.each(&yield_fields)
    end

  private

    # @param [Regexp] start_match a +Regexp+ that, when matched against the
    #   input stream, signifies the beginning of the next series of fields to
    #   yield
    # @return [Proc] a unary +Proc+ that returns +nil+ if the argument mathes
    #   the +start_match+ +Regexp+, and otherwise returns the number of
    #   start-of-fields signifiers so far encountered.
    # @example
    #   chunker = chunk_matches /<=>/
    #   chunked = %w[foo fighters <=> bar none <=> baz luhrmann].chunk(&chunker)
    #   chunked.to_a
    #     #=> [[0, ["foo", "fighters"]], [1, ["bar", "none"]], [2, ["baz", "luhrmann"]]]
    def chunk_matches(start_match)
      i = 0

      lambda do |e|
        if e.match?(start_match)
          i += 1
          nil
        else
          i
        end
      end
    end
  end
end
