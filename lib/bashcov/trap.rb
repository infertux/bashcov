require "shellwords"
require "tempfile"

require "bashcov"

module Bashcov
  class Trap < SimpleDelegator
    class << self
      private :new
      def set(*args)
        new(*args)
      end
    end

    def initialize(name, delim, fd, fields)
      @delim = delim
      @fields = fields

      if block_given?
        Tempfile.open(name) do |tempfile|
          __setobj__(tempfile)
          write_trap_text(delim, fd, fields)
          yield self
        end
      else
        __setobj__(Tempfile.open(name))
        write_trap_text(delim, fd, fields)
        self
      end
    end

  private

    def write_trap_text(delim, fd, fields)
      write trap_text(delim, fd, fields)
      close
    end

    def trap_text(delim, fd, fields)
      printf_format = (["%s"] * fields.length).join(delim) + delim
      fields_format = (fields.map { |f| format '"%s"', f }).join(" ")
      redirect = fd == 1 ? "" : "1>&#{fd.to_i}"
      <<-EOF.gsub(/^\s+/, "")
        trap 'printf -- #{redirect} "#{printf_format}" #{fields_format}' DEBUG

        # Don't allow this to be unset!
        readonly BASH_ENV
        export BASH_ENV
      EOF
    end
  end
end
