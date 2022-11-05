### Controlling the command name

Bashcov respects all of your `.simplecov` settings save one --
[`SimpleCov.command_name`](http://www.rubydoc.info/gems/simplecov/SimpleCov/Configuration#command_name-instance_method),
which is the tag that SimpleCov attaches to coverage results from a particular
test suite. You can set the value of `SimpleCov.command_name` by using
Bashcov's `--command-name` option, or by assigning a value to the environment
variable `BASHCOV_COMMAND_NAME`. Otherwise, Bashcov will generate a command
name for you based on the name of the currently-executing Bash script and any
arguments passed to it. For example, assuming your Bash lives at `/bin/bash`
and you run the command

```
bashcov -- ./test_suite.sh --and some --flags
```

Bashcov will set `SimpleCov.command_name` to `"/bin/bash ./test_suite.sh --and
some --flags"`. Basing `SimpleCov.command_name` on the executing command helps
to ensure that multiple coverage runs don't [overwrite each other's
results](https://github.com/colszowka/simplecov#test-suite-names) due to
SimpleCov identifying multiple runs by the same tag. The `--command-name` and
`BASHCOV_COMMAND_NAME` knobs are there for you to twiddle in case your test
suite runs the exact same `bashcov` command more than once, in which case the
generated command name will not distinguish each invocation from the others.

For more info on `SimpleCov.command_name` and its relation to SimpleCov's
result-merging behavior, see the [SimpleCov
README](https://github.com/colszowka/simplecov#merging-results).

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
