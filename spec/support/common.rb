# frozen_string_literal: true

# Common helpers

def ignore_exception(exception)
  yield
rescue exception # rubocop:disable Naming/RescuedExceptionsVariableName
  nil
end
