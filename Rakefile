# frozen_string_literal: true

require "bundler/gem_tasks"

require "cucumber/rake/task"
Cucumber::Rake::Task.new

require "rspec/core/rake_task"
RSpec::Core::RakeTask.new(:spec) do |t|
  t.ruby_opts = "-w"
end

require "rubocop/rake_task"
RuboCop::RakeTask.new

require "bundler/audit/task"
Bundler::Audit::Task.new

task default: %i[bundle:audit rubocop spec cucumber]
