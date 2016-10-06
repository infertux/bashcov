# frozen_string_literal: true

lib = File.expand_path("../lib", __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require "bashcov/version"

Gem::Specification.new do |gem|
  gem.name          = "bashcov"
  gem.version       = Bashcov::VERSION
  gem.authors       = ["Cédric Félizard"]
  gem.email         = ["cedric@felizard.fr"]
  gem.description   = "Code coverage tool for Bash"
  gem.summary       = gem.description
  gem.homepage      = "https://github.com/infertux/bashcov"
  gem.license       = "MIT"

  gem.files         = `git ls-files -z`.split("\x0").reject { |f| f.start_with?(".") || f.match(%r{\A(test|spec|features)/}) }
  gem.executables   = gem.files.grep(%r{\Abin/}).map { |f| File.basename(f) }
  gem.require_paths = ["lib"]

  gem.required_ruby_version = ">= 2.2.5"

  gem.add_dependency "simplecov", "~> 0.11"

  gem.add_development_dependency "rake"
  gem.add_development_dependency "rspec"
  gem.add_development_dependency "guard-rspec"
  gem.add_development_dependency "rb-inotify"
  gem.add_development_dependency "cane"
  gem.add_development_dependency "rubocop"
  gem.add_development_dependency "yard"
  gem.add_development_dependency "coveralls"
end
