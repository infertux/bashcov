unless RUBY_ENGINE == "rbx" # coverage support is broken on rbx
  require "simplecov"
  require "coveralls"

  SimpleCov.formatter = SimpleCov::Formatter::MultiFormatter[
    SimpleCov::Formatter::HTMLFormatter,
    Coveralls::SimpleCov::Formatter
  ]
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
    Bashcov.set_default_options!

    # Permit setting the path to Bash from the controlling environment
    unless (bash_path = ENV["BASHCOV_BASH_PATH"]).nil?
      Bashcov.bash_path = bash_path
    end

    Bashcov.mute = true # don't print testsuite output
  end
end
