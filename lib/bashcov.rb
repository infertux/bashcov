require "bashcov/version"
require "bashcov/lexer"
require "bashcov/line"
require "bashcov/runner"
require "bashcov/xtrace"

module Bashcov
  class << self
    def root_directory
      Dir.getwd
    end

    def coverage_array(filename, fill = Line::UNCOVERED)
      lines = File.readlines(filename).size
      [fill] * lines
    end

    def link
      %Q|<a href="https://github.com/infertux/bashcov">bashcov</a> v#{VERSION}|
    end
  end
end
