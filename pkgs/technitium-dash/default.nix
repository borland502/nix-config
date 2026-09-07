# technitium-dash — Python CLI packaged for Nix.
#
# Reference pattern for Python tools in this repo (see ../README.md): a
# pyproject.toml plus a thin buildPythonApplication wrapper, with dependencies
# resolved from nixpkgs. Registered via pkgs.python3.pkgs.callPackage so that
# httpx/rich come from the Python package set rather than the top level.
{
  lib,
  buildPythonApplication,
  hatchling,
  httpx,
  rich,
}:
buildPythonApplication {
  pname = "technitium-dash";
  version = "0.2.0";

  src = lib.fileset.toSource {
    root = ./.;
    fileset = lib.fileset.unions [
      ./pyproject.toml
      ./src
    ];
  };

  pyproject = true;
  build-system = [hatchling];
  dependencies = [httpx rich];

  pythonImportsCheck = ["technitium_dash"];

  meta = {
    description = "Technitium DNS stats and live query panel";
    mainProgram = "technitium-dash";
    platforms = lib.platforms.linux ++ lib.platforms.darwin;
  };
}
