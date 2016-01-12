require "pathname"

module Bashcov
  # This class manages +xtrace+ output.
  #
  # @see Runner
  class Xtrace
    # Prefix used for PS4.
    # @note The first character ('+') will be repeated to indicate the nesting
    #   level.
    PREFIX = "+BASHCOV> "

    # [String] +PS4+ variable used for xtrace output
    # @see http://www.gnu.org/software/bash/manual/bashref.html#index-PS4
    # @see http://stackoverflow.com/questions/59895/can-a-bash-script-tell-what-directory-its-stored-in
    # @note We use a forward slash as delimiter since it's the only forbidden
    #   character in filenames on Unix and Windows.
    PS4 = %(#{PREFIX}${BASH_SOURCE}/${LINENO}: )

    # Regexp to match xtrace elements.
    LINE_REGEXP = %r{\A#{Regexp.escape(PREFIX[0])}+#{PREFIX[1..-1]}(?<filename>.+)\/(?<lineno>\d+): }

    # Cleans redundant slashes and dots and attempts to expand symlinks in a
    # given path.
    # @param  [#to_s]   path  File path to clean and expand
    # @return [String]        +path+, with symlinks (hopefully) expanded
    # @note Falls back to calling {Pathname#cleanpath} on {Errno::ENOENT}.
    #   This is necessary for cases like process substitution, when the file
    #   won't actually exist on disk.
    def self.realpath(path)
      pathname = Pathname.new(path)
      pathname.realpath.to_s
    rescue Errno::ENOENT
      pathname.cleanpath(true).to_s
    end

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

        filename = realpath(File.expand_path(match[:filename], Bashcov.root_directory))

        lineno = match[:lineno].to_i - 1
        @files[filename] ||= []
        @files[filename][lineno] ||= 0
        @files[filename][lineno] += 1
      end

      @files
    end

  private

    # Implements simple caching of path expansion results to avoid having to
    # perform the expansion for each line in a given file.
    # @see realpath
    def realpath(path)
      @path_cache ||= {}
      @path_cache[path] ||= self.class.realpath(path)
    end
  end
end
