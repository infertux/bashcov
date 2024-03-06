# Hacking on Bashcov

[Nix development shell]: #entering-the-nix-development-shell
[`Gemfile.nix.lock`]: ./Gemfile.nix.lock
[`gemset.nix`]: ./gemset.nix
[`bashcov.gemspec`]: ./bashcov.gemspec

## Nix flake usage

This project supplies a [`flake.nix`](./flake.nix) file defining a Nix
flake[^nix-flakes] that makes it possible to build, test, run, and hack on
Bashcov using the [Nix package manager](https://nixos.org)

[^nix-flakes]: See the [NixOS wiki](https://nixos.wiki/wiki/Flakes) and the
               [`nix flake` page in the Nix package manager reference manual](https://nixos.org/manual/nix/unstable/command-ref/new-cli/nix3-flake.html)
               for background on Nix flakes.

This Nix flake defines three important important outputs:

1. A [Nix package for Bashcov](#building-the-bashcov-package),
2. A [Nix flake check](#nix-flake-checks) (test) that runs Bashcov's
   unit and feature tests,
3. A [Nix application](#running-the-nix-application),[^app] and
4. A [Nix development shell],[^devshell].

[^devshell]: Based on the [`numtide/devshell`](https://github.com/numtide/devshell) project.
[^app]: Runnable with `nix run`.

In order to work on the Bashcov project's Nix features,
you'll need to [install the Nix package manager](https://nixos.org/download.html) and
[ensure that the `flakes` and `nix-command` experimental features are enabled](https://nixos.wiki/wiki/Flakes#Enable_flakes).

### Building the Bashcov package

To build the Bashcov package exposed by this flake, run the
following command:[^verbose-output]

[^verbose-output]: Note that the `-L` flag can be omitted for terser output.

```shell-session
$ nix build -L '.#'
```

Or:

```shell-session
$ nix build -L '.#bashcov'
```

These two forms are functionally equivalent because the
Bashcov package is the default package.

In addition to building the package, `nix build` will place a symbolic link to
its output path at `./result` (`ls -lAR ./result/`, `tree ./result/`, or
similar to see what the package contains).

### Nix flake checks

This project includes a test of Bashcov's functionality and features, exposed
as a Nix flake check.  It is the eq

#### Running Nix flake checks

To run Nix flake checks, execute the following command:[^verbose-output]

```shell-session
$ nix flake check -L
```

If a check fails, `nix` will print a diagnostic message and exit with nonzero
status.

##### Running a check for a specific system

Running `nix flake check` will execute Nix flake checks for all supported
systems.[^supported-systems]  To run a check for a particular system, instead
use the `nix build` command.  For instance, to execute the Bashcov unit and
feature tests with Nix on the `x86_64-linux` system, run:[^verbose-output]

```shell-session
$ nix build -L '.#checks.x86_64-linux.bashcov'
```

[^supported-systems]: Run `nix flake show` to view flake outputs namespaced by
                      all supported systems.

### Running the Nix application

To run Bashcov itself:

```shell-session
$ nix run '.#' -- <args>
```

To run commands from [the Nix development shell](#entering-the-nix-development-shell)
but without entering the shell:

```shell-session
$ nix run '.#devshell' -- <command> <args>
```

For instance, to run [the `update-deps` shell command](#summary-of-available-commands):

```shell-session
$ nix run '.#devshell' -- update-deps
```

### Entering the Nix development shell

To enter the Nix development shell, run the following command:

```shell-session
$ nix develop
```

You will be presented with a menu of commands available within the development
shell.

#### Summary of available commands

- `fmt`: format all Nix code in this project using
  [`alejandra`](https://github.com/kamadorueda/alejandra).
- `bundix`: tool for managing Nix <=> Ruby integration assets (Bundix lives
  [here](https://github.com/nix-community/bundix)).
- `update-deps`: update [the Nix-specific lockfile][`Gemfile.nix.lock`] and
  [Nix gemset][`gemset.nix`].
- `update-deps-conservative`: update [the Nix-specific lockfile][`Gemfile.nix.lock`]
  and [Nix gemset][`gemset.nix`] if (and only if) `nix build` fails _without_
  updates to those assets **and** `nix build` succeeds _with_ updates to them.

### Maintenance of Nix assets

The Bashcov Nix package depends on [`nixpkgs`'s Ruby
integration](https://nixos.org/manual/nixpkgs/stable/#developing-with-ruby);
specifically, it uses the `bundlerEnv` function to create an environment with
all of Bashcov's Ruby gem dependencies present.  `bundlerEnv` requires a
Bundler lockfile (here, [`Gemfile.nix.lock`]) and a Nix-specific [`gemset.nix`]
that acts as a sort of translation layer between Bundler and Nix.

Both of these files must be updated from time to time in order to reflect
changes in [`bashcov.gemspec`], including certain changes to Bashcov itself
(e.g. version bumps).

> **Note**
> If [`bashcov.gemspec`] is updated without updating the Bundler lockfile and
> [`gemset.nix`], the Bashcov Nix package will fail to build.

The [Nix development shell] includes two convenience commands for managing
these assets:

- `update-deps` unconditionally updates [`Gemfile.nix.lock`] with
  [`bundle lock`](https://bundler.io/v2.4/man/bundle-lock.1.html), then updates
  [`gemset.nix`] to reflect any changes to the Bundler lockfile.
- `update-deps-conservative` does the same, but if (and only if) doing so fixes
  failures running `nix build`.  That is, it updates the assets if it looks
  like problems with those assets have broken the Bashcov Nix package.
