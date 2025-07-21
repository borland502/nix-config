{
    enable = true;
    enableCompletion = true;
    autosuggestion.enable = true;
    syntaxHighlighting.enable = true;

    shellAliases = {
      rsync-cp = "rsync -avzhi --filter=':- .gitignore' --exclude='node_modules' --exclude='.venv' --compress-choice=zstd --info=progress2 --stats";
      rsync-mv = "rsync -avz --compress-choice=zstd --progress -h --remove-source-files";
      rsync-update = "rsync -avzu --compress-choice=zstd --progress -h";
      rsync-sync = "rsync -avzu --compress-choice=zstd --delete --info=progress2 --no-whole-file -h";

      rsync-bak = "rsync -avbuzh --numeric-ids --compress-choice=zstd --progress --backup-dir={{.xdg_cache_home}}/rsync";

      alias cat="bat --pager=never";
      alias top="sudo htop";
      alias du="ncdu --color dark -rr -x --exclude .git --exclude node_modules";

      alias ls="eza --icons";                                   # ls
      alias l="eza -lbF --git --icons";                         # list, size, type, git
      alias ll="eza -lbGF --git --icons";                       # long list
      alias ltr="eza -lbGd --git --sort=modified --icons";      # long list, modified date sort
      alias llm="eza --all --header --long --sort=modified $eza_params";
      alias la="eza -lbhHigUmuSa --git --color-scale --icons";  # all list
      alias lx="eza -lbhHigUmuSa@ --git --color-scale --icons"; # all + extended list
      update = "sudo nixos-rebuild switch";
    };
    history.size = 10000;
}