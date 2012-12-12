module Bashcov
  class Xtrace
    def initialize output
      @output = output
    end

    def files
      files = {}

      @output.readlines.each do |line|
        next unless match = line.match(Xtrace.line_regexp)

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

