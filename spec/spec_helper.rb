unless RUBY_ENGINE == 'rbx' # coverage support is broken on rbx
  require 'simplecov'
  SimpleCov.start do
    minimum_coverage 100
    add_group "Sources", "lib"
    add_group "Tests", "spec"
  end
end

require 'bashcov'

Dir["./spec/support/**/*.rb"].each { |file| require file }

RSpec.configure do |config|
  config.before(:each) do
    Bashcov.set_default_options!
    Bashcov.mute = true # don't print testsuite output
  end
end

