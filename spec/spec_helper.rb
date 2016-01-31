unless RUBY_ENGINE == "rbx" # coverage support is broken on rbx
  require "simplecov"
  require "coveralls"

  formatters = [SimpleCov::Formatter::HTMLFormatter, Coveralls::SimpleCov::Formatter]
  SimpleCov.formatter = SimpleCov::Formatter::MultiFormatter.new(formatters)
  SimpleCov.start do
    minimum_coverage 100
    add_group "Sources", "lib"
    add_group "Tests", "spec"
  end
end

require "bashcov"

Dir["#{File.dirname(__FILE__)}/support/**/*.rb"].each { |file| require file }

RSpec.configure do |config|
  config.before(:each) do
    # Reset the options to, among other things, pick up on a new working
    # directory.
    Bashcov.set_default_options!

    # Permit setting the path to Bash from the controlling environment
    unless (bash_path = ENV["BASHCOV_BASH_PATH"]).nil?
      Bashcov.bash_path = bash_path
    end

    Bashcov.mute = true # don't print testsuite output
  end
end
