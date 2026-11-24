{pkgs}:
pkgs.mkShell {
  packages = with pkgs; [
    actionlint
    chezmoi
    alejandra
    deadnix
    fd
    git
    gitleaks
    go-task
    jq
    markdownlint-cli2
    python3
    ripgrep
    ruff
    shellcheck
    shfmt
    statix
    taplo
    yamllint
    zsh
    zstd
  ];
}
