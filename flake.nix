{
  description = "Code coverage tool for Bash";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-23.05";

    devshell.url = "github:numtide/devshell";
    devshell.inputs.nixpkgs.follows = "nixpkgs";

    flake-compat.url = "github:edolstra/flake-compat";
    flake-compat.flake = false;

    flake-parts.url = "github:hercules-ci/flake-parts";

    treefmt-nix.url = "github:numtide/treefmt-nix";
    treefmt-nix.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = inputs @ {
    self,
    devshell,
    flake-parts,
    treefmt-nix,
    ...
  }:
    flake-parts.lib.mkFlake {inherit inputs;} ({lib, ...}: {
      systems = [
        "aarch64-darwin"
        "aarch64-linux"
        "x86_64-darwin"
        "x86_64-linux"
      ];

      imports = [
        devshell.flakeModule
        flake-parts.flakeModules.easyOverlay
        treefmt-nix.flakeModule
      ];

      perSystem = {
        config,
        pkgs,
        self',
        system,
        ...
      }: let
        newestRuby = let
          rubies = lib.filterAttrs (name: value: let
            hasRubyEngine = builtins.tryEval (value ? rubyEngine);
          in
            lib.hasPrefix "ruby" name && hasRubyEngine.success && hasRubyEngine.value)
          pkgs;

          recentRubies =
            lib.foldlAttrs (
              acc: name: value: let
                v = toString value.version;
              in
                acc ++ (lib.optional (lib.versionAtLeast v "3" && lib.versionOlder v "4") {inherit name value;})
            ) []
            rubies;

          sortedRubies = lib.sort (x: y: lib.versionAtLeast (toString x.value.version) (toString y.value.version)) recentRubies;
        in
          if (lib.length sortedRubies) > 0
          then lib.head sortedRubies
          else {
            name = "ruby";
            value = pkgs.ruby;
          };

        ruby = newestRuby.value;
        rubyName = newestRuby.name;
      in {
        # `nix run '.#devshell' -- update-deps`, etc.
        apps.devshell = self'.devShells.default.flakeApp;

        checks = {
          inherit (config.packages) bashcov;
        };

        devshells.default = {
          imports = [
            # Ruby support, including prerequisites for compiling native
            # extensions.
            "${inputs.devshell}/extra/language/ruby.nix"
          ];

          commands = [
            {
              name = "fmt";
              category = "linting";
              help = "Format the Nix code in this project";
              command = ''
                exec ${config.treefmt.build.wrapper}/bin/treefmt "$@"
              '';
            }

            {
              package = ruby;
              category = "development";
            }

            {
              package = pkgs.bundix;
              category = "maintenance";
            }

            {
              name = "update-deps";
              category = "maintenance";
              help = "Update dependencies with Bundler and Bundix";
              command = ''
                export NIX_PATH="nixpkgs=${toString pkgs.path}''${NIX_PATH:+:''${NIX_PATH}}"
                lockfile="''${PRJ_ROOT:-.}/Gemfile.nix.lock"
                bundle lock --lockfile "$lockfile"
                exec bundix --ruby ${lib.escapeShellArg rubyName} --lockfile="$lockfile" "$@"
              '';
            }

            {
              name = "update-deps-conservative";
              category = "maintenance";
              help = "Update dependencies with Bundler and Bundix (if necessary)";

              # If `nix build` succeeds, then presume that the lockfiles do not
              # need to be updated.  If `nix build` fails after updating the
              # lockfile, out-of-date dependencies weren't to blame for the
              # build failure.
              command = ''
                export NIX_PATH="nixpkgs=${toString pkgs.path}''${NIX_PATH:+:''${NIX_PATH}}"
                nix build && exit
                if update-deps; then
                  nix build || {
                    rc="$?"
                    git restore "''${PRJ_ROOT}/Gemfile.nix.lock" "''${PRJ_ROOT}/gemset.nix" || rc="$?"
                    exit "$rc"
                  }
                fi
              '';
            }
          ];
        };

        overlayAttrs = {
          inherit (config.packages) bashcov;
        };

        packages = {
          bashcov = pkgs.callPackage ({
            lib,
            bash,
            buildRubyGem,
            makeWrapper,
            ruby,
            gems,
            doCheck ? true, # Whether to run RSpec and Cucumber Rake tasks.
          }: let
            inherit (gems'.gems.bashcov) version;
            gems' = gems.override {inherit ruby;};
            gemName = gems'.gems.bashcov.name;
          in
            assert lib.assertMsg (gems'.gems ? bashcov) "bashcov: gem set must contain `bashcov`";
              buildRubyGem {
                inherit doCheck gemName version ruby;

                name = "${gemName}-${version}";

                src = self;

                nativeBuildInputs = [bash makeWrapper];
                propagatedBuildInputs = [gems'];

                checkPhase = ''
                  ${config.packages.gems.wrappedRuby}/bin/rake cucumber spec
                '';

                # Replace shebangs like "#!/usr/bin/env bash" with Nix store
                # paths.  Note that we need to do this for `./bin/bashcov`
                # itself, as otherwise running `bashcov` from Cucumber features
                # during the check phase will fail because `/usr/bin/env` does
                # not exist in the build sandbox.
                doPatch = true;
                postPatch = ''
                  patchShebangs ./bin ./features ./spec
                '';

                # Ensure that Bashcov can find Bash, but make this Bash
                # low-precedence by placing its /bin/ at the end of PATH.
                postInstall = ''
                  wrapProgram $out/bin/bashcov --suffix PATH : ${bash}/bin
                '';
              }) {
            inherit ruby;
            inherit (config.packages) gems;
          };

          default = config.packages.bashcov;

          gems = pkgs.callPackage ({
            bundlerEnv,
            ruby,
          }:
            bundlerEnv {
              inherit ruby;
              pname = "bashcov";
              gemdir = self;
              lockfile = ./Gemfile.nix.lock;
              version = "3.0.2";
              postBuild = ''
                for gem in $out/${ruby.gemPath}/bundler/gems/*; do
                  ln -sfrT "$gem" $out/${ruby.gemPath}/gems/"''${gem##*/}"
                done
              '';
            }) {inherit ruby;};
        };

        treefmt = {
          programs.alejandra.enable = true;
          flakeFormatter = true;
          projectRootFile = "flake.nix";
        };
      };
    });
}
