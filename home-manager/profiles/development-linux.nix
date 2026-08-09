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

  vscodeEnabled = !isWsl && pkgs ? vscode;

  # VS Code profiles do NOT inherit the default profile's settings — a profile
  # without its own settings.json starts from stock VS Code. Re-use the shared
  # settings so the language profiles keep the Stylix theme, fonts, and zsh
  # terminal instead of looking like a fresh install. common.nix applies the
  # same set to the default profile.
  baseUserSettings = import ../lib/code-editor-user-settings.nix {inherit pkgs;};

  # Sublime keymap: not in nixpkgs' vscode-extensions set, so pinned from the
  # marketplace. Shared by every profile so the keybindings follow the user.
  sublimeKeymap = pkgs.vscode-utils.extensionsFromVscodeMarketplace [
    {
      name = "sublime-keybindings";
      publisher = "ms-vscode";
      version = "4.1.10";
      sha256 = "sha256-XlogenuBmP+tE18VLH4lUSpOq/7d022n8HgXnKjY3n0=";
    }
  ];

  # Baseline every *language* profile gets on top of its language tooling.
  # Deliberately not applied to the default profile, which stays as-is.
  languageProfileBase =
    (with pkgs.vscode-extensions; [
      mhutchie.git-graph
      pkief.material-icon-theme
      usernamehw.errorlens
      editorconfig.editorconfig
      streetsidesoftware.code-spell-checker
      tamasfe.even-better-toml
      ms-azuretools.vscode-docker
      ms-vscode-remote.remote-containers
      github.vscode-pull-request-github
    ])
    ++ sublimeKeymap;

  # One VS Code profile per language stack. The attribute name is both the
  # display name in the profile picker and the directory under
  # ~/.config/Code/User/profiles/, so keep it short and space-free.
  languageProfiles = {
    Go = {
      extensions =
        languageProfileBase
        ++ (with pkgs.vscode-extensions; [
          golang.go
        ]);
      userSettings =
        baseUserSettings
        // {
          # go.alternateTools in the shared settings already points the
          # toolchain at the Nix store copies, so never let the extension try
          # to `go install` its own.
          "go.toolsManagement.autoUpdate" = false;
          "[go]" = {
            "editor.defaultFormatter" = "golang.go";
            "editor.codeActionsOnSave" = {
              "source.organizeImports" = "explicit";
            };
          };
        };
    };

    Python = {
      extensions =
        languageProfileBase
        ++ (with pkgs.vscode-extensions; [
          ms-python.python
          ms-python.vscode-pylance
          ms-python.debugpy
          ms-python.mypy-type-checker
          charliermarsh.ruff
          ms-toolsai.jupyter
        ]);
      userSettings =
        baseUserSettings
        // {
          "python.defaultInterpreterPath" = "${pkgs.python3}/bin/python3";
          "python.analysis.typeCheckingMode" = "basic";
          "[python]" = {
            "editor.defaultFormatter" = "charliermarsh.ruff";
            "editor.codeActionsOnSave" = {
              "source.organizeImports.ruff" = "explicit";
            };
          };
        };
    };

    # Java + Spring Boot.
    Java = {
      extensions =
        languageProfileBase
        ++ (with pkgs.vscode-extensions; [
          redhat.java
          redhat.vscode-xml
          redhat.vscode-yaml
          vscjava.vscode-java-debug
          vscjava.vscode-java-test
          vscjava.vscode-java-dependency
          vscjava.vscode-maven
          vscjava.vscode-gradle
          vscjava.vscode-spring-initializr
        ])
        # The Spring Boot halves of the usual "Spring Boot Extension Pack" are
        # not in nixpkgs' vscode-extensions set.
        ++ pkgs.vscode-utils.extensionsFromVscodeMarketplace [
          {
            # Spring Boot Tools (language server for .properties/.yml + @-annotations)
            name = "vscode-spring-boot";
            publisher = "vmware";
            version = "2.4.2026080800";
            sha256 = "sha256-1wW2MaHt8JtXJA8UzJ7cjcA/7FWX8Sv7M0fz1XXDagI=";
          }
          {
            name = "vscode-spring-boot-dashboard";
            publisher = "vscjava";
            version = "0.14.2025041702";
            sha256 = "sha256-gtEn4UD5Ft+JJqHcz/Eh4t2njOZJg2NRVtfD8Hy4LT8=";
          }
        ];
      userSettings =
        baseUserSettings
        // {
          # No JDK is on PATH in this config, and jdt.ls will not start without
          # one. Point it at the Nix JDK directly rather than adding a ~300 MB
          # java/javac to every host's user profile.
          "java.jdt.ls.java.home" = pkgs.jdk.home;
          "java.import.gradle.java.home" = pkgs.jdk.home;
          "java.configuration.runtimes" = [
            {
              name = "JavaSE-21";
              path = pkgs.jdk.home;
              default = true;
            }
          ];
          "[java]" = {
            "editor.defaultFormatter" = "redhat.java";
          };
        };
    };

    NodeJS = {
      extensions =
        languageProfileBase
        ++ (with pkgs.vscode-extensions; [
          dbaeumer.vscode-eslint
          esbenp.prettier-vscode
          bradlc.vscode-tailwindcss
          christian-kohler.npm-intellisense
          christian-kohler.path-intellisense
          wix.vscode-import-cost
          yoavbls.pretty-ts-errors
        ])
        ++ pkgs.vscode-utils.extensionsFromVscodeMarketplace [
          {
            name = "vscode-jest";
            publisher = "orta";
            version = "6.4.4";
            sha256 = "sha256-aAS52nwAtoMxrFoWD2Ow4LSKgCiBEZvAP6H2xYXMUzY=";
          }
          {
            name = "es7-react-js-snippets";
            publisher = "dsznajder";
            version = "4.4.3";
            sha256 = "sha256-QF950JhvVIathAygva3wwUOzBLjBm7HE3Sgcp7f20Pc=";
          }
        ];
      userSettings =
        baseUserSettings
        // {
          "eslint.useFlatConfig" = true;
          "javascript.updateImportsOnFileMove.enabled" = "always";
          "typescript.updateImportsOnFileMove.enabled" = "always";
          "[javascript]" = {
            "editor.defaultFormatter" = "esbenp.prettier-vscode";
          };
          "[javascriptreact]" = {
            "editor.defaultFormatter" = "esbenp.prettier-vscode";
          };
          "[json]" = {
            "editor.defaultFormatter" = "esbenp.prettier-vscode";
          };
          "[jsonc]" = {
            "editor.defaultFormatter" = "esbenp.prettier-vscode";
          };
          # formatOnSave stays off for TS/TSX (the shared settings turn it off
          # deliberately); this only names the formatter for an explicit
          # "Format Document".
          "[typescript]" = {
            "editor.formatOnSave" = false;
            "editor.defaultFormatter" = "esbenp.prettier-vscode";
          };
          "[typescriptreact]" = {
            "editor.formatOnSave" = false;
            "editor.defaultFormatter" = "esbenp.prettier-vscode";
          };
        };
    };
  };
in {
  # Development tools
  home.packages = availablePackages;

  # Note: Git configuration moved to common.nix to avoid duplication
  # Note: Common dev tools (jq, yq, ripgrep, fd, bat) moved to common.nix

  # Stylix themes only the profiles it is told about; without this the language
  # profiles get no Stylix theme extension and workbench.colorTheme = "Stylix"
  # resolves to nothing.
  stylix.targets.vscode.profileNames =
    lib.mkIf vscodeEnabled (["default"] ++ builtins.attrNames languageProfiles);

  # VS Code configuration
  #
  # NOTE: declaring any profile other than `default` flips home-manager's
  # `programs.vscode.mutableExtensionsDir` to false, which makes
  # ~/.vscode/extensions a read-only Nix symlink. Extensions installed by hand
  # from the marketplace no longer survive a switch — see the note at the
  # bottom of this block.
  programs.vscode = lib.mkIf vscodeEnabled {
    enable = true;
    profiles =
      {
        # Kept deliberately lean: Git Graph, the Material icon theme, and
        # Tailwind IntelliSense now live only in the language profiles that
        # actually need them.
        default.extensions =
          (with pkgs.vscode-extensions; [
            # Python development
            ms-python.python

            # Web development
            esbenp.prettier-vscode
            ritwickdey.liveserver

            # Remote / container development
            ms-vscode-remote.remote-containers

            # Config formats
            tamasfe.even-better-toml
          ])
          ++ sublimeKeymap;
      }
      // languageProfiles;
    # Never declared here, and no longer present after a switch either: the
    # language profiles above make ~/.vscode/extensions an immutable Nix
    # symlink, so hand-installed marketplace extensions do not survive.
    #   amazonwebservices.aws-toolkit-vscode — dropped on purpose; not packaged
    #     in nixpkgs anyway (only amazonwebservices.amazon-q-vscode is)
    #   anthropic.claude-code — self-updating; nixpkgs lags the marketplace
    #     build and a pinned copy is immediately marked obsolete by VS Code.
    #     Reinstall from the marketplace after activation if it is wanted.
  };
}
