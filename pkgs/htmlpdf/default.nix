# htmlpdf — Python CLI packaged for Nix.
{
  lib,
  libiconv,
  libiconvReal,
  libidn2,
  libpsl,
  libunistring,
  stdenv,
  python,
  file,
  pyinstaller,
  poetry-core,
  playwright,
  pymupdf,
  markdown-it-py,
  mdit-py-plugins,
  pygments,
  pytest,
}: let
  pythonBuildInputs = [
    python
    poetry-core
    pyinstaller
    playwright
    pymupdf
    markdown-it-py
    mdit-py-plugins
    pygments
    pytest
  ];
  pythonEnv = python.withPackages (_: pythonBuildInputs);
in
  stdenv.mkDerivation {
    pname = "htmlpdf";
    version = "0.1.0";

    src = lib.fileset.toSource {
      root = ./.;
      fileset = lib.fileset.unions [
        ./pyproject.toml
        ./poetry.lock
        ./src
        ./tests
      ];
    };

    strictDeps = true;
    dontConfigure = true;
    nativeBuildInputs = [pythonEnv file];

    doCheck = true;
    checkPhase = ''
      runHook preCheck
      PYTHONPATH="$PWD/src" python -c 'import htmlpdf'
      PYTHONPATH="$PWD/src" python -m pytest -q tests
      runHook postCheck
    '';

    buildPhase = ''
      runHook preBuild

      ${lib.optionalString stdenv.hostPlatform.isDarwin ''
        mkdir -p "$PWD/pyinstaller-libs"
        cp "${libiconvReal}/lib/libiconv.2.dylib" "$PWD/pyinstaller-libs/libiconv-gnu.2.dylib"
        /usr/bin/install_name_tool -id "@rpath/libiconv-gnu.2.dylib" "$PWD/pyinstaller-libs/libiconv-gnu.2.dylib"
        cp "${libidn2.out}/lib/libidn2.0.dylib" "$PWD/pyinstaller-libs/libidn2.0.dylib"
        /usr/bin/install_name_tool \
          -change "${libiconvReal}/lib/libiconv.2.dylib" "@rpath/libiconv-gnu.2.dylib" \
          "$PWD/pyinstaller-libs/libidn2.0.dylib"
        cp "${libpsl}/lib/libpsl.5.dylib" "$PWD/pyinstaller-libs/libpsl.5.dylib"
        /usr/bin/install_name_tool \
          -change "${libiconvReal}/lib/libiconv.2.dylib" "@rpath/libiconv-gnu.2.dylib" \
          "$PWD/pyinstaller-libs/libpsl.5.dylib"
        cp "${libunistring}/lib/libunistring.5.dylib" "$PWD/pyinstaller-libs/libunistring.5.dylib"
        /usr/bin/install_name_tool \
          -change "${libiconvReal}/lib/libiconv.2.dylib" "@rpath/libiconv-gnu.2.dylib" \
          "$PWD/pyinstaller-libs/libunistring.5.dylib"
      ''}

      # --collect-all htmlpdf bundles the package's modules, CSS, fonts, and pinned
      # Mermaid runtime. The spec runs collect_all() in PyInstaller's own
      # interpreter, which sees src only through PYTHONPATH (--paths applies later,
      # during analysis). Without it PyInstaller logs "not a package", drops all of
      # them, and the binary fails at runtime with ModuleNotFoundError.
      export PYTHONPATH="$PWD/src"
      PYINSTALLER_CONFIG_DIR="$PWD/.pyinstaller" PATH="${lib.optionalString stdenv.hostPlatform.isDarwin "/usr/bin:"}$PATH" pyi-makespec \
        --onefile \
        --name htmlpdf \
        --paths src \
        --specpath "$PWD" \
        --collect-all htmlpdf \
        --collect-all pymupdf \
        --collect-all playwright \
        src/htmlpdf/__main__.py
      ${lib.optionalString stdenv.hostPlatform.isDarwin ''
        python - <<PY
        from pathlib import Path

        spec = Path("htmlpdf.spec")
        preamble = """\
        a.binaries = [
            entry for entry in a.binaries
            if entry[0] not in {"libiconv.2.dylib", "libidn2.0.dylib", "libpsl.5.dylib", "libunistring.5.dylib"}
        ]
        a.binaries += [
            ("libiconv.2.dylib", "${libiconv}/lib/libiconv.2.dylib", "BINARY"),
            ("libiconv-gnu.2.dylib", "$PWD/pyinstaller-libs/libiconv-gnu.2.dylib", "BINARY"),
            ("libidn2.0.dylib", "$PWD/pyinstaller-libs/libidn2.0.dylib", "BINARY"),
            ("libpsl.5.dylib", "$PWD/pyinstaller-libs/libpsl.5.dylib", "BINARY"),
            ("libunistring.5.dylib", "$PWD/pyinstaller-libs/libunistring.5.dylib", "BINARY"),
        ]

        """
        spec.write_text(
            spec.read_text().replace("pyz = PYZ(a.pure)", preamble + "pyz = PYZ(a.pure)")
        )
        PY
      ''}
      PYINSTALLER_CONFIG_DIR="$PWD/.pyinstaller" PATH="${lib.optionalString stdenv.hostPlatform.isDarwin "/usr/bin:"}$PATH" pyinstaller \
        --distpath "$PWD/dist" \
        --workpath "$PWD/build" \
        "$PWD/htmlpdf.spec"
      runHook postBuild
    '';

    installPhase = ''
      runHook preInstall
      install -Dm755 "$PWD/dist/htmlpdf" "$out/bin/htmlpdf"
      runHook postInstall
    '';

    doInstallCheck = true;
    installCheckPhase = ''
      runHook preInstallCheck
      test -x "$out/bin/htmlpdf"
      file "$out/bin/htmlpdf" | grep -E 'Mach-O|ELF'
      "$out/bin/htmlpdf" --help >/dev/null

      # Every package module and asset must be inside the one-file archive.
      pyi-archive_viewer -l -r "$out/bin/htmlpdf" > archive-contents.txt
      for entry in htmlpdf htmlpdf.cli src/htmlpdf/assets/*; do
        entry="''${entry#src/}"
        if ! grep -qF ", '$entry'" archive-contents.txt; then
          echo "htmlpdf: the executable is missing $entry" >&2
          exit 1
        fi
      done

      # Run the frozen Markdown path without a browser, so the check also holds in
      # a Linux sandbox. Staging the page reads the packaged fonts and CSS through
      # importlib.resources; a stand-in browser that exits at once then stops the
      # conversion, and --keep-html leaves the staged page to inspect.
      mkdir install-check
      cp tests/fixtures/guide.md install-check/guide.md
      if "$out/bin/htmlpdf" convert install-check/guide.md --chrome "$(type -P false)" --keep-html 2>install-check/stderr.txt; then
        echo "htmlpdf: conversion succeeded with a browser that cannot start" >&2
        exit 1
      fi
      if ! grep -qF 'could not start Chrome' install-check/stderr.txt; then
        cat install-check/stderr.txt >&2
        exit 1
      fi
      staged=(install-check/.guide.htmlpdf-*.html)
      grep -qF 'url(data:font/woff2;base64,' "''${staged[0]}"
      grep -qF '<pre class="mermaid">' "''${staged[0]}"
      runHook postInstallCheck
    '';

    dontStrip = true;
    # PyInstaller preserves build-machine source locations in bytecode. Remove
    # them so its self-contained executable cannot retain the Python build graph.
    disallowedRequisites = pythonBuildInputs;
    removeReferencesTo = pythonBuildInputs;

    meta = {
      description = "Convert HTML or Markdown documents to print-ready PDFs";
      mainProgram = "htmlpdf";
      platforms = lib.platforms.linux ++ lib.platforms.darwin;
    };
  }
