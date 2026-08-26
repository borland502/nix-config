# VS Code profiles, shared by every host that installs VS Code.
#
# Imported by home.nix (Linux) and home-darwin.nix. NOT imported by
# home-wsl.nix: WSL does not install VS Code at all — the editor runs on the
# Windows side and only its server needs settings, which home-wsl.nix writes
# directly to ~/.vscode-server/{data/User,data/Machine}/settings.json. There is
# no profile directory there to manage.
#
# common.nix owns the parts that are the same everywhere `programs.vscode` is
# enabled at all (enable, the shared userSettings, nix-ide on the default
# profile); this module owns the profile *layout* on top of that.
{
  pkgs,
  lib,
  isWsl ? false,
  ...
}: let
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

  # Git worktree management: not in nixpkgs' vscode-extensions set, so pinned
  # from the marketplace like sublimeKeymap above. jackiotyu.git-worktree-manager
  # is the most-installed genuine worktree manager (30.3k installs, 5.0/8
  # ratings, last published 2026-08-11); GitWorktrees.git-worktrees is second at
  # 22.6k. letmaik.git-tree-compare outranks both on a "worktree" search with
  # 253k installs but is unrelated — it diffs the working tree against a branch
  # and manages no worktrees.
  gitWorktreeManager = pkgs.vscode-utils.extensionsFromVscodeMarketplace [
    {
      name = "git-worktree-manager";
      publisher = "jackiotyu";
      version = "3.27.0";
      sha256 = "sha256-L1Hpv/d8lRNCEhy64s4G3l1KK9u7xV5pGqNEECDKwHc=";
    }
  ];

  # The worktree extension actually in use on the default profile. Declared
  # separately from gitWorktreeManager above so the language profiles keep
  # jackiotyu and the default profile gets this one; previously the default
  # profile had no worktree extension at all and this was hand-installed from
  # the marketplace, which does not survive a switch once any non-default
  # profile is declared (see the note at the bottom of this file).
  gitWorktrees = pkgs.vscode-utils.extensionsFromVscodeMarketplace [
    {
      name = "git-worktrees";
      publisher = "GitWorktrees";
      version = "2.16.0";
      sha256 = "sha256-wCGXBsQwfdCCZfuSFO9hPKWVbJyXgI/5wHuC2F/noD8=";
    }
  ];

  # Shell-script extensions that nixpkgs' vscode-extensions set does not carry,
  # pinned from the marketplace like sublimeKeymap above. Marketplace install
  # counts on 2026-08-26: bash-debug 1.38M (the only maintained-enough bash
  # debugger and the 4th most-installed shell extension overall), shellman
  # 409k, shebang-snippets 221k. The three nixpkgs-packaged ones the Shell
  # profile also uses outrank all of these — shell-format 2.68M, shellcheck
  # 2.24M, bash-ide 1.19M.
  shellMarketplace = pkgs.vscode-utils.extensionsFromVscodeMarketplace [
    {
      name = "bash-debug";
      publisher = "rogalmic";
      version = "0.3.9";
      sha256 = "sha256-f8FUZCvz/PonqQP9RCNbyQLZPnN5Oce0Eezm/hD19Fg=";
    }
    {
      # Snippet library for the argument parsing / getopts / trap boilerplate.
      name = "shellman";
      publisher = "remisa";
      version = "5.7.0";
      sha256 = "sha256-ggRe7r1h11TUDzyXCZbaaoI8g3YKdZR0iBLI/0nmiPs=";
    }
    {
      name = "shebang-snippets";
      publisher = "rpinski";
      version = "1.1.0";
      sha256 = "sha256-biv0Ccdfwd68hsY8UwLc+0vAnfmV+Ngnqie3QOo6VBc=";
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
    ++ sublimeKeymap
    ++ gitWorktreeManager;

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

    # POSIX sh / bash scripting. mkhl.direnv is in here rather than in
    # languageProfileBase because this is the profile used on repos like this
    # one, where every script is entered through a .envrc.
    Shell = {
      extensions =
        languageProfileBase
        ++ (with pkgs.vscode-extensions; [
          timonwong.shellcheck
          foxundermoon.shell-format
          mads-hartmann.bash-ide-vscode
          jetmartin.bats
          mkhl.direnv
        ])
        ++ shellMarketplace;
      userSettings =
        baseUserSettings
        // {
          # All three of these ship a bundled binary or expect one on PATH.
          # Point them at the store copies common.nix already installs so the
          # editor and `task lint:sh` cannot disagree about versions.
          "shellcheck.executablePath" = "${pkgs.shellcheck}/bin/shellcheck";
          "shellcheck.enableQuickFix" = true;
          "shellcheck.run" = "onType";
          "shellformat.path" = "${pkgs.shfmt}/bin/shfmt";
          # -i 0 (tab indent) matches `task fmt:sh` and CI; without it the
          # extension formats with spaces and every save fights the linter.
          "shellformat.flag" = "-i 0";
          "bashIde.shellcheckPath" = "${pkgs.shellcheck}/bin/shellcheck";
          "bashIde.shfmt.path" = "${pkgs.shfmt}/bin/shfmt";

          # bash-ide also registers a shellscript formatter, so name the one
          # that should win — otherwise formatOnSave prompts on every save.
          "[shellscript]" = {
            "editor.defaultFormatter" = "foxundermoon.shell-format";
          };

          # shellcheck's default ignorePatterns already skips .zsh/.zshrc (it
          # cannot parse zsh); add the chezmoi-prefixed copies of those, which
          # the shared files.associations maps to shellscript.
          "shellcheck.ignorePatterns" = {
            "**/dot_zshrc" = true;
            "**/dot_zshenv" = true;
            "**/dot_zprofile" = true;
            "**/*.zsh.tmpl" = true;
          };

          # bash-debug takes every path from the launch config and defaults
          # them to FHS locations (/usr/local/bin/bashdb, /usr/bin/cat, ...)
          # that do not exist on NixOS, so F5 fails out of the box. VS Code
          # honours a "launch" key in user settings, which gives the profile a
          # working global config without a launch.json in every repo.
          "launch" = {
            version = "0.2.0";
            configurations = [
              {
                type = "bashdb";
                request = "launch";
                name = "Bash-Debug (current file)";
                program = "\${file}";
                cwd = "\${workspaceFolder}";
                pathBash = "${pkgs.bash}/bin/bash";
                pathBashdb = "${pkgs.bashdb}/bin/bashdb";
                pathBashdbLib = "${pkgs.bashdb}/share/bashdb";
                pathCat = "${pkgs.coreutils}/bin/cat";
                pathMkfifo = "${pkgs.coreutils}/bin/mkfifo";
                pathPkill = "${pkgs.procps}/bin/pkill";
              }
            ];
          };
        };
    };
  };
in {
  # Stylix themes only the profiles it is told about; without this the language
  # profiles get no Stylix theme extension and workbench.colorTheme = "Stylix"
  # resolves to nothing.
  stylix.targets.vscode.profileNames =
    lib.mkIf vscodeEnabled (["default"] ++ builtins.attrNames languageProfiles);

  # NOTE: declaring any profile other than `default` flips home-manager's
  # `programs.vscode.mutableExtensionsDir` to false, which makes
  # ~/.vscode/extensions a read-only Nix symlink. Extensions installed by hand
  # from the marketplace no longer survive a switch — see the note at the
  # bottom of this block.
  programs.vscode = lib.mkIf vscodeEnabled {
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
          ++ sublimeKeymap
          ++ gitWorktrees;
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
