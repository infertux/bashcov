# frozen_string_literal: true

module Bashcov
  # Module exposing information concerning the installed Bash version
  # @note methods do not cache results because +bash_path+ can change at
  #   runtime
  # @note receiver is expected to implement +bash_path+
  module BashInfo
    # @return [Boolean] Whether Bash supports +BASH_XTRACEFD+
    def bash_xtracefd?
      BASH_VERSION >= "4.1"
    end

    # @param [Integer] length the number of bytes to test; default 128
    # @return [Boolean] whether Bash supports a +PS4+ of at least a given
    #   number of bytes
    # @see https://tiswww.case.edu/php/chet/bash/CHANGES
    # @note Item +i.+ under the +bash-4.2-release+ to +bash-4.3-alpha+ change
    #   list notes that version 4.2 truncates +PS4+ if it is greater than 128
    #   bytes.
    def truncated_ps4?(length = 128)
      ps4 = SecureRandom.base64(length)
      !`PS4=#{ps4} #{bash_path} 2>&1 1>&- -xc 'echo hello'`.start_with?(ps4)
    end
  end
end
