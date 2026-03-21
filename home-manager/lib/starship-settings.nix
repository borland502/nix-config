{
  add_newline = true;
  command_timeout = 500;
  continuation_prompt = "[∙](#bab6c0) ";
  format = "$os$username$hostname$directory$git_branch$git_status$package$nix_shell$nodejs$python$rust$golang$docker_context$kubernetes$aws$cmd_duration$line_break$time$character";
  right_format = "";
  scan_timeout = 30;

  aws = {
    format = "[$symbol($profile )(($region) )]($style)";
    symbol = "🅰 ";
    style = "bold #FCE566";
    disabled = false;
    expiration_symbol = "X";
    force_display = false;
  };

  os = {
    disabled = false;
    format = "[$symbol]($style) ";
    style = "#7BD88F bold";
    symbols = {
      Macos = "󰀵 ";
      NixOS = " ";
      Ubuntu = "󰕈 ";
      Debian = "󰣚 ";
      Fedora = "󰣛 ";
      Arch = "󰣇 ";
      Linux = "󰌽 ";
      Windows = "󰍲 ";
    };
  };

  character = {
    format = "$symbol ";
    disabled = false;
    success_symbol = "[❯](#7BD88F) ";
    error_symbol = "[❯](#FC618D)";
  };

  cmd_duration = {
    min_time = 2000;
    format = "⏱ [$duration]($style) ";
    style = "#FCE566 bold";
    show_milliseconds = false;
    disabled = false;
    show_notifications = false;
    min_time_to_notify = 45000;
  };

  directory = {
    truncation_length = 2;
    truncate_to_repo = true;
    format = "[$path]($style)[$read_only]($read_only_style) ";
    style = "#5AD4E6";
    disabled = false;
    read_only = "🔒";
    read_only_style = "#FC618D";
    truncation_symbol = "…/";
    home_symbol = "~";
    use_os_path_sep = true;
    substitutions = {
      Documents = " ";
      Downloads = " ";
      Music = " ";
      Pictures = " ";
    };
  };

  docker_context = {
    format = "[$symbol\\[$context\\]]($style) ";
    style = "#5AD4E6";
    symbol = "⬢ ";
    only_with_files = true;
    disabled = false;
    detect_extensions = [];
    detect_files = [
      "docker-compose.yml"
      "docker-compose.yaml"
      "Dockerfile"
    ];
    detect_folders = [];
  };

  git_branch = {
    format = "[on](#bab6c0) [$symbol$branch(:$remote_branch)]($style) ";
    symbol = " ";
    style = "#948ae3";
    truncation_length = 9223372036854775807;
    truncation_symbol = "…";
    only_attached = false;
    always_show_remote = false;
    ignore_branches = [];
    disabled = false;
  };

  git_status = {
    format = "([\\[$all_status$ahead_behind\\]]($style)) ";
    style = "#FC618D bold";
    stashed = "≡";
    ahead = "⇡";
    behind = "⇣";
    up_to_date = "";
    diverged = "⇕";
    conflicted = "═";
    deleted = "✘";
    renamed = "»";
    modified = "!";
    staged = "✚";
    untracked = "?";
    typechanged = "◈";
    disabled = false;
  };

  hostname = {
    ssh_only = false;
    format = "[@$hostname]($style) ";
    style = "#fd9353 bold";
    disabled = false;
  };

  nix_shell = {
    format = "[$symbol$state( \\($name\\))]($style) ";
    symbol = "❄️ ";
    style = "#5AD4E6 bold";
    impure_msg = "[impure shell](bold red)";
    pure_msg = "[pure shell](bold green)";
    disabled = false;
  };

  package = {
    format = "[$symbol$version]($style) ";
    symbol = "📦 ";
    style = "#7BD88F bold";
    display_private = false;
    disabled = false;
  };

  nodejs = {
    format = "[$symbol($version )]($style)";
    version_format = "v\${raw}";
    symbol = " ";
    style = "#7BD88F bold";
    disabled = false;
    detect_extensions = ["js" "mjs" "cjs" "ts" "mts" "cts"];
    detect_files = ["package.json" ".nvmrc"];
    detect_folders = ["node_modules"];
  };

  python = {
    format = "[(\${symbol}\${pyenv_prefix}(\${version} )(\\($virtualenv\\) ))]($style)";
    version_format = "v\${raw}";
    symbol = " ";
    style = "#FCE566 bold";
    pyenv_version_name = false;
    pyenv_prefix = "pyenv ";
    python_binary = ["python" "python3" "python2"];
    detect_extensions = ["py"];
    detect_files = [".python-version" "Pipfile" "__init__.py" "pyproject.toml" "requirements.txt" "setup.py" "tox.ini"];
    detect_folders = [];
    disabled = false;
  };

  rust = {
    format = "[$symbol($version )]($style)";
    version_format = "v\${raw}";
    symbol = " ";
    style = "#fd9353 bold";
    disabled = false;
    detect_extensions = ["rs"];
    detect_files = ["Cargo.toml"];
    detect_folders = [];
  };

  time = {
    disabled = false;
    format = "[🕒 $time]($style) ";
    style = "#bab6c0 bold";
    time_format = "%R";
    use_12hr = false;
    utc_time_offset = "local";
  };

  golang = {
    format = "[$symbol($version )]($style)";
    version_format = "v\${raw}";
    symbol = " ";
    style = "#5AD4E6 bold";
    disabled = false;
    detect_extensions = ["go"];
    detect_files = ["go.mod" "go.sum" "glide.yaml" "Gopkg.yml" "Gopkg.lock" ".go-version"];
    detect_folders = ["Godeps"];
  };

  kubernetes = {
    format = "[$symbol$context( \\($namespace\\))]($style) ";
    symbol = "☸ ";
    style = "#5AD4E6 bold";
    disabled = true;
  };

  username = {
    style_root = "#FC618D";
    style_user = "#948ae3";
    format = "[$user]($style)";
    disabled = false;
    show_always = false;
  };
}
