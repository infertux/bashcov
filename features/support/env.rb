# frozen_string_literal: true

require "aruba/cucumber"

Aruba.configure do |config|
  config.log_level         = :debug
  config.exit_timeout      = 0.5
  config.startup_wait_time = 1
end
