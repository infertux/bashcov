module Bashcov
  # This class manages +xtrace+ output.
  #
  # @see Runner
  class Xtrace
    # @param [Array] output Array of output lines.
    # @raise [ArgumentError] if the given +output+ is not an array
    def initialize output
      raise ArgumentError "#{output} must be an array" unless output.is_a? Array
      @lines = output
    end

    # Filters out non-xtrace lines.
    # @return [Array] xtrace output
    def xtrace_output
      @lines.select { |line| line =~ Xtrace.line_regexp }
    end

    # Parses xtrace output and computes coverage
    # @raise [RuntimeError] on invalid files
    # @return [Hash] Hash of executed files with coverage information
    def files
      files = {}

      xtrace_output.each do |line|
        match = line.match(Xtrace.line_regexp)
        filename = File.expand_path(match[:filename], Bashcov.root_directory)
        next if File.directory? filename
        raise "#{filename} is not a file" unless File.file? filename

        lineno = match[:lineno].to_i
        lineno -= 1 if lineno > 0

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
      %Q{#{prefix}$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")/${LINENO} BASHCOV}
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
      /\A#{depth_character}+#{prefix[1..-1]}(?<filename>.+)\/(?<lineno>\d+) BASHCOV/
    end
  end
end

