# Common helpers

def ignore_exception(exception)
  yield
rescue exception
  nil
end

class Object
  # Redefines a constant without that pesky warning.
  #
  # @param [Constant] const a constant value
  # @param            val   the desired value for +const+
  # @return                 the new value of +const+
  def const_redefine(const, val)
    remove_const(const) if const_defined?(const)
    const_set(const, val)
  end
end
