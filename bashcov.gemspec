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

  gem.files         = `git ls-files -z`.split("\x0").reject do |file|
    file.start_with?(".") || file.match(%r{\A(test|spec|features)/})
  end

  gem.executables   = gem.files.grep(%r{\Abin/}).map { |f| File.basename(f) }
  gem.require_paths = ["lib"]

  gem.required_ruby_version = ">= 2.3.0"

  gem.add_dependency "simplecov", "0.15.1"

  gem.add_development_dependency "aruba", "~> 0.14.3"
  gem.add_development_dependency "coveralls"
  gem.add_development_dependency "cucumber"
  gem.add_development_dependency "mutant-rspec"
  gem.add_development_dependency "rake"
  gem.add_development_dependency "rspec"
  gem.add_development_dependency "rubocop"
  gem.add_development_dependency "yard"
end
