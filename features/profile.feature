Feature:

  Users can select a SimpleCov profile to load using the `--profile`
  command-line option or the `BASHCOV_PROFILE` environment variable.

  Background:

    Given SimpleCov is configured with:
      """
      require "simplecov"
      SimpleCov.profiles.define "all" do
        minimum_coverage 100
      end

      SimpleCov.profiles.define "some" do
        minimum_coverage 50
      end
      """

    And a file named "exit.sh" with mode "0755" and with:
      """
      exit
      echo "Whoops!"
      """

  Scenario: the "all" profile is selected with `--profile`

    When I run the following commands with bashcov using `--profile all`:
      """
      ./exit.sh
      """

    Then the stderr should contain:
      """
      is below the expected minimum coverage
      """

    And the exit status should not be 0

  Scenario: the "some" profile is selected with `--profile`

    When I run the following commands with bashcov using `--profile some`:
      """
      ./exit.sh
      """

    Then the exit status should be 0

  Scenario: the "all" profile is selected with `$BASHCOV_PROFILE`

    When I set the environment variable "BASHCOV_PROFILE" to "all"

    And I run the following commands with bashcov:
      """
      ./exit.sh
      """

    Then the stderr should contain:
      """
      is below the expected minimum coverage
      """

    And the exit status should not be 0

  Scenario: the "some" profile is selected with `$BASHCOV_PROFILE`

    When I set the environment variable "BASHCOV_PROFILE" to "some"

    And I run the following commands with bashcov:
      """
      ./exit.sh
      """

    Then the exit status should be 0
