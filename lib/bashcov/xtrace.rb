require "pathname"
require "securerandom"

module Bashcov
  # This class manages +xtrace+ output.
  #
  # @see Runner
  class Xtrace
    # [String] Character that will be used to indicate the nesting level of
    #   +xtrace+d instructions
    DEPTH_CHAR = "+"

    # [String] Prefix used in +PS4+ to identify relevant output
    PREFIX = "BASHCOV>"

    # [String] A token for delimiting the end of the PS4
    EOPS4 = SecureRandom.uuid

    # [String] +PS4+ variable used for xtrace output
    # @see http://www.gnu.org/software/bash/manual/bashref.html#index-PS4
    # @see http://stackoverflow.com/questions/59895/can-a-bash-script-tell-what-directory-its-stored-in
    # @note This means that files and directories whose names contain newlines
    #   won't be dealt with correctly.  They'll also muck up processing of
    #   further scripts, so {#run} raises an exception if a non-conforming
    #   script is detected.
    PS4 = %W(#{DEPTH_CHAR + PREFIX} ${BASH_SOURCE} ${PWD} ${OLDPWD} ${LINENO} #{EOPS4}).join($/) + $/

    # Regexp to match line start.  {DEPTH_CHAR} will be repeated in proportion
    # to the level of Bash call nesting.
    LINE_START_REGEXP = /\A#{Regexp.escape(DEPTH_CHAR)}+#{PREFIX}/

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
      lines = @read.each_line

      loop do
        # Reject all lines until we've seen the start of the PS4
        nil until lines.next =~ LINE_START_REGEXP

        # The next three lines will be $BASH_SOURCE, $PWD, $OLDPWD, and $LINENO
        bash_source, pwd, oldpwd, lineno = (1..4).map { lines.next.chomp }

        # @todo remove this
        # $stderr.puts "#=> #{bash_source} | #{pwd} | #{oldpwd} | #{lineno} | #{lines.peek}"

        unexpected_lines = []
        unexpected_lines << lines.next.chomp until lines.peek.chomp == EOPS4

        unless unexpected_lines.empty?
          raise "Illegal linebreak(s) detected in filename"
        end

        parse_hit!(*[bash_source, pwd, oldpwd].map { |p| Pathname.new(p) }, lineno.to_i - 1)
      end

      @files
      # :nocov: -- this is here in case the +lines+ iterator raises it on
      # +#next+.
    rescue StopIteration
      @files
    end
  # :nocov:

  private

    def parse_hit!(bash_source, pwd, oldpwd, lineno)
      # Tracks coverage for each file under test
      @files ||= {}

      update_wd_stacks!(pwd, oldpwd)

      script = find_script(bash_source)

      @files[script] ||= []
      @files[script][lineno] ||= 0
      @files[script][lineno] += 1
    rescue IndexError
      raise "#{script} => #{lineno}"
    end

    def find_script(bash_source)
      # Scan the $PWD stack in reverse on the assumption that more recent
      # entries are more plausible candidates for base directories from which
      # $BASH_SOURCE can be reached.
      script = @pwd_stack.reverse.map { |wd| wd + bash_source }.find(&:file?)
      script.nil? ? bash_source.cleanpath : script.realpath
    end

    def update_wd_stacks!(pwd, oldpwd)
      # Stacks for updating working directory changes
      @pwd_stack ||= []
      @oldpwd_stack ||= []
      @pwd_stack[0] ||= pwd
      @oldpwd_stack[0] ||= oldpwd unless oldpwd.to_s.empty?

      # We haven't changed working directories, so return
      return if pwd == @pwd_stack[-1]

      # A previous cd/pushd has been undone
      if pwd == @oldpwd_stack[-1] && oldpwd == @oldpwd_stack[-2]
        @pwd_stack.pop
        @oldpwd_stack.pop
      # New cd/pushd
      else
        @pwd_stack << pwd
        @oldpwd_stack << oldpwd
      end
    end
  end
end
