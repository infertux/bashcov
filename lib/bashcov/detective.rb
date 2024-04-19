# frozen_string_literal: true

require "set"

module Bashcov
  # Detect shell scripts
  class Detective
    # [Set<String>] Basenames of shell executables
    SHELL_BASENAMES = Set.new(%w[bash sh ash dash]).freeze

    # [Set<String>] Basenames of executables commonly used to +exec+ other
    #   processes, including shells
    OTHER_BASENAMES = Set.new(%w[env]).freeze

    # [Set<String>] Filename extensions commonly used for shell scripts
    SHELLSCRIPT_EXTENSIONS = Set.new(%w[.bash .sh]).freeze

    # Create an object that can be used for inferring whether a file is or is
    # not a shell script.
    # @param [String] bash_path path to a Bash interpreter
    def initialize(bash_path)
      @bash_path = bash_path
    end

    # Checks whether the provided file refers to a shell script by
    # determining whether the first line is a shebang that refers to a shell
    # executable, or whether the file has a shellscript extension and contains
    # valid shell syntax.
    # @param [String,Pathname] filename the name of the file to be checked
    # @return [Boolean] whether +filename+ refers to a shell script
    # @note returns +false+ when +filename+ is not readable, even if +filename+
    #   indeed refers to a shell script.
    def shellscript?(filename)
      return false unless File.exist?(filename) && File.readable?(filename) \
        && File.file?(File.realpath(filename))

      shellscript_shebang?(filename) ||
        (shellscript_extension?(filename) && shellscript_syntax?(filename))
    end

    # @param [String,Pathname] filename the name of the file to be checked
    # @return [Boolean] whether +filename+'s first line is a valid shell
    #   shebang
    # @note assumes that +filename+ is readable and refers to a regular file
    def shellscript_shebang?(filename)
      # Handle empty files that cause an immediate EOFError
      begin
        shebang = File.open(filename) { |f| f.readline.chomp }
      rescue EOFError
        return false
      end

      shellscript_shebang_line?(shebang)
    end

    # @param [String] shebang a line to test for shell shebang-itude
    # @return [Boolean] whether the line is a valid shell shebang
    def shellscript_shebang_line?(shebang)
      scanner = StringScanner.new(shebang)

      begin
        return false if scanner.scan(/#!\s*/).nil?

        shell = scanner.scan(/\S+/)

        return false if shell.nil?

        args = scanner.skip(/\s+/).nil? ? [] : scanner.rest.split(/\s+/)
      rescue ArgumentError
        # Handle "invalid byte sequence in UTF-8" from `StringScanner`.  Can
        # happen when trying to read binary data (e.g. .pngs).
        return false
      end

      shell_basename = File.basename(shell)

      SHELL_BASENAMES.include?(shell_basename) ||
        (OTHER_BASENAMES.include?(shell_basename) &&
          args.any? { |arg| SHELL_BASENAMES.include?(File.basename(arg)) })
    end

    # @param [String,Pathname] filename the name of the file to be checked
    # @return [Boolean] whether +filename+'s extension is a valid shellscript
    # extension
    def shellscript_extension?(filename)
      SHELLSCRIPT_EXTENSIONS.include? File.extname(filename)
    end

  private

    # @param [String,Pathname] filename the name of the file to be checked
    # @return [Boolean] whether +filename+'s text matches valid shell syntax
    # @note assumes that +filename+ is readable and refers to a regular file
    def shellscript_syntax?(filename)
      system(@bash_path, "-n", filename.to_s, in: :close, out: :close, err: :close)
      $?.success?
    end
  end
end
