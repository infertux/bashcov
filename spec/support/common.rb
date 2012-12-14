# Common helpers

def ignore_exception
  begin
    yield
  rescue Exception
    # silently ignore the exception
  end
end

