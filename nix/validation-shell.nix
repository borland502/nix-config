{pkgs}:
pkgs.mkShell {
  packages = with pkgs; [
    actionlint
    age
    chezmoi
    alejandra
    deadnix
    fd
    git
    gitleaks
    go-task
    inetutils # hostname for Task host detection in an isolated environment
    jq
    markdownlint-cli2
    nix
    python3
    ripgrep
    ruff
    shellcheck
    shfmt
    sops
    statix
    taplo
    yamllint
    yq-go
    zsh
    zstd
  ];
}
