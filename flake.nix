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

        devshells.default = {
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
          ];

          # Needed for compiling native extensions
          devshell.packages = with pkgs; [gcc gnumake];
        };

        overlayAttrs = {
          inherit (config.packages) bashcov;
        };

        packages = {
          bashcov = let
            gemName = "bashcov";
            version = "3.0.2";
          in
            pkgs.buildRubyGem rec {
              inherit gemName version ruby;

              name = "${gemName}-${version}";

              src = self;

              nativeBuildInputs = with pkgs; [bash git makeWrapper];
              propagatedBuildInputs = [config.packages.gems];

              # Whether to run RSpec and Cucumber Rake tasks.
              doCheck = true;
              checkPhase = ''
                ${config.packages.gems.wrappedRuby}/bin/ruby ${config.packages.gems.gems.rake}/bin/rake cucumber spec
              '';

              # Replace shebangs like "#!/usr/bin/env bash" with Nix store paths.
              # Note that we need to do this for `./bin/bashcov` itself, as
              # otherwise running `bashcov` from Cucumber features during the
              # check phase will fail because `/usr/bin/env` does not exist in
              # the build sandbox.
              doPatch = true;
              postPatch = ''
                patchShebangs ./bin ./features ./spec
              '';

              # Ensure that Bashcov can find Bash, but make this Bash
              # low-precedence by placing its /bin/ at the end of PATH.
              postInstall = ''
                wrapProgram $out/bin/bashcov --suffix PATH : ${pkgs.bash}/bin
              '';
            };

          default = config.packages.bashcov;

          gems = pkgs.bundlerEnv {
            inherit ruby;
            pname = "bashcov";
            gemdir = self;
            lockfile = ./Gemfile.nix.lock;
            version = "3.0.2";
          };
        };

        treefmt = {
          programs.alejandra.enable = true;
          flakeFormatter = true;
          projectRootFile = "flake.nix";
        };
      };
    });
}
