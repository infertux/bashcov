# frozen_string_literal: true

require "aruba/api"
require "json"
require "simplecov"

# Convenience methods for use in step definitions
module StepHelpers
  include Aruba::Api

  def aruba_setting(setting_name)
    Aruba.configure { |config| return config.public_send(setting_name) }
  end

  def aruba_working_directory_expanded
    File.expand_path(aruba_setting(:working_directory), aruba_setting(:root_directory))
  end

  def simplecov_results_json
    run_simple(<<-'COMMAND')
      ruby -rjson -rsimplecov -e '
        SimpleCov.at_exit { } # noop to prevent output other than the desired JSON
        print SimpleCov::ResultMerger.results.map(&:to_hash).to_json
      '
    COMMAND

    last_command_started.stdout
  end

  def simplecov_results_from_json(doc)
    JSON.parse(doc).map { |raw| SimpleCov::Result.from_hash(raw) }
  end

  def simplecov_results
    simplecov_results_from_json(simplecov_results_json)
  end

  def simplecov_merged_result
    SimpleCov::ResultMerger.merge_results(*simplecov_results)
  end
end

World(StepHelpers)

Given(/^SimpleCov is configured(?: in ("[^"]"))? with:$/) do |config_dir, config_body|
  simplecov_config_path = File.join(*[config_dir, ".simplecov"].compact.reject(&:empty?))

  steps %(
    Given a file named "#{simplecov_config_path}" with:
      """
      #{config_body}
      """
    Then the file "#{simplecov_config_path}" should exist
  )
end

When(/I run the following commands with bashcov(?: using `([^`]+)`)?:$/) do |options, commands|
  unless (options ||= "--root .").include? "--root"
    options << " --root ."
  end

  steps %(
    When I run the following commands:
      """
      #{commands.each_line.map { |command| "bashcov #{options} -- #{command}" }.join("\n")}
      """
  )
end

Then(/^the results should contain the commands:$/) do |table|
  results = simplecov_results
  commands = table.raw.flatten
  expect(results.map(&:command_name)).to include(*commands)
end

Then(/^the file "([^"]*)" should have the following coverage:/) do |filename, table|
  filename = File.expand_path(filename, aruba_working_directory_expanded)

  merged_result = simplecov_merged_result
  original_result = merged_result.original_result

  expect(original_result).to include(filename), %(coverage includes results for "#{filename}")

  file_coverage = original_result[filename]

  table.raw.each do |line_number, coverage|
    line_number = line_number.to_i

    coverage = coverage == "nil" ? nil : coverage.to_i

    expect(file_coverage[line_number - 1]).to(
      eq(coverage),
      %(line #{line_number} of "#{filename}" has coverage `#{coverage}`)
    )
  end
end
