# frozen_string_literal: true

module Bashcov
  # Extensions for other libraries
  module Ext
    # Extensions for the SimpleCov Gem
    module SimpleCov
      refine ::SimpleCov.singleton_class do
        # Complain loudly if SimpleCov.result has been updated to accept an
        # argument, as this means the refinement is likely no longer needed
        # :nocov:
        if $VERBOSE && !::SimpleCov.method(:result).arity.zero?
          name = Module.nesting.first.name
          warn "SimpleCov.result now accepts arguments; consider removing the #{name} refinement"
        end
        # :nocov:

        # Override +SimpleCov.result+ to permit storing our own result
        # @param [SimpleCov::Result, nil] coverage run result to store and
        #   (when non-+nil+) returned by future calls to the +SimpleCov.result+
        #   reader method
        def result(result = nil)
          @result = result unless result.nil?

          # *Always* call super, as SimpleCov.result is defined with an ensure
          # clause that we don't want to suppress.  Explicitly pass an empty
          # argument list to avoid triggering an ArgumentError.
          super()
        end
      end
    end
  end
end
