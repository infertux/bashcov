# frozen_string_literal: true

module Bashcov
  # Signals an error parsing Bash's debugging output.
  class XtraceError < ::RuntimeError
    # Will contain the coverages parsed prior to the error
    attr_reader :files

    # @param [#to_s]  message An error message
    # @param [Hash]   files   A hash containing coverage information
    def initialize(message, files)
      @files = files
      super(message)
    end
  end
end
