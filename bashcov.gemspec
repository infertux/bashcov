# frozen_string_literal: true

require_relative "lib/bashcov/version"

Gem::Specification.new do |spec|
  spec.name          = "bashcov"
  spec.version       = Bashcov::VERSION
  spec.authors       = ["Cédric Félizard"]
  spec.email         = ["cedric@felizard.fr"]

  spec.summary       = spec.description
  spec.description   = "Code coverage tool for Bash"
  spec.homepage      = "https://github.com/infertux/bashcov"
  spec.license       = "MIT"
  spec.required_ruby_version = ">= 3.0.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/infertux/bashcov"
  spec.metadata["changelog_uri"] = "https://github.com/infertux/bashcov/blob/master/CHANGELOG.md"

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  spec.files = Dir.chdir(File.expand_path(__dir__)) do
    `git ls-files -z`.split("\x0").reject { |f| f.match(%r{\A(?:test|spec|features)/}) }
  end
  spec.bindir        = "exe"
  spec.executables   = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_dependency "simplecov", "~> 0.21.2"

  spec.add_development_dependency "aruba"
  spec.add_development_dependency "bundler-audit"
  # spec.add_development_dependency "coveralls"
  spec.add_development_dependency "cucumber"
  spec.add_development_dependency "rake"
  spec.add_development_dependency "rspec"
  spec.add_development_dependency "rubocop"
  spec.add_development_dependency "rubocop-rake"
  spec.add_development_dependency "rubocop-rspec"
  spec.add_development_dependency "yard"
  spec.metadata["rubygems_mfa_required"] = "true"
end
