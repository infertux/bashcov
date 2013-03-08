require 'tempfile'

module Bashcov
  # This class manages +xtrace+ output.
  #
  # @see Runner
  class Xtrace
    # Creates a temporary file for xtrace output
    def initialize
      @xtrace_file = Tempfile.new 'xtrace_output'
      @xtrace_file.unlink # unlink on create so other programs cannot access it
    end

    # @return [Fixnum] File descriptor of the output file
    def file_descriptor
      @xtrace_file.fileno
    end

    # Parses xtrace output and computes coverage
    # @return [Hash] Hash of executed files with coverage information
    def files
      files = {}

      @xtrace_file.rewind
      @xtrace_file.read.each_line do |line|
        match = line.match(self.class.line_regexp)
        next if match.nil? # multiline instruction

        filename = File.expand_path(match[:filename], Bashcov.root_directory)
        next if File.directory? filename
        unless File.file? filename
          warn "Warning: #{filename} was executed but has been deleted since then - skipping it."
          next
        end

        lineno = match[:lineno].to_i - 1
        files[filename] ||= Bashcov.coverage_array(filename)
        files[filename][lineno] += 1
      end

      files
    end

    # @see http://www.gnu.org/software/bash/manual/bashref.html#index-PS4
    # @return [String] +PS4+ variable used for xtrace output
    def self.ps4
      # We use a forward slash as delimiter since it's the only forbidden
      # character in filenames on Unix and Windows.

      # http://stackoverflow.com/questions/59895/can-a-bash-script-tell-what-directory-its-stored-in
      %Q{#{prefix}$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")/${LINENO} BASHCOV: }
    end

  private

    def self.prefix
      # Note that the first caracter (+) will be repeated to indicate the
      # nesting level (see depth_character).
      '+BASHCOV> '
    end

    def self.depth_character
      Regexp.escape(prefix[0])
    end

    def self.line_regexp
      @line_regexp ||= /\A#{depth_character}+#{prefix[1..-1]}(?<filename>.+)\/(?<lineno>\d+) BASHCOV: /
    end
  end
end

