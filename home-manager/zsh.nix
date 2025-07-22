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
    base0 = #131313
    base1 = #191919
    base2 = #222222
    base3 = #363537
    base4 = #525053
    base5 = #69676c
    base6 = #8b888f
    base7 = #bab6c0
    base8 = #f7f1ff
    base8x0c = #2b2b2b
    blue = #5ad4e6
    green = #7bd88f
    orange = #fd9353
    purple = #948ae3
    red = #fc618d
    yellow = #fcd566"
    EDITOR=vim"
    XDG_BIN_HOME = $HOME/.local/bin
    XDG_CACHE_HOME = $HOME/.cache
    XDG_CONFIG_HOME = $HOME/.config
    XDG_DATA_HOME = $HOME/.local/share
    XDG_LIB_HOME = $HOME/.local/lib
    XDG_RUNTIME_DIR = $HOME/.run
    XDG_STATE_HOME = $HOME/.local/state
    CAN_USE_SUDO = 1
    DOCKER_BUILDKIT = 1
    GOMPLATE_CONFIG = $XDG_CONFIG_HOME/gomplate/gomplate.yaml
    GUM_CHOOSE_CURSOR_FOREGROUND = $green
    GUM_CHOOSE_ITEM_FOREGROUND = $blue
    GUM_CHOOSE_SELECTED_FOREGROUND = $purple
    GUM_INPUT_CURSOR_FOREGROUND = $green
    GUM_INPUT_PLACEHOLDER = What is the value?
    GUM_INPUT_PROMPT = > 
    GUM_INPUT_PROMPT_FOREGROUND = $blue
    GUM_INPUT_WIDTH = 120
    HAS_ALLOW_UNSAFE = 'y'
    HOMEBREW_NO_ANALYTICS = 0
    HOMEBREW_NO_INSTALL_CLEANUP = true
    LS_COLORS = $(dircolors --print-ls-colors $XDG_CONFIG_HOME/colors/dircolors.monokai)
    UNISON = $XDG_CONFIG_HOME/unison
  '';

  history = {
    save = 90000;
    size = 90000;
    expireDuplicatesFirst = true;
    ignoreAllDups = true;

  };
}
