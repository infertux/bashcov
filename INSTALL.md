# Installing Bashcov

## Installation as a Ruby gem

Bashcov is distributed as [a Ruby gem](https://guides.rubygems.org/) -- that
is, as a software package for [the Ruby programming language](https://www.ruby-lang.org/en/).  It is hosted on
https://rubygems.org/ and is installable with tools distributed with Ruby
itself.

### Prerequisites

- Ruby (installation instructions [here](https://www.ruby-lang.org/en/documentation/installation/)).
- Development tools (primarily, a C compiler and `make`).  These are needed
  because certain of Bashcov's Ruby gem dependencies include native extensions
  that must be compiled for your host platform.  Installation instructions are
  OS- and distribution-specific; please consult your OS and/or distribution's
  documentation.

### Installation with the `gem` command

The `gem` executable is included with the Ruby distribution.  To install
Bashcov for your current user, run:

```shell-session
$ gem install bashcov
```

Now you can run Bashcov with:

```shell-session
$ bashcov -- <your-bash-script> <and-options>
```

### Installation with Bundler

[Bundler](https://bundler.io/), an environment manager for Ruby, is included in
(quoting the https://bundler.io/ landing page) "[a]ny modern distribution of
Ruby".  To install Bashcov with Bundler, create a file named `Gemfile` in your
project's top-level directory and ensure it contains the following:

```ruby
source 'https://rubygems.org'
gem 'bashcov'
```

Then, run this to install Bashcov (and the other gems specified in your
`Gemfile`):

```shell-session
$ bundle install
```

Finally, to run Bashcov, execute:

```shell-session
$ bundle exec bashcov -- <your-bash-script> <and-options>
```

For more on Bundler, please see [its "Getting Started" guide](https://bundler.io/guides/getting_started.html#getting-started).

## Installation with the Nix package manager

Bashcov is available using [the Nix package manager](https://nixos.org/).
Specifically, Bashcov exposes a [Nix flake](https://nixos.org/) (a sort of
supercharged package) consumable via various subcommands of the `nix` command
line tool.

### Running Bashcov as [a Nix application](https://nixos.org/manual/nix/stable/command-ref/new-cli/nix3-run.html)

You can use Nix to run Bashcov without first explicitly installing it:

```shell-session
$ nix run 'github:infertux/bashcov' -- <your-bash-script> <and-options>
```

### Adding Bashcov to [a Nix shell environment](https://nixos.org/manual/nix/stable/command-ref/new-cli/nix3-shell)

You can start a shell with Bashcov available like so:

```shell-session
$ command -v bashcov || echo ':(' 1>&2
:(
$ nix shell 'github:infertux/bashcov'
$ command -v bashcov || echo ':(' 1>&2
/nix/store/ns3phdbmfxkf6xqbz0lzha0846ngbmwc-bashcov-3.0.2/bin/bashcov
```

### Incorporating Bashcov into your Nix flake

You can incorporate Bashcov into your own flake by declaring it as an input and
then referencing its output attribute `packages.<system>.bashcov`.  For
instance, to include Bashcov in a [`nix develop` environment](https://nixos.org/manual/nix/stable/command-ref/new-cli/nix3-develop),
you could do something like the following:

```nix
# flake.nix

{
  inputs = {
    bashcov.url = "github:infertux/bashcov";
    bashcov.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = inputs @ { nixpkgs, bashcov, ... }: let
    system = "x86_64-linux";
  in {
    devShells.${system}.default = nixpkgs.legacyPackages.${system}.mkShell {
      packages = [inputs.bashcov.packages.${system}.bashcov];
    };
  };
}
```

Now, when you execute `nix develop` from within your flake project, the
`bashcov` command will be available in your environment.
