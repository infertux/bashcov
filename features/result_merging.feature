Feature:

  When Bashcov is run more than once and SimpleCov is configured to merge the
  results of multiple runs, each run should have a unique command name, and the
  results from each run should be merged together.  However, if command names
  are not unique, only the last-run command should appear in the coverage
  results.

  Background:

    Given SimpleCov is configured with:
      """
      require "simplecov"
      SimpleCov.configure do
        use_merging true
      end
      """

    And a file named "simple.sh" with mode "0755" and with:
      """
      #!/usr/bin/env bash
      tr '[[:lower:]]' '[[:upper:]]' <<<'shhh'
      """

  Scenario: SimpleCov.use_merging == true and SimpleCov.command_name is unique

    When I run the following commands with bashcov using `--command-name simple-test-1`:
      """
      ./simple.sh
      """

    And I run the following commands with bashcov using `--command-name simple-test-2`:
      """
      ./simple.sh
      """

    Then the results should contain the commands:
      | simple-test-1 |
      | simple-test-2 |

    And the file "./simple.sh" should have the following coverage:
      | 1 | nil |
      | 2 | 2 |

  Scenario: SimpleCov.use_merging == true and SimpleCov.command_name is not unique

    When I run the following commands with bashcov using `--command-name simple-test`:
      """
      ./simple.sh
      """

    And I run the following commands with bashcov using `--command-name simple-test`:
      """
      ./simple.sh
      """

    Then the results should contain the commands:
      | simple-test |

    And the file "./simple.sh" should have the following coverage:
      | 1 | nil |
      | 2 | 1 |
