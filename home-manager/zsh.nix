{
  enable = true;
  enableCompletion = true;
  autosuggestion.enable = true;
  syntaxHighlighting.enable = true;

  # setOptions = [
  #   "NO_BEEP"
  #   "NO_FLOW_CONTROL"
  #   "PROMPT_SUBST"
  #   "LONG_LIST_JOBS"
  #   "NONOMATCH"
  #   "NOTIFY"
  #   "HASH_LIST_ALL"
  #   "COMPLETE_IN_WORD"
  #   "NO_SH_WORD_SPLIT"
  #   "INTERACTIVE_COMMENTS"
  # ];

  shellAliases = {
    rsync-cp =
      "rsync -avzhi --filter=':- .gitignore' --exclude='node_modules' --exclude='.venv' --compress-choice=zstd --info=progress2 --stats";
    rsync-mv =
      "rsync -avz --compress-choice=zstd --progress -h --remove-source-files";
    rsync-update = "rsync -avzu --compress-choice=zstd --progress -h";
    rsync-sync =
      "rsync -avzu --compress-choice=zstd --delete --info=progress2 --no-whole-file -h";

    rsync-bak =
      "rsync -avbuzh --numeric-ids --compress-choice=zstd --progress --backup-dir={{.xdg_cache_home}}/rsync";

    cat = "bat --pager=never";
    top = "sudo htop";
    du = "ncdu --color dark -rr -x --exclude .git --exclude node_modules";

    ls = "eza --icons"; # ls
    l = "eza -lbF --git --icons"; # list, size, type, git
    ll = "eza -lbGF --git --icons"; # long list
    ltr =
      "eza -lbGd --git --sort=modified --icons"; # long list, modified date sort
    llm = "eza --all --header --long --sort=modified $eza_params";
    la = "eza -lbhHigUmuSa --git --color-scale --icons"; # all list
    lx = "eza -lbhHigUmuSa@ --git --color-scale --icons"; # all + extended list
    update = "sudo nixos-rebuild switch";
  };

  envExtra = ''
    export base0="#131313"
    export base1="#191919"
    export base2="#222222"
    export base3="#363537"
    export base4="#525053"
    export base5="#69676c"
    export base6="#8b888f"
    export base7="#bab6c0"
    export base8="#f7f1ff"
    export base8x0c="#2b2b2b"
    export blue="#5ad4e6"
    export green="#7bd88f"
    export orange="#fd9353"
    export purple="#948ae3"
    export red="#fc618d"
    export yellow="#fcd566"
    export EDITOR="vim"
    export XDG_BIN_HOME="$HOME/.local/bin"
    export XDG_CACHE_HOME="$HOME/.cache"
    export XDG_CONFIG_HOME="$HOME/.config"
    export XDG_DATA_HOME="$HOME/.local/share"
    export XDG_LIB_HOME="$HOME/.local/lib"
    export XDG_RUNTIME_DIR="$HOME/.run"
    export XDG_STATE_HOME="$HOME/.local/state"
    export CAN_USE_SUDO=1
    export DOCKER_BUILDKIT=1
    export GOMPLATE_CONFIG="$XDG_CONFIG_HOME/gomplate/gomplate.yaml"
    export GUM_CHOOSE_CURSOR_FOREGROUND="$green"
    export GUM_CHOOSE_ITEM_FOREGROUND="$blue"
    export GUM_CHOOSE_SELECTED_FOREGROUND="$purple"
    export GUM_INPUT_CURSOR_FOREGROUND="$green"
    export GUM_INPUT_PLACEHOLDER="What is the value?"
    export GUM_INPUT_PROMPT="> "
    export GUM_INPUT_PROMPT_FOREGROUND="$blue"
    export GUM_INPUT_WIDTH=120
    export HAS_ALLOW_UNSAFE='y'
    export HOMEBREW_NO_ANALYTICS=0
    export HOMEBREW_NO_INSTALL_CLEANUP=true
    export UNISON="$XDG_CONFIG_HOME/unison"
  '';

  history = {
    save = 90000;
    size = 90000;
    expireDuplicatesFirst = true;
    ignoreAllDups = true;

  };
}
