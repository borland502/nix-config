# Custom packages built from this repo.
#
# One directory per tool, named for the tool rather than its language — callers
# should not need to know what a thing is written in. Each directory owns its
# source, its dependency manifest, a default.nix that builds it, and a
# standalone Taskfile.yml for working on it directly.
#
# Registration is explicit: a directory is not a package until it is listed
# here, so a scratch directory can never become part of the build.
pkgs: {
  gopwgen = pkgs.callPackage ./gopwgen {};
  shop-scan = pkgs.callPackage ./shop-scan {};
  technitium-dash = pkgs.python3.pkgs.callPackage ./technitium-dash {};
  wordgen = pkgs.callPackage ./wordgen {};
}
