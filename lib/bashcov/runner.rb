require 'open3'

module Bashcov
  class Runner
    attr_reader :output

    def initialize filename
      @filename = File.expand_path(filename)
    end

    def run
      # SHELLOPTS must be exported so we use Ruby's ENV variable
      ENV['SHELLOPTS'] = 'braceexpand:hashall:interactive-comments:posix:verbose:xtrace' # FIXME gross

      command = "PS4='#{Xtrace.ps4}' #{@filename}"
      _, _, @output = Open3.popen3(command)
    end

    def result
      # FIXME complex method - split me

      # 1. Grab all bash files in project root and mark them uncovered
      @files = find_bash_files

      # 2. Add coverage information from run
      xtraced_files = Xtrace.new(@output).files
      xtraced_files.each do |file, lines|
        next if file == @filename
        lines.each_with_index do |line, index|
          @files[file] ||= Bashcov.coverage_array(file) # non .sh files but executed though
          @files[file][index] = line if line
        end
      end

      # 3. Ignore irrelevant lines
      @files.each do |filename, lines|
        warn filename unless File.file?(filename)
        next unless File.file?(filename)
        lexer = Lexer.new(filename)
        lexer.irrelevant_lines.each do |lineno|
          @files[filename][lineno] = Bashcov::Line::IGNORED
        end
      end
    end

    def find_bash_files
      files = {}

      (Dir["#{Bashcov.root_directory}/**/*.sh"] - [@filename]).each do |file|
        absolute_path = File.expand_path(file)
        next unless File.file?(absolute_path)

        files[absolute_path] = Bashcov.coverage_array(absolute_path)
      end

      files
    end

  end
end
