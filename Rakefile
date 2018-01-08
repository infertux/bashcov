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

task default: %i[rubocop spec cucumber]
