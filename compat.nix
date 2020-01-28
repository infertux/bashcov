let
  haveFlakeLock = builtins.pathExists ./flake.lock;

  lock = builtins.fromJSON (builtins.readFile ./flake.lock);

  ref =
    if haveFlakeLock
    then lock.nodes.flake-compat.locked.rev
    else "master";

  checksum =
    if haveFlakeLock
    then {
      sha256 = lock.nodes.flake-compat.locked.narHash;
    }
    else {};

  args =
    {
      url = "https://github.com/edolstra/flake-compat/archive/${ref}.tar.gz";
    }
    // checksum;

  flakeCompat = fetchTarball args;
in
  import flakeCompat {src = ./.;}
