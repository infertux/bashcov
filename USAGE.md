[Aruba]: https://github.com/cucumber/aruba "The Aruba CLI application testing framework"
[RSpec]: http://rspec.info/documentation "The RSpec BDD testing framework"
[SimpleCov]: https://github.com/colszowka/simplecov "The SimpleCov coverage framework"
[SimpleCov filters]: https://www.rubydoc.info/gems/simplecov#Filters "SimpleCov filters"
[`SimpleCov.command_name`]: https://www.rubydoc.info/gems/simplecov/SimpleCov%2FConfiguration:command_name "The SimpleCov.command_name configuration option"
[`SimpleCov.coverage_dir`]: https://www.rubydoc.info/gems/simplecov/SimpleCov%2FConfiguration:coverage_dir "The SimpleCov.coverage_dir configuration option"
[`SimpleCov.coverage_path`]: https://www.rubydoc.info/gems/simplecov/SimpleCov%2FConfiguration:coverage_path "The SimpleCov.coverage_path configuration option"
[`SimpleCov.minimum_coverage`]: https://www.rubydoc.info/gems/simplecov/SimpleCov%2FConfiguration:minimum_coverage "The SimpleCov.minimum_coverage configuration option"
[`SimpleCov.root`]: https://www.rubydoc.info/gems/simplecov/SimpleCov%2FConfiguration:root "The SimpleCov.root configuration option"
[`.simplecov` configuration file]: https://www.rubydoc.info/gems/simplecov/#Using__simplecov_for_centralized_config "The .simplecov configuration file"

### [SimpleCov] integration

#### Configuring SimpleCov using a [`.simplecov` configuration file]

While Bashcov is responsible for gathering coverage data for the shell scripts
under test, it's the [SimpleCov] framework that handles things like caching
coverage results and formatting coverage reports. As mentioned in [the
README](./README.md#simplecov-integration), you can customize the behavior of
SimpleCov by adding a [`.simplecov` configuration file] to the root directory
of your project. SimpleCov is [highly customizable](https://www.rubydoc.info/gems/simplecov/frames#Configuring_SimpleCov)
via its [many configuration options](http://rubydoc.info/gems/simplecov/SimpleCov/Configuration);
please see its [extensive documentation](https://www.rubydoc.info/gems/simplecov)
for ways in which you can tune SimpleCov to suit your project's needs.

#### Configuring [SimpleCov] at the command line

Bashcov exposes some SimpleCov settings as options to the `bashcov` executable:

```
$ bashcov --command-name erkeen [...]   # Sets SimpleCov.command_name to "erkeen"
$ bashcov --profile myprofile [...]     # Loads the SimpleCov profile "myprofile"
$ bashcov --root /project/root [...]    # Sets SimpleCov.root to "/project/root"
```

It also recognizes corresponding environment variables:

```
$ BASHCOV_COMMAND_NAME=erkeen bashcov [...]
$ BASHCOV_PROFILE=myprofile bashcov [...]
$ BASHCOV_ROOT=/project/root bashcov [...]
```

See below for details.

#### Controlling the command name

##### Synopsis

```
$ bashcov --command-name mytestsuite [...]          # Sets SimpleCov.command_name to "mytestsuite"
$ BASHCOV_COMMAND_NAME=mytestsuite bashcov [...]    # This does, too
```

##### Description

(**Note**: for the purposes of the following section, "test suite" means
"something that generates coverage results and is (or should be) uniquely
associated with them". A single `bashcov -- ./my_tests.sh` invocation counts as
a "test suite".)

SimpleCov associates coverage results with particular test suites using the
[`SimpleCov.command_name`] setting. It is vital that each test suite's command
name be **unique** -- quoting the [SimpleCov docs on test suite naming](https://www.rubydoc.info/gems/simplecov/#Test_suite_names):

> **[I]f multiple suites resolve to the same `command_name`** be aware that the
> coverage results **will clobber each other instead of being merged**.

To help avoid this, Bashcov automatically generates a value for
[`SimpleCov.command_name`] based on the name of the currently-executing Bash
script and any arguments passed to it. For example, assuming your Bash lives
at `/bin/bash` and you run the command:

```
$ bashcov -- ./test_suite.sh --and some --flags
```

Bashcov will set [`SimpleCov.command_name`] to `"/bin/bash ./test_suite.sh
--and some --flags"`.

Beware -- if you run the same script multiple times using the same arguments,
you will need to set [`SimpleCov.command_name`] yourself to prevent later runs
from overwriting the coverage results from previous runs. For example, you
might run a script with different environment variables in effect:

```
$ ENABLE_THRUSTERS=0 bashcov -- ./test_entrypoint.sh
$ ENABLE_THRUSTERS=1 bashcov -- ./test_entrypoint.sh
```

Since Bashcov's command name generation logic does not take environment
variables into account, the second run will clobber the results from the first.
In cases like this, you can provide your own command name by invoking Bashcov
with the `--command-name` option, or by assigning a value to the
`BASHCOV_COMMAND_NAME` environment variable.

**Note**: If you define a custom [`SimpleCov.command_name`] in your
[`.simplecov` configuration file], Bashcov will use this value rather than
auto-generating a command name as described above. Howevever, command names
provided using `--command-name` option or the `BASHCOV_COMMAND_NAME`
environment variable will override the command name defined in `.simplecov`.

##### Automatically generating a command name with [Aruba] and [RSpec]

[Aruba] is a tool for testing command-line applications; it integrates with
multiple Ruby-based testing frameworks, including the popular [RSpec]
behavior-driven development framework. If you'd like to use Bashcov with
[RSpec] and [Aruba], the following pattern helps ensure that each invocation of
Bashcov uses a unique [`SimpleCov.command_name`]:

```ruby
RSpec.describe "My CLI application", type: :aruba do
  # Set the BASHCOV_COMMAND_NAME environment variable to the full description
  # of each example group.
  around(:each) do |example|
    # `with_environment` is a helper method from Aruba that runs code (here,
    # the RSpec example group) with environment variables temporarily set to
    # the specified values.
    with_environment('BASHCOV_COMMAND_NAME' => example.full_description, &example)
  end

  context "given FROBNICATE=1" do
    it "frobnicates" do
      run_command_and_stop("bashcov", "--", "./test_suite.sh")
      expect(last_command_started.stdout.downcase).to include(/commencing\s+frobnication/)
    end
  end
end
```

The coverage results from the above example group will appear under the command
name `"My CLI application given FROBNICATE=1 frobnicates"`.

**Please note** that this technique will only work properly when Bashcov runs
**once per example group**: since the `around` hook sets `BASHCOV_COMMAND_NAME`
to a single value for the duration of the example group, each invocation of
Bashcov in that example group will have the same [`SimpleCov.command_name`],
and therefore only the results from the **last** Bashcov invocation will
persist in the coverage results cache and be reflected in the coverage report.

#### Loading a SimpleCov profile

##### Synopsis

```
$ bashcov --profile myprofile [...]         # Causes SimpleCov to load the "myprofile" profile
$ BASHCOV_PROFILE=myprofile bashcov [...]   # Ditto
```

##### Description

With Bashcov's `--profile` option or the `BASHCOV_PROFILE_NAME` environment
variable, you can load a specific [SimpleCov profile](https://www.rubydoc.info/gems/simplecov/#Profiles),
causing any settings defined in the named profile to be applied during the
current coverage run.

Why might you want to do this? Here's one scenario: perhaps you enforce a
minimum coverage percentage via [`SimpleCov.minimum_coverage`]. But -- you've
inherited a set of legacy shell scripts, and, as you get them under test, you
don't want your test suite to fail repeatedly until their coverage is up to the
usually-enforced percentage. You can apply a lower minimum coverage level to
the legacy scripts by doing something like the following:

```ruby
# .simplecov

SimpleCov.profiles.define "new" do
  minimum_coverage 90
end

SimpleCov.profiles.define "legacy" do
  minimum_coverage 50
end
```

Then run the tests of your legacy scripts with the option `bashcov --profile
legacy`, and those tests will only need to achieve 50% coverage. Run the tests
of the other scripts using `bashcov --profile new` to apply the more stringent
minimum coverage setting.

Another scenario: your test suite runs Bashcov more than once, and you don't
want to generate coverage reports until the entire test suite completes (by
default, Bashcov generates a report every time the `bashcov` process exits, via
defining a custom [`SimpleCov.at_exit` hook](https://www.rubydoc.info/gems/simplecov/#Customizing_exit_behaviour)).
You can turn off report generation like so:

```ruby
# .simplecov

SimpleCov.configure do
  # `use_merging` is true by default; it's defined here explicitly to highlight
  # that results-merging needs to be enabled in order to aggregate results
  # from multiple Bashcov runs.
  use_merging true
end

SimpleCov.profiles.define "intermediate" do
  # The default `at_exit` callback performs coverage report generation at
  # process exit; override this by making `at_exit` an empty block (a no-op).
  at_exit { }
end

SimpleCov.profiles.define "final" do
  at_exit do
    puts "Test suite complete! Generating coverage report(s)."
    SimpleCov.result.format!
  end
end
```

Invoke `bashcov` with `--profile intermediate` to disable report generation;
then, for the final `bashcov` invocation, use `--profile final` to create
a report aggregating the results from all Bashcov runs.

Quick tip: if it is not possible to know in advance which `bashcov` invocation
will come last -- for instance, maybe your test suite randomizes the test
execution order -- you can format your coverage results with a small script
that runs after your test suite completes:

```ruby
#!/usr/bin/env ruby

# format_coverage_results.rb

require "simplecov"

# Load stored coverage data from coverage/.resultset.json and create coverage
# report(s)
SimpleCov::ResultMerger.merged_result.format!
```

Run `ruby ./format_coverage_results.rb` once all Bashcov processes have exited,
and you'll end up with coverage reports in the `./coverage` subdirectory of
your project (or wherever [`SimpleCov.coverage_path`] lives, depending on how
you've configured [`SimpleCov.root`] and [`SimpleCov.coverage_dir`]).

#### Setting the project root

##### Synopsis

```
$ bashcov --root /my/project [...]          # SimpleCov.project_root is /my/project
$ BASHCOV_ROOT=/my/project bashcov [...]    # Same here
```

##### Description

[`SimpleCov.root`] is the directory SimpleCov considers to be the "root" of
your project; it is used for things like figuring out where
[`SimpleCov.coverage_dir`] is located, or excluding files outside your project
from coverage results.

In addition to its various uses within SimpleCov, Bashcov uses
[`SimpleCov.root`] as the starting point of the directory hierarchy it
[searches for unexecuted shell scripts](#ignoring-unexecuted-shell-scripts).

The default value of [`SimpleCov.root`] is the current working directory, and
this is a sensible value in many cases. If, however, you run Bashcov from a
directory other than your project's root, you can point Bashcov and SimpleCov
at the correct [`SimpleCov.root`] by using the `--root` option or the
`BASHCOV_ROOT` environment variable.

**Note**: If you specify [`SimpleCov.root`] using Bashcov's `--root` option or
the environment variable `BASHCOV_ROOT`, this will override the value of
[`SimpleCov.root`] as configured in your [`.simplecov` configuration file].

### Other Bashcov options

#### Ignoring unexecuted shell scripts

##### Synopsis

```
$ bashcov --skip-uncovered [...]    # Omits unexecuted shell scripts from coverage results
```

##### Description

By default, after running the provided Bash command, Bashcov checks whether
there are any shell scripts in your project that were left unexecuted. It adds
any such scripts to the coverage results, indicating that they were 100%
uncovered.

For example, suppose your project contains the following shell scripts:

```
myproject
└── bin
    ├── bar.sh
    ├── baz.sh
    └── foo.sh
```

Suppose further that your test entrypoint, `test/test_suite.sh`, contains:

```
#!/bin/bash

../bin/bar.sh
../bin/baz.sh
```

and that neither `bar.sh`, nor `baz.sh`, nor any commands invoked therein
result in executing `foo.sh`.  Nonetheless, running `bashcov --
./test/test_suite.sh` from your project's root directory would generate
coverage results **including** `foo.sh` (which would be shown as totally
uncovered).

This behavior helps bring attention to potential holes in your test suite's
coverage, but it can sometimes lead to including extraneous files in your
coverage results. If you want to exclude uncovered files from the coverage
results (and adding [SimpleCov filters] doesn't suit your use case), you can
tell Bashcov to ignore uncovered files by passing the `--skip-uncovered` flag.

### Some gory details

Figuring out where an executing Bash script lives in the file system can be
surprisingly difficult. Bash offers a fair amount of [introspection into its
internals](https://www.gnu.org/software/bash/manual/html_node/Bash-Variables.html),
but the location of the current script has to be inferred from the limited
information available through `BASH_SOURCE`, `PWD`, and `OLDPWD` (and
potentially `DIRSTACK` if you are using `pushd`/`popd`). For this purpose,
Bashcov puts Bash in debug mode and sets up a `PS4` that expands the values of
these variables, reading them on each command that Bash executes. But, given
that:

  * `BASH_SOURCE` is only an absolute path if the script was invoked using an
    absolute path,
  * the builtins `cd`, `pushd`, and `popd` alter `PWD` and `OLDPWD`, and
  * none of these variables are read-only and can therefore be `unset` or
    otherwise altered,

it can be easy to lose track of where we are.

_"Wait a minute, what about `pwd`, `readlink`, and so on?"_ That would be great,
except that subshells executed as part of expanding the `PS4` can cause Bash to
report [extra executions](https://github.com/infertux/bashcov/commit/4130874e30a05b7ab6ea66fb96a19acaa973c178)
for [certain lines](https://github.com/infertux/bashcov/pull/16). Also,
subshells are slow as the `PS4` is expanded on each and every command when Bash
is in debug mode.

To deal with these limitations, Bashcov uses the expedient of maintaining two
stacks that track changes to `PWD` and `OLDPWD`. To determine the full path to
the executing script, Bashcov iterates in reverse over the `PWD` stack, testing
for the first `$PWD/$BASH_SOURCE` combination that refers to an existing file.
This heuristic is susceptible to false positives -- under certain combinations
of directory structure, script invocation paths, and working directory changes,
it may yield a path that doesn't refer to the currently-running script.
However, it performs well under the various working directory changes performed
in the [test app demo] and avoids the spurious extra hits caused by using
subshells in the `PS4`.

One final note on innards: Bash 4.3 fixed a bug in which `PS4` expansion is
truncated to a maximum of 128 characters. On platforms whose Bash version
suffers from this bug, Bashcov uses the ASCII record separator character to
delimit the `PS4` fields, whereas it uses a long random string on Bash 4.3 and
above. When the field delimiter appears in the path of a script under test or
in a command the script executes, Bashcov won't correctly parse the `PS4` and
will abort early with incomplete coverage results.
