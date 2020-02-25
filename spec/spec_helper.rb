# frozen_string_literal: true

require "simplecov"
require "coveralls"

formatters = [SimpleCov::Formatter::HTMLFormatter, Coveralls::SimpleCov::Formatter]
SimpleCov.formatter = SimpleCov::Formatter::MultiFormatter.new(formatters)

require "bashcov"

Dir["#{File.dirname(__FILE__)}/support/**/*.rb"].sort.each { |file| require file }

RSpec.configure do |config|
  config.filter_run_excluding :slow

  config.around(:each) do |example|
    # XXX: https://github.com/mbj/mutant#mutations-with-infinite-runtimes
    Timeout.timeout(1, &example)
  end

  config.before(:each) do
    # Reset the options to, among other things, pick up on a new working
    # directory.
    Bashcov.set_default_options!

    # Permit setting the path to Bash from the controlling environment
    Bashcov.bash_path = ENV["BASHCOV_BASH_PATH"] unless ENV["BASHCOV_BASH_PATH"].nil?

    Bashcov.mute = true # don't print testsuite output
  end
end

puts "BASH_VERSION=#{Bashcov::BASH_VERSION}"
