require 'open3'

module Bashcov
  class Runner
    attr_reader :output

    def initialize filename
      @filename = File.expand_path(filename)
    end

    def run
      inject_shellopts_flags

      env = { 'PS4' => Xtrace.ps4 }
      stdin, stdout, stderr, wait_thr = Open3.popen3(env, @filename)
      stdin.close
      exit_status = wait_thr.value # block until process returns
      @output = stderr.dup
    end

    def result
      files = find_bash_files "#{Bashcov.root_directory}/**/*.sh"
      files = add_coverage_result files
      files = ignore_irrelevant_lines files
    end

    def find_bash_files directory
      files = {}

      # grab all bash files in project root and mark them uncovered
      (Dir[directory] - [@filename]).each do |file|
        absolute_path = File.expand_path(file)
        next unless File.file?(absolute_path)

        files[absolute_path] = Bashcov.coverage_array(absolute_path)
      end

      files
    end

    def add_coverage_result files
      xtraced_files = Xtrace.new(@output).files
      xtraced_files.delete @filename # drop the test suite file

      xtraced_files.each do |file, lines|
        lines.each_with_index do |line, lineno|
          files[file] ||= Bashcov.coverage_array(file) # non .sh files but executed though
          files[file][lineno] = line if line
        end
      end

      files
    end

    def ignore_irrelevant_lines files
      files.each do |filename, lines|
        lexer = Lexer.new(filename)
        lexer.irrelevant_lines.each do |lineno|
          files[filename][lineno] = Bashcov::Line::IGNORED
        end
      end
    end

  private

    def setup
      inject_xtrace_flag

      @stdout = []
      @stderr = []

      @command = "PS4='#{Xtrace.ps4}' #{@filename}"
    end

    def inject_xtrace_flag
      # SHELLOPTS must be exported so we use Ruby's ENV variable
      existing_flags = (ENV['SHELLOPTS'] || '').split(':')
      ENV['SHELLOPTS'] = (existing_flags | ['xtrace']).join(':')
    end
  end
end

