Feature:

  Bashcov defers to SimpleCov settings configured in users' `.simplecov` files,
  unless overridden on the command line or via the environment.

  Background:

    Given a file named "test.sh" with mode "0755" and with:
      """
      #!/bin/bash
      true
      """

  Scenario: no explicit command name is provided

    When I run the following commands with bashcov:
      """
      ./test.sh
      """

    Then the results should contain the commands:
      | /bin/bash ./test.sh |

  Scenario: the command name is set in `.simplecov`

    Given SimpleCov is configured with:
      """
      require "simplecov"
      SimpleCov.configure do
        command_name "and conquer"
      end
      """

    When I run the following commands with bashcov:
      """
      ./test.sh
      """

    Then the results should contain the commands:
      | and conquer |

    When I run the following commands with bashcov using `--command-name houston`:
      """
      ./test.sh
      """

    Then the results should contain the commands:
      | houston |

    When I set the environment variable "BASHCOV_COMMAND_NAME" to "economy"

    And I run the following commands with bashcov:
      """
      ./test.sh
      """

    Then the results should contain the commands:
      | economy |
