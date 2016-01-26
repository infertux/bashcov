require "bashcov"

module Bashcov
  class FieldStream
    def initialize(read)
      # Copy stream to StringIO so that we can seek back and forth
      # ...
      # Might be a bit slow
      @read = StringIO.new
      IO.copy_stream(read, @read)

      # No need for write stream
      @read.close_write
    end

    def each(read_bytes = 128, field_count = Xtrace::PS4.split(Xtrace::DELIM).length + 1)
      # Create enumerator
      return enum_for(__method__) unless block_given?

      # Seek to start of stream
      @read.seek(0, IO::SEEK_SET)

      loop do
        # Pull +read_bytes - bytes_read+ characters from the stream
        buffer = @read.read(read_bytes)

        # $stderr.puts("#=> Position(#{read_position}) | buffer(#{buffer}) | EOF(#{@read.eof?})")

        break if buffer.nil?

        # Split at delimiter, adding empty strings to fill in for any missing
        # fields.
        fields = buffer.split(Xtrace::DELIM, field_count)
        if (missing_field_count = field_count - fields.length)
          fields += [""].cycle(missing_field_count).to_a
        end

        $stderr.puts "#===> Yielding fields..."
        fields[0..(field_count - 2)].each do |field|
          $stderr.puts "#  => Field: #{field}"
          yield field
        end

        # Rewind to just before the ignored field
        bytes_consumed = fields[field_count..1].map(&:length).reduce(&:+)
        @read.seek(bytes_consumed - read_bytes, IO::SEEK_CUR)
      end

      @read.close
    end
  end
end
