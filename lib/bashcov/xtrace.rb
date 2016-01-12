module Bashcov
  # This class manages +xtrace+ output.
  #
  # @see Runner
  class Xtrace
    # Prefix used for PS4.
    # @note The first caracter ('+') will be repeated to indicate the nesting
    #   level.
    PREFIX = "+BASHCOV> "

    # [String] +PS4+ variable used for xtrace output
    # @see http://www.gnu.org/software/bash/manual/bashref.html#index-PS4
    # @see http://stackoverflow.com/questions/59895/can-a-bash-script-tell-what-directory-its-stored-in
    # @note We use a forward slash as delimiter since it's the only forbidden
    #   character in filenames on Unix and Windows.
    GET_ABS_DIR = "$(cd $(dirname ${BASH_SOURCE[0]}); pwd)"
    GET_BASE = "$(basename ${BASH_SOURCE[0]})"
    PS4 = %(#{PREFIX}#{GET_ABS_DIR}/#{GET_BASE}/${LINENO}: )

    # Regexp to match xtrace elements.
    LINE_REGEXP = %r{\A#{Regexp.escape(PREFIX[0])}+#{PREFIX[1..-1]}(?<filename>.+)\/(?<lineno>\d+): }

    # Creates a pipe for xtrace output.
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
        line = File.readlines(filename)[lineno]
        ishere = line.match("cat.*<<-?\s*[\"']?\(.*\)[\"']?")
        next unless ishere
        lineno += 1
        line = File.readlines(filename)[lineno]
        until line.nil? || line.match("^\s*#{ishere[1]}")
          @files[filename][lineno] ||= 0
          @files[filename][lineno] += 1
          lineno += 1
          line = File.readlines(filename)[lineno]
        end
        unless line.nil?
          @files[filename][lineno] ||= 0
          @files[filename][lineno] += 1
        end
      end

      @files
    end
  end
end
