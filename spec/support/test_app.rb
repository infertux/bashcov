def test_app
  File.expand_path("../../test_app", __FILE__)
end

def scripts
  "#{test_app}/scripts"
end

def test_suite
  "#{test_app}/test_suite.sh"
end

def executed_files
  bash_files + ["#{scripts}/sourced.txt"] - ["#{test_app}/never_called.sh"]
end

def bash_files
  files_in("#{test_app}/**/*.sh")
end

def all_files
  files_in("#{test_app}/**/*")
end

def files_in directory
  Dir[directory].select { |file| File.file? file }
end

def expected_coverage
  {
    "#{test_app}/never_called.sh" => [nil, nil, 0, nil],
    "#{test_app}/scripts/case.sh" => [nil, nil, nil, 2, 1, nil, 0, 0, 1, nil, nil, nil, 1, 1, nil],
    "#{test_app}/scripts/function.sh" => [nil, nil, nil, 2, nil, nil, nil, 1, 1, nil, nil, 1, 1, nil],
    "#{test_app}/scripts/long_line.sh" => [nil, nil, 1, 1, 1, 0, nil],
    "#{test_app}/scripts/nested/simple.sh" => [nil, nil, nil, nil, 1, 1, nil, 0, nil, nil, 1, nil, nil],
    "#{test_app}/scripts/one_liner.sh" => [nil, nil, 2, nil, 1, nil, 0, nil, nil],
    "#{test_app}/scripts/simple.sh" => [nil, nil, nil, nil, 1, 1, nil, 0, nil, nil, 1, nil, nil],
    "#{test_app}/scripts/source.sh" => [nil, nil, 1, nil, 2, nil],
    "#{test_app}/scripts/sourced.txt" => [nil, nil, 1, nil],
    "#{test_app}/scripts/stdin.sh" => [nil, nil, 1, 1, 1, nil],
    "#{test_app}/test_suite.sh" => [nil, nil, 0, nil, nil, 0, nil]
  }
end

