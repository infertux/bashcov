# frozen_string_literal: true

module Bashcov
  # Utility methods for loading the SimpleCov gem
  module SimpleCovLoader
    # Configure SimpleCov with low-precedence values
    # @yield [void] passes the provided block to +SimpleCov.configure+
    # @return [void]
    # @note any SimpleCov options configured here are liable to be overridden
    #   either by SimpleCov's own defaults (as defined in +simplecov/defaults+)
    #   or by user defaults in +.simplecov+
    # @note short-circuits without loading SimpleCov if no block was provided
    def preconfigure_simplecov
      return unless block_given?

      safe_load_simplecov!
      SimpleCov.configure(&Proc.new)
      load_simplecov!
    end

    # Executes a block with +ENV["SIMPLECOV_NO_DEFAULTS"]+ in effect
    # @yield [void] runs the provided block with +ENV["SIMPLECOV_NO_DEFAULTS"]+
    #   defined, then restores the unmodified +ENV+ at method return
    # @note short-circuits if no block was provided
    # @return [void]
    def simplecov_no_defaults
      return unless block_given?

      begin
        saved_env = ENV.to_hash
        ENV["SIMPLECOV_NO_DEFAULTS"] ||= "1"
        yield
      ensure
        ENV.replace(saved_env)
      end
    end

    # Loads SimpleCov with +ENV["SIMPLECOV_NO_DEFAULTS"] in effect
    # @return [void]
    def safe_load_simplecov!
      simplecov_no_defaults { load_simplecov! }
    end

    # Loads SimpleCov with Ruby interpreter warnings silenced
    # @return [void]
    def load_simplecov!
      saved_verbose, $VERBOSE = $VERBOSE, false
      load "simplecov.rb"
    ensure
      $VERBOSE = saved_verbose
    end
  end
end
