module Bashcov
  # Module exposing information concerning the installed Bash version
  # @note methods do not cache results because {bash_path} can change at
  #   runtime
  module BashInfo
    # @return [Array<String>] An array representing the components of
    #   +BASH_VERSINFO+
    def bash_versinfo
      `#{bash_path} -c 'echo "${BASH_VERSINFO[@]}"'`.chomp.split
    end

    # @return [Boolean] Whether Bash supports +BASH_XTRACEFD+
    def bash_xtracefd?
      bash_versinfo[0..1].join.to_i >= 41
    end

    # @return [Boolean] Whether Bash supports a +PS4+ of greater than 128 bytes
    # @see https://tiswww.case.edu/php/chet/bash/CHANGES
    # @note Item +i.+ under the +bash-4.2-release+ to +bash-4.3-alpha+ change
    #   list notes that version 4.2 truncates +PS4+ if it is greater than 128
    #   bytes.
    def truncated_ps4?
      bash_versinfo[0..1].join.to_i <= 42
    end

    def bash_path
      "/bin/bash"
    end
  end
end
