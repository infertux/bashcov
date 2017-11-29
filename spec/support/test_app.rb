# frozen_string_literal: true

def test_app(*maybe_paths)
  File.join(File.expand_path("../../test_app", __FILE__), *maybe_paths)
end

def test_suite
  test_app("test_suite.sh")
end

def uncovered_files
  [test_app("never_called.sh")]
end

def expected_coverage # rubocop:disable Metrics/MethodLength
  {
    "#{test_app}/never_called.sh" => [nil, nil, 0],
    "#{test_app}/scripts/case.sh" => [nil, nil, nil, 2, nil, 1, nil, nil, 0, 1, nil, nil, nil, 1, 1],
    "#{test_app}/scripts/cd.sh" => [nil, nil, 1, 2, nil, 3, 1, 3, nil, 2, nil, nil, 1, nil, 3, nil, 6, nil, 1, nil, 1],
    "#{test_app}/scripts/delete.sh" => [nil, nil, 1, 1, 1, 1, nil, 1, 1],
    "#{test_app}/scripts/function.sh" => [nil, nil, nil, 2, nil, nil, nil, 1, 1, nil, nil, nil, nil, 1, nil, nil, 1, 1, 1],
    "#{test_app}/scripts/long_line.sh" => [nil, nil, 1, 1, 1, 0],
    "#{test_app}/scripts/nested/simple.sh" => [nil, nil, nil, nil, 1, 1, nil, 0, nil, nil, 1],
    "#{test_app}/scripts/new\nline.sh" => [nil, nil, 1, nil, 2],
    "#{test_app}/scripts/nounset.sh" => [nil, nil, 1, nil, 1, nil, 0],
    "#{test_app}/scripts/one_liner.sh" => [nil, nil, 2, nil, 1, nil, 0],
    "#{test_app}/scripts/process_substitution.sh" => [nil, nil, nil, 1, nil, nil, 2, nil, 4],
    "#{test_app}/scripts/simple.sh" => [nil, nil, nil, nil, 1, 1, nil, 0, nil, nil, 1],
    "#{test_app}/scripts/source.sh" => [nil, nil, 1, nil, 2],
    "#{test_app}/scripts/sourced.txt" => [nil, nil, 1],
    "#{test_app}/scripts/unicode.sh" => [nil, nil, nil, 1, nil, 1],
    "#{test_app}/scripts/multiline.sh" => [nil, nil, nil, 1, nil, 0, nil, 1, nil, 1, nil, 0, nil, nil, 1, 2, 1, 1, 0, nil, nil, 2, nil, nil, 1, 1, 1, 1, nil, 1, 1, 1, 1, 1, nil, 1, 1, 1, 1, nil, 1],
    "#{test_app}/scripts/multiline2.sh" => [nil, nil, 1, 1, 1, 1, nil, 1, 1, 1, 1, nil, 1, 1, 1, 1, 1, 1, nil, 1, 1, 1, 1, 1, 1, 1, 1, nil, 1, 1, 1, nil, 1],
    "#{test_app}/scripts/executable" => [nil, nil, 1],
    "#{test_app}/scripts/exit_non_zero.sh" => [nil, nil, 1],
    "#{test_app}/scripts/no_shebang.sh" => [nil, nil, nil, nil, 0],
    "#{test_app}/scripts/no_extension/bin_bash" => [nil, nil, 0],
    "#{test_app}/scripts/no_extension/bin_bash_with_args" => [nil, nil, 0],
    "#{test_app}/scripts/no_extension/bin_dash" => [nil, nil, 0],
    "#{test_app}/scripts/no_extension/bin_sh" => [nil, nil, 0],
    "#{test_app}/scripts/no_extension/usr_bin_env_bash" => [nil, nil, 0],
    "#{test_app}/test_suite.sh" => [nil, nil, 2, nil, 1],
  }
end

def expected_missing
  [
    "#{test_app}/scripts/bad_syntax.sh",
    "#{test_app}/scripts/no_extension/usr_bin_env_perl",
    "#{test_app}/scripts/no_extension/usr_local_bin_gawk",
  ]
end
