# frozen_string_literal: true

require "bundler/gem_tasks"

require "bundler/audit/task"
Bundler::Audit::Task.new

require "cucumber/rake/task"
Cucumber::Rake::Task.new do |t|
  t.cucumber_opts = %w[--publish-quiet --backtrace --verbose --order=random]
end

require "rspec/core/rake_task"
RSpec::Core::RakeTask.new(:rspec) do |t|
  t.ruby_opts = "-w"
end

require "rubocop/rake_task"
RuboCop::RakeTask.new

task default: %i[bundle:audit cucumber rspec rubocop]
