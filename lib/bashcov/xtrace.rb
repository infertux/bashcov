require 'mkmf'

module Bashcov
  # This class manages +xtrace+ output.
  #
  # @see Runner
  class Xtrace
    # Prefix used for PS4.
    # @note The first caracter ('+') will be repeated to indicate the nesting
    #   level.
    PREFIX = '+BASHCOV> '

    # [String] +PS4+ variable used for xtrace output
    # @see http://www.gnu.org/software/bash/manual/bashref.html#index-PS4
    # @see http://stackoverflow.com/questions/59895/can-a-bash-script-tell-what-directory-its-stored-in
    # @note We use a forward slash as delimiter since it's the only forbidden
    #   character in filenames on Unix and Windows.
    _READLINK = find_executable('readlink')
    _GREADLINK = find_executable('greadlink')
    READLINK = _GREADLINK.nil? ? _READLINK : _GREADLINK
    PS4 = %Q{#{PREFIX}$(#{READLINK} -f ${BASH_SOURCE[0]})/${LINENO}: }

    # Regexp to match xtrace elements.
    LINE_REGEXP = /\A#{Regexp.escape(PREFIX[0])}+#{PREFIX[1..-1]}(?<filename>.+)\/(?<lineno>\d+): /

    # @return [Hash] Coverage of executed files
    attr_reader :coverage

    # Creates a temporary file for xtrace output.
    # @see http://stackoverflow.com/questions/6977561/pipe-vs-temporary-file
    def initialize
      @read, @write = IO.pipe
    end

    # @return [Fixnum] File descriptor of the write end of the pipe
    def file_descriptor
      @write.fileno
    end

    # Closes the pipe for writing.
    # @return [void]
    def close
      @write.close
    end

    # Parses xtrace output and computes coverage.
    # @return [Hash] Hash of executed files with coverage information
    def read
      @files = {}

      @read.each_line do |line|
        match = line.match(LINE_REGEXP)
        next if match.nil? # garbage line from multiline instruction

        filename = File.expand_path(match[:filename], Bashcov.root_directory)

        lineno = match[:lineno].to_i - 1
        @files[filename] ||= []
        @files[filename][lineno] ||= 0
        @files[filename][lineno] += 1
      end

      @files
    end
  end
end

