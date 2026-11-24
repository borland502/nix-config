{pkgs}: let
  registry = import ../pkgs pkgs;
  goShell = package:
    pkgs.mkShell {
      inputsFrom = [package];
      packages = with pkgs; [go gopls go-task];
    };
  pythonTools = with pkgs; [go-task ruff];
  typesPygments = pkgs.python3Packages.buildPythonPackage rec {
    pname = "types-pygments";
    version = "2.21.0.20260819";
    format = "wheel";
    src = pkgs.fetchPypi {
      pname = "types_pygments";
      inherit version format;
      dist = "py3";
      python = "py3";
      abi = "none";
      platform = "any";
      sha256 = "85e216770d616db6a7e96fb70c2de9d9f283b746c37edb7768ce645bdbcaddb2";
    };
  };
in {
  gopwgen = goShell registry.gopwgen;
  wordgen = goShell registry.wordgen;
  shop-scan = pkgs.mkShell {
    inputsFrom = [registry.shop-scan];
    packages = with pkgs; [bun typescript go-task];
  };
  technitium-dash = pkgs.mkShell {
    packages =
      pythonTools
      ++ [
        (pkgs.python3.withPackages (p: with p; [httpx rich mypy]))
      ];
  };
  htmlpdf = pkgs.mkShell {
    inputsFrom = [registry.htmlpdf];
    packages =
      pythonTools
      ++ [
        (pkgs.python3.withPackages (p:
          with p; [
            mypy
            playwright
            pymupdf
            markdown-it-py
            mdit-py-plugins
            pygments
            pytest
            typesPygments
          ]))
      ];
  };
}
