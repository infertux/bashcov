Feature:

  Users can control the command name used for identifying SimpleCov's coverage
  results through an environment variable or a command-line option; by default
  Bashcov auto-generates a unique(-ish) command name based on the command
  Bashcov was asked to execute.

  Background:

    Given SimpleCov is configured with:
      """
      require "simplecov"
      SimpleCov.configure do
        use_merging true
      end
      """

    And a file named "test.sh" with mode "0755" and with:
      """
      #!/bin/bash
      date
      """

  Scenario: no explicit command name is provided

    When I run the following commands with bashcov:
      """
      ./test.sh
      """

    Then the results should contain the commands:
      | /bin/bash ./test.sh |

  Scenario: the command name is set with `--command-name`

    When I run the following commands with bashcov using `--command-name hey-i-am-a-command`:
      """
      ./test.sh
      """

    And I run the following commands with bashcov using `--command-name cool-i-am-a-command-too`:
      """
      ./test.sh
      """

    Then the results should contain the commands:
      | hey-i-am-a-command |
      | cool-i-am-a-command-too |

  Scenario: the command name is provided with `$BASHCOV_COMMAND_NAME`

    When I set the environment variable "BASHCOV_COMMAND_NAME" to "mytestsuite"

    And I run the following commands with bashcov:
      """
      ./test.sh
      """

    Then the results should contain the commands:
      | mytestsuite |
