# frozen_string_literal: true

# More info at https://github.com/guard/guard#readme

guard "rspec", cli: "--tag ~slow" do
  watch(%r{^spec/.+_spec\.rb$})
  watch(%r{^lib/(.+)\.rb$})        { |m| "spec/#{m[1]}_spec.rb" }
  watch(%r{^lib/(.+)/(.+)\.rb$})   { |m| "spec/#{m[1]}/#{m[2]}_spec.rb" }
  watch("spec/spec_helper.rb")     { "spec" }
  watch(%r{^spec/support/.+\.rb$}) { "spec" }
end
