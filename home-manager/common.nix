# Common home-manager configuration shared between Linux and Darwin
{
  config,
  pkgs,
  lib,
  ...
}: let
  inherit (config.nixConfig.host) preferSystemPython;
  availableOnHost = pkg: lib.meta.availableOn pkgs.stdenv.hostPlatform pkg;
  inherit (config.home) homeDirectory;
  xdgBinHome = "${homeDirectory}/.local/bin";
  xdgCacheHome = "${homeDirectory}/.cache";
  xdgConfigHome = "${homeDirectory}/.config";
  xdgDataHome = "${homeDirectory}/.local/share";
  xdgLibHome = "${homeDirectory}/.local/lib";
  xdgStateHome = "${homeDirectory}/.local/state";

  xdgDirectories = [
    xdgBinHome
    xdgCacheHome
    xdgConfigHome
    xdgDataHome
    xdgLibHome
    xdgStateHome
  ];
  vividTheme = import ./lib/vivid-theme.nix {inherit lib pkgs;};
  # Bake LS_COLORS at build time from the repo's monokai palette so ls/eza/tree
  # share the rest of the theme. Read at shell init via $(cat ...) — kernel
  # caches the /nix/store file so the cost is effectively zero.
  lsColors = pkgs.runCommand "ls-colors" {} ''
    ${pkgs.vivid}/bin/vivid generate ${vividTheme} > $out
  '';
  awsSamCliPatched = pkgs.aws-sam-cli.overridePythonAttrs (old: {
    # nixpkgs currently wires newer click and aws-lambda-builders versions than
    # the wheel metadata expects. Keep the package Nix-managed and skip the
    # strict runtime metadata check until upstream packaging catches up.
    doCheck = false;
    dontCheckRuntimeDeps = true;
    pythonRelaxDeps = (old.pythonRelaxDeps or []) ++ ["click"];
  });
  direnvPatched =
    if pkgs.stdenv.isDarwin
    then
      pkgs.direnv.overrideAttrs (old: {
        env = (old.env or {}) // {CGO_ENABLED = "1";};
        doCheck = false;
      })
    else pkgs.direnv;
  # pipx 1.8.0 has test failures in nixos-26.05 due to PEP 508 spacing
  # differences in the packaging library — skip tests, the package itself works.
  pipxPatched = pkgs.pipx.overridePythonAttrs (_old: {
    doCheck = false;
  });
  commonPackages = with pkgs; [
    # Version control
    git
    gh
    gh-dash # TUI dashboard for GitHub PRs/issues
    lazygit # TUI for fast hunk-level staging, diff/log/branch navigation
    delta # syntax-highlighting pager for git diffs (wired as core.pager below)

    # Network
    curl
    wget
    nmap # port/service scanning and NSE scripts; also the `ncat`/`ndiff` tools
    prettyping # readable ping; note the shell aliases `ping` to it, so a script
    # that needs machine-parsable output must call /bin/ping explicitly
    arp-scan # L2 sweep with an OUI vendor database — finds hosts that drop ICMP,
    # which is most IoT gear and the main blind spot of a ping sweep
    avahi # mDNS/DNS-SD browsing (avahi-browse); how Google/LIFX/Hue/Nest
    # actually announce human-readable names on a home LAN

    # Sender half of Wake-on-LAN; the `wake` helper shells out to it. Shared
    # rather than Linux-only: nixpkgs marks it platforms.all, and a magic packet
    # is most useful from the laptop that finds a host asleep. Unprivileged — it
    # broadcasts UDP/9 rather than forging an ethernet frame, hence this and not
    # etherwake.
    wakeonlan

    # Tools built from this repo (pkgs/), delivered through the
    # localPackagesOverlay in flake.nix. These replace the hand-installed copies
    # that used to live in ~/.local/bin via chezmoi or `task deploy`.
    #
    # Two of the four packages are deliberately absent from every profile:
    #   * technitium-dash is host-gated to ellone, the DNS wall panel. ellone is
    #     not a flake or chezmoi host (aarch64 Debian, no Nix), so there is no
    #     module to gate it in — it ships as a zipapp via `task deploy:ellone:dash`
    #     and belongs on no other machine.
    #   * shop-scan is a ~100 MB bun binary that drives a browser, wanted rarely.
    # Both stay registered in pkgs/default.nix, so `nix run .#<tool>` still works
    # anywhere without putting them in the profile.
    gopwgen
    htmlpdf
    wordgen

    # Build tools
    gcc
    pkg-config
    go-task
    # maven is shared, but the JDK it runs on is not: `jdk` lives in
    # home-darwin.nix, since only the Mac does Java work today. Nix's maven
    # wrapper carries its own JDK reference, so `mvn` works on the Linux and
    # WSL hosts even with no `java` on PATH there.
    maven

    # Go toolchain
    go
    gopls
    govulncheck
    delve

    # Python
    # The interpreter is appended to home.packages rather than listed here, so
    # that preferSystemPython can leave it out. pipx and uv are unaffected:
    # each carries its own python in its own closure and neither installs a
    # `python3` of its own into the profile.
    pipxPatched
    uv

    # JavaScript
    bun

    # Cloud & AWS
    awscli2
    awslogs
    awsSamCliPatched
    # checkov removed 2026-08-13: it was the sole path to arrow-cpp
    # (checkov -> igraph -> plotly -> pyarrow -> arrow-cpp), whose install-check
    # suite fails on aarch64-darwin. nixpkgs excludes the known-broken
    # TestAzuriteGeneric.Empty (apache/arrow#41505) only for isDarwin &&
    # isx86_64, so the test runs here, and with sandbox=false the Azurite
    # emulator's telemetry stalls its startup past the test's connect timeout.
    # Nothing in this repo invoked checkov; re-add it with an arrow-cpp overlay
    # widening that exclusion if it is ever needed again.

    # Containers & process management
    docker_29
    docker-buildx
    docker-compose
    overmind

    # Shell enhancement
    bat
    eza
    fzf
    fd
    overmind
    ripgrep
    sd
    zoxide
    direnvPatched

    # Data processing
    jq
    yq-go
    dasel
    gron # flatten JSON into greppable assignment lines (and back)

    # Nix tooling
    alejandra
    statix
    deadnix
    nixd

    # Linters
    markdownlint-cli2
    ruff
    shellcheck
    shfmt
    yamllint
    taplo

    # AI & agent tools
    # claude-code and github-copilot-cli intentionally omitted — they install
    # off nixpkgs via ~/.local/bin/update-agent-clis, each using its vendor's
    # native self-updating installer into ~/.local (run on chezmoi apply and
    # `task agents:update`). nixpkgs lags these CLIs by weeks and a read-only
    # store copy cannot self-update, freezing the Copilot CLI on a build that
    # rejects current subagent models. See flake.nix / AGENTS.md.
    opsAgent

    # Secret management
    age
    sops
    # Interpreter for `keepass set-attr`. keepassxc-cli cannot write custom
    # (Advanced-tab) attributes and pykeepass cannot open a vault keyed with a
    # YubiKey, so the two are paired: pykeepass builds a one-entry database and
    # keepassxc-cli merges it in. Named rather than added to `python3` because
    # nixpkgs' python3 is deliberately kept off $PATH here (see below).
    keepassPython
    # `task lint:secrets` runs gitleaks, so without it here the full `task lint`
    # chain exits 127 on every local run — CI passed only because the workflow
    # installs it explicitly via `nix shell nixpkgs#gitleaks`.
    gitleaks

    # Dotfiles & file sync
    chezmoi
    unison
    # Backing store for sync-to-gdrive and its scheduled timer/agent
    # (home-manager/modules/gdrive-sync.nix). Previously left to the distro
    # package on Linux and Homebrew on darwin, which made the scheduled job's
    # dependency implicit and unversioned.
    rclone

    # Productivity & content
    glow
    gum
    tealdeer
    scrcpy
    # Backs the always-on defuddle skill, which instructs agents to use it
    # instead of WebFetch for article-shaped pages. It was never installed, so
    # every invocation died on command-not-found and cost a recovery turn.
    defuddle

    # Diagrams — Confluence architecture/sequence visuals
    d2 # text -> layout-aware SVG; faster than hand-authored SVG for control-plane diagrams
    resvg # SVG -> PNG, consistent rendering for quick visual QA

    # Basic utilities
    file
    which
    tree
    rsync
    ncdu

    # Compression
    unzip
    p7zip
    zstd

    # System monitoring
    btop
    lsof
  ];
  # ops-agent's model loop runs through the user's `claude` CLI (subscription
  # OAuth) — stdlib-only Python, no anthropic SDK / API key needed.
  keepassPython = pkgs.writeShellScriptBin "keepass-python" ''
    exec ${pkgs.python3.withPackages (ps: [ps.pykeepass])}/bin/python3 "$@"
  '';
  agentToolsLibraries = import ./lib/agent-tools-libraries.nix {inherit lib;};
  agentToolsLib = agentToolsLibraries.python;
  opsAgent = pkgs.writeShellScriptBin "ops-agent" ''
    export AGENT_TOOLS_LIB="''${AGENT_TOOLS_LIB:-${agentToolsLib}}"
    exec ${pkgs.python3}/bin/python ${../ai-tools/scripts/ops-agent.py} "$@"
  '';
in {
  nixpkgs.config = {
    allowUnfree = true;
    allowUnfreePredicate = _: true;
  };

  # Shared imports
  imports = [
    ./modules/host-options.nix
    ./zsh.nix
    ./starship.nix
    ./modules/sops.nix
    ./modules/sudo-askpass.nix
    ./modules/agent-code-tools.nix
    ./modules/agent-tooling.nix
    ./modules/credential-services.nix
    ./modules/desktop-defaults.nix
  ];

  xdg = {
    enable = true;
    cacheHome = xdgCacheHome;
    configHome = xdgConfigHome;
    dataHome = xdgDataHome;
    stateHome = xdgStateHome;
  };

  home = {
    # Ensure user-local binaries are found regardless of shell
    sessionPath = lib.mkBefore [xdgBinHome];

    sessionVariables = {
      GOBIN = xdgBinHome;
      XDG_BIN_HOME = xdgBinHome;
      XDG_CACHE_HOME = xdgCacheHome;
      XDG_CONFIG_HOME = xdgConfigHome;
      XDG_DATA_HOME = xdgDataHome;
      XDG_LIB_HOME = xdgLibHome;
      XDG_STATE_HOME = xdgStateHome;
      COPILOT_CACHE_HOME = "${xdgCacheHome}/copilot/runtime";
      LS_COLORS = "$(${pkgs.coreutils}/bin/cat ${lsColors})";
    };

    activation = {
      ensureXdgDirectories = lib.hm.dag.entryAfter ["writeBoundary"] ''
        ${pkgs.coreutils}/bin/mkdir -p ${lib.concatMapStringsSep " " lib.escapeShellArg xdgDirectories}
      '';

      # Configure chezmoi to use the nix-config repo as its source of truth.
      # The repo path is recorded to ~/.local/state/chezmoi/nix-config-dir by
      # the _record-nix-config-dir task whenever any switch task runs, so this
      # wiring survives the repo being renamed or moved.
      configureChezmoi = lib.hm.dag.entryAfter ["ensureXdgDirectories"] ''
        _cm_dir_file="${xdgStateHome}/chezmoi/nix-config-dir"
        _cm_age_key="${homeDirectory}/.config/sops/age/keys.txt"
        if [ -f "$_cm_dir_file" ]; then
          _cm_nix_dir=$(${pkgs.coreutils}/bin/cat "$_cm_dir_file")
          _cm_source="$_cm_nix_dir/chezmoi"
          if [ -d "$_cm_source" ]; then
            ${pkgs.coreutils}/bin/mkdir -p "${xdgConfigHome}/chezmoi"
            {
              ${pkgs.coreutils}/bin/printf 'sourceDir = "%s"\n' "$_cm_source"
              if [ -f "$_cm_age_key" ]; then
                ${pkgs.coreutils}/bin/printf 'encryption = "age"\n'
                ${pkgs.coreutils}/bin/printf '\n[age]\n'
                ${pkgs.coreutils}/bin/printf '  identity = "%s"\n' "$_cm_age_key"
                # recipient enables encryption (chezmoi add --encrypt); identity
                # alone only decrypts. Derived from the same key so encrypted
                # source files (e.g. work-repo agent directives) round-trip on
                # any host holding the key.
                _cm_age_recipient=$(${pkgs.age}/bin/age-keygen -y "$_cm_age_key" 2>/dev/null | ${pkgs.coreutils}/bin/head -n1 || true)
                if [ -n "$_cm_age_recipient" ]; then
                  ${pkgs.coreutils}/bin/printf '  recipient = "%s"\n' "$_cm_age_recipient"
                fi
              fi
            } > "${xdgConfigHome}/chezmoi/chezmoi.toml"
          fi
        fi
      '';

      setDefaultShell = lib.hm.dag.entryAfter ["writeBoundary"] ''
        _zsh="${homeDirectory}/.nix-profile/bin/zsh"
        _username="${config.home.username}"
        if [ -x "$_zsh" ]; then
          if ! ${pkgs.gnugrep}/bin/grep -qxF "$_zsh" /etc/shells 2>/dev/null; then
            ${pkgs.coreutils}/bin/printf '%s\n' "$_zsh" | sudo -n tee -a /etc/shells >/dev/null 2>&1 || true
          fi
          # -n: non-interactive; silently skipped if sudo requires a password.
          # The taskfile's home-switch/upgrade tasks run the same command
          # interactively as a fallback.
          sudo -n /usr/sbin/usermod -s "$_zsh" "$_username" 2>/dev/null || true
        fi
      '';
    };

    # Common packages shared across Linux, WSL, and macOS.
    # Installing nixpkgs' python3 puts `python3` in ~/.nix-profile/bin, which
    # precedes /usr/bin on $PATH and so becomes the interpreter that every
    # `#!/usr/bin/env python3` on the machine resolves to — including scripts
    # the distro installed, whose modules live in the distro python's
    # site-packages and are invisible to the nix one. That is not a version
    # skew that can be patched around: the two interpreters have separate
    # module paths, and a distro package's C extensions are built against its
    # own python ABI.
    #
    # So nixpkgs' python3 is only worth shadowing the system one when it is
    # actually newer. Where the distro is level or ahead, preferSystemPython
    # leaves it out of the profile and /usr/bin/python3 wins. Nothing here
    # loses access to it: the ops-agent and kion-aws-refresh wrappers below
    # invoke ${pkgs.python3} by absolute store path, and pipx, uv and yamllint
    # bring their own — this only decides who owns the bare `python3` name.
    packages =
      lib.filter availableOnHost commonPackages
      ++ lib.optional (!preferSystemPython) pkgs.python3;

    # Common home-manager settings
    stateVersion = "26.05";
  };

  programs = {
    # Common Git configuration
    git = {
      enable = true;
      # Global excludes (~/.config/git/ignore). ".worktrees/" is here so the
      # worktree parent directory is ignored in every repo, not just the ones
      # that happen to list it: ai-tools/skills/git-worktrees refuses a
      # repository-local worktree path that `git check-ignore` does not already
      # confirm, and the git-worktree-manager templates in
      # lib/code-editor-user-settings.nix propose that same path. Without this
      # the two agree only in repos whose own .gitignore covers it.
      ignores = [
        "**/.claude/settings.local.json"
        ".worktrees/"
      ];
      settings = {
        user = {
          name = "jhettenh";
          email = "jhettenh@gmail.com";
        };
        init.defaultBranch = "main";
        core = {
          editor = "vim";
          pager = "delta";
          # Global hook directory (see xdg.configFile."git/hooks/commit-msg"
          # below). Applies the agent-attribution stripper to every repo without
          # committing anything to those repos -- needed where a project's own
          # hooks cannot be modified. A repo that sets its own core.hooksPath
          # (husky et al) overrides this -- nix-config included, which is why it
          # ships .githooks/commit-msg as a shim back to the same script; a repo
          # relying on plain .git/hooks does not run them while this is set.
          hooksPath = "${xdgConfigHome}/git/hooks";
        };
        pull.rebase = false;
        # delta: syntax-highlighted diffs/pager. `delta` package added above.
        interactive.diffFilter = "delta --color-only";
        delta = {
          navigate = true; # n/N to move between diff hunks
          line-numbers = true;
        };
        merge.conflictStyle = "zdiff3";
        diff.colorMoved = "default";
        credential."https://github.com".helper = "!/usr/bin/env gh auth git-credential";
        credential."https://gist.github.com".helper = "!/usr/bin/env gh auth git-credential";
      };
    };

    # Common program configurations
    bat.enable = true;
    tmux.enable = true;
    neovim.enable = true;

    # btop/fzf/lazygit are enabled as program modules, not just installed as
    # packages, so Stylix has somewhere to write the palette: its targets work
    # by setting programs.<tool>.settings, which Home Manager only renders to
    # disk when the module itself is enabled. Installed as bare packages they
    # kept running with stock themes while the Stylix targets read as enabled.
    btop.enable = true;
    lazygit.enable = true;

    fzf = {
      enable = true;
      # zsh.nix already does `source <(fzf --zsh)` behind a command -v guard;
      # letting the module add its own integration would bind Ctrl-R/Ctrl-T
      # twice. Theming is unaffected — the palette rides on FZF_DEFAULT_OPTS
      # via home.sessionVariables, which is independent of this option.
      enableZshIntegration = false;
    };

    eza = {
      enable = true;
      enableZshIntegration = true;
      colors = "always";
      git = true;
      icons = "always";
    };

    fd.enable = true;
    ripgrep.enable = true;

    # SSH host aliases, ported from the hand-written ~/.ssh/config that
    # predated this repo (files dated 2021). The host list itself lives in
    # The host aliases are NOT declared here any more. They live encrypted at
    # secrets/hosts.toml (this repo is public), and flake eval is pure, so
    # nothing in Nix can decrypt them at build time. They are decrypted and
    # rendered into ~/.ssh/config.d/hosts at ACTIVATION time instead — see
    # decryptSshHosts / renderSshHostConfig in home-manager/modules/sops.nix.
    #
    # enableDefaultConfig = false keeps the generated file to the include alone;
    # the default would prepend a `Host *` block that the hand-written config
    # never had, silently changing global ssh behaviour.
    #
    # The include is a glob rather than a literal path on purpose: ssh treats a
    # missing literal Include as an error, but a glob that matches nothing is
    # fine. On a machine with no age key the fragment is never written, and ssh
    # must still work for everything that does not depend on an alias.
    ssh = {
      enable = true;
      enableDefaultConfig = false;
      includes = ["config.d/*"];
    };

    # Direnv for automatic environment loading
    direnv = {
      enable = true;
      enableBashIntegration = true;
      enableZshIntegration = true;
      package = direnvPatched;
    };

    home-manager.enable = true;
  };
}
