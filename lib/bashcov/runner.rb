require 'open4'

module Bashcov
  class Runner
    attr_reader :stdout, :stderr

    def initialize filename
      @filename = File.expand_path(filename)
    end

    def run
      setup

      Open4::popen4(@command) do |pid, stdin, stdout, stderr|
        stdin = $stdin # bind stdin

        [ # we need threads here to stream output in realtime
          Thread.new { # stdout
            stdout.each do |line|
              $stdout.puts line unless Bashcov.mute?
              @stdout << line
            end
          },
          Thread.new { # stderr
            stderr.each do |line|
              unless Bashcov.mute?
                xtrace = Xtrace.new [line]
                $stderr.puts line if xtrace.xtrace_output.empty?
              end
              @stderr << line
            end
          }
        ].map(&:join)
      end
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
      xtraced_files = Xtrace.new(@stderr).files
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

