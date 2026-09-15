# htmlpdf — Python CLI packaged for Nix.
{
  lib,
  buildPythonApplication,
  poetry-core,
  playwright,
  pymupdf,
  markdown-it-py,
  mdit-py-plugins,
  pygments,
}:
buildPythonApplication {
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

  pyproject = true;
  build-system = [poetry-core];
  dependencies = [
    playwright
    pymupdf
    markdown-it-py
    mdit-py-plugins
    pygments
  ];

  pythonImportsCheck = ["htmlpdf"];

  meta = {
    description = "Convert Markdown documents to PDF files";
    mainProgram = "htmlpdf";
    platforms = lib.platforms.linux ++ lib.platforms.darwin;
  };
}
