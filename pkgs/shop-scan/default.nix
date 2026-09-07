# shop-scan — bun/TypeScript CLI packaged for Nix.
#
# Reference pattern for TypeScript tools in this repo. nixpkgs has no
# `buildBunPackage`, so this follows the shape used by nixpkgs' own bun packages
# (see pkgs/by-name/hu/hunk): dependencies are fetched in a fixed-output
# derivation, then `bun build --compile` produces a single static binary.
{
  lib,
  stdenv,
  bun,
}: let
  pname = "shop-scan";
  version = "0.1.0";

  # Only the files the build actually reads, so editing the README or adding a
  # sibling tool does not invalidate the build.
  src = lib.fileset.toSource {
    root = ./.;
    fileset = lib.fileset.unions [
      ./package.json
      ./bun.lock
      ./tsconfig.json
      ./src
    ];
  };

  # The ONLY phase permitted network access. Everything downloaded here is
  # pinned by `outputHash`, which keeps the real build hermetic.
  #
  # When bun.lock changes this hash must change too: set it to
  # lib.fakeHash, run the build, and copy the value nix prints as "got:".
  node_modules = stdenv.mkDerivation {
    pname = "${pname}-node_modules";
    inherit version src;

    nativeBuildInputs = [bun];
    dontConfigure = true;

    buildPhase = ''
      runHook preBuild
      export HOME=$(mktemp -d)
      export BUN_INSTALL_CACHE_DIR=$(mktemp -d)
      bun install \
        --frozen-lockfile \
        --ignore-scripts \
        --no-progress \
        --cpu="*" \
        --os="*"
      runHook postBuild
    '';

    installPhase = ''
      runHook preInstall
      mkdir -p $out
      cp -R node_modules $out
      runHook postInstall
    '';

    dontFixup = true;
    outputHash = "sha256-Yv4ml+HjgeBQAXZtnAEHNw8dX9Bor9QoTSdjvTiG/+w=";
    outputHashMode = "recursive";
  };
in
  stdenv.mkDerivation {
    inherit pname version src;

    strictDeps = true;
    nativeBuildInputs = [bun];

    configurePhase = ''
      runHook preConfigure
      cp -R ${node_modules}/node_modules .
      chmod -R u+w node_modules
      runHook postConfigure
    '';

    buildPhase = ''
      runHook preBuild
      export HOME=$(mktemp -d)
      mkdir -p .bun-tmp .bun-install
      BUN_TMPDIR=$PWD/.bun-tmp \
      BUN_INSTALL=$PWD/.bun-install \
        bun build --compile \
          --no-compile-autoload-bunfig \
          --no-compile-autoload-dotenv \
          src/${pname}.ts \
          --outfile ${pname}
      runHook postBuild
    '';

    installPhase = ''
      runHook preInstall
      install -Dm755 ${pname} $out/bin/${pname}
      runHook postInstall
    '';

    # `bun build --compile` emits a self-extracting binary with the runtime
    # appended; stripping or RPATH-rewriting it corrupts the payload.
    dontFixup = true;
    dontStrip = true;

    doInstallCheck = true;
    installCheckPhase = ''
      runHook preInstallCheck
      $out/bin/${pname} --version | grep -F "${version}"
      runHook postInstallCheck
    '';

    passthru = {inherit node_modules;};

    meta = {
      description = "Human-paced price comparison across public storefront listings";
      mainProgram = pname;
      platforms = lib.platforms.linux ++ lib.platforms.darwin;
    };
  }
