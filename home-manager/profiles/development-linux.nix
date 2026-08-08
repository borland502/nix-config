# Development-focused home-manager profile
{
  pkgs,
  lib,
  isWsl ? false,
  ...
}: let
  devPackages = with pkgs;
    [
      # Build tools
      gnumake
      cmake

      # Languages and runtimes
      nodejs

      # Cloud tools
      kubectl
    ]
    ++ lib.optionals (!isWsl) [pkgs.vscode];

  availablePackages = lib.filter (pkg: lib.meta.availableOn pkgs.stdenv.hostPlatform pkg) devPackages;
in {
  # Development tools
  home.packages = availablePackages;

  # Note: Git configuration moved to common.nix to avoid duplication
  # Note: Common dev tools (jq, yq, ripgrep, fd, bat) moved to common.nix

  # VS Code configuration
  programs.vscode = lib.mkIf (!isWsl && pkgs ? vscode) {
    enable = true;
    profiles.default.extensions =
      (with pkgs.vscode-extensions; [
        # Python development
        ms-python.python

        # Git integration
        eamodio.gitlens

        # Themes and appearance
        pkief.material-icon-theme

        # Web development
        bradlc.vscode-tailwindcss
        esbenp.prettier-vscode
        ritwickdey.liveserver

        # Remote / container development
        ms-vscode-remote.remote-containers

        # Config formats
        tamasfe.even-better-toml
      ])
      # Not in nixpkgs' vscode-extensions set, so pulled from the marketplace.
      ++ pkgs.vscode-utils.extensionsFromVscodeMarketplace [
        {
          # Sublime Text Keymap and Settings Importer
          name = "sublime-keybindings";
          publisher = "ms-vscode";
          version = "4.1.10";
          sha256 = "sha256-XlogenuBmP+tE18VLH4lUSpOq/7d022n8HgXnKjY3n0=";
        }
      ];
    # Left deliberately unmanaged (installed from the marketplace instead):
    #   amazonwebservices.aws-toolkit-vscode — not packaged in nixpkgs
    #     (only amazonwebservices.amazon-q-vscode is)
    #   anthropic.claude-code — self-updating; nixpkgs lags the marketplace
    #     build and the pinned copy is immediately marked obsolete by VS Code
  };
}
