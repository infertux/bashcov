# frozen_string_literal: true

require_relative "lib/bashcov/version"

Gem::Specification.new do |spec|
  spec.name          = "bashcov"
  spec.version       = Bashcov::VERSION
  spec.authors       = ["Cédric Félizard"]
  spec.email         = ["cedric@felizard.fr"]

  spec.summary       = "Code coverage tool for Bash"
  spec.description   = "Code coverage tool for Bash"
  spec.homepage      = "https://github.com/infertux/bashcov"
  spec.license       = "MIT"

  spec.required_ruby_version = ">= 3.0.0"

  spec.metadata["homepage_uri"]          = spec.homepage
  spec.metadata["source_code_uri"]       = "https://github.com/infertux/bashcov"
  spec.metadata["changelog_uri"]         = "https://github.com/infertux/bashcov/blob/master/CHANGELOG.md"
  spec.metadata["rubygems_mfa_required"] = "true"

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  spec.files = Dir.chdir(__dir__) do
    git_ls_files_z = `git ls-files -z 2>/dev/null`

    # Handle contexts (like the Nix build sandbox) where we are not in a git
    # repository -- in such cases, include the entire current directory
    # hierarchy.
    files = $? == 0 ? git_ls_files_z.split("\x0") : Dir["**/*"]

    files.reject do |f|
      (File.expand_path(f) == __FILE__) || f.start_with?(*%w[test/ spec/ features/ .git])
    end
  end
  spec.executables   = spec.files.grep(%r{\Abin/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_dependency "simplecov", "~> 0.22.0"

  spec.add_development_dependency "aruba"
  spec.add_development_dependency "bundler-audit"
  spec.add_development_dependency "cucumber"
  spec.add_development_dependency "rake"
  spec.add_development_dependency "rspec"
  spec.add_development_dependency "rubocop"
  spec.add_development_dependency "rubocop-rake"
  spec.add_development_dependency "rubocop-rspec"
  spec.add_development_dependency "yard"
end
