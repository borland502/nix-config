{ config, pkgs, lib, ... }:

{
  programs.starship = {
    enable = true;
    enableZshIntegration = true;
    settings = {
      add_newline = true;
      command_timeout = 500;
      continuation_prompt = "[∙](#bab6c0) "; # base05 (light gray) for visibility
      format = "$os$username$hostname$directory$git_branch$git_status$package$nix_shell$nodejs$python$rust$golang$docker_context$kubernetes$aws$cmd_duration$line_break$character";
      right_format = "";
      scan_timeout = 30;
      
      # AWS
      aws = {
        format = "[$symbol($profile )(($region) )]($style)";
        symbol = "🅰 ";
        style = "bold #FCE566"; # base0A (yellow)
        disabled = false;
        expiration_symbol = "X";
        force_display = false;
      };

      # Character
      character = {
        format = "$symbol ";
        disabled = false;
        success_symbol = "[❯](#7BD88F) "; # base0B (green) with visible arrow
        error_symbol = "[❯](#FC618D)"; # base08 (red) with visible arrow
      };

      # Command Duration
      cmd_duration = {
        min_time = 2000;
        format = "⏱ [$duration]($style) ";
        style = "#FCE566 bold"; # base0A (yellow)
        show_milliseconds = false;
        disabled = false;
        show_notifications = false;
        min_time_to_notify = 45000;
      };

      # Directory
      directory = {
        truncation_length = 3;
        truncate_to_repo = true;
        format = "[$path]($style)[$read_only]($read_only_style) ";
        style = "#5AD4E6"; # base0C (cyan)
        disabled = false;
        read_only = "🔒";
        read_only_style = "#FC618D"; # base08 (red)
        truncation_symbol = "…/";
        home_symbol = "~";
        use_os_path_sep = true;
        substitutions = {
          "Documents" = " ";
          "Downloads" = " ";
          "Music" = " ";
          "Pictures" = " ";
        };
      };

      # Docker Context
      docker_context = {
        format = "[$symbol$context]($style) ";
        style = "#5AD4E6"; # base0C (cyan)
        symbol = " ";
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

      # Git Branch
      git_branch = {
        format = "[$symbol$branch(:$remote_branch)]($style) ";
        symbol = " ";
        style = "#948ae3"; # base0D (purple)
        truncation_length = 9223372036854775807;
        truncation_symbol = "…";
        only_attached = false;
        always_show_remote = false;
        ignore_branches = [];
        disabled = false;
      };

      # Git Status
      git_status = {
        format = "([\\[$all_status$ahead_behind\\]]($style) )";
        style = "#FC618D bold"; # base08 (red)
        stashed = "\\$";
        ahead = "⇡";
        behind = "⇣";
        up_to_date = "";
        diverged = "⇕";
        conflicted = "=";
        deleted = "✘";
        renamed = "»";
        modified = "M";
        staged = "+";
        untracked = "?";
        typechanged = "";
        disabled = false;
      };

      # Hostname
      hostname = {
        ssh_only = false;
        format = "[@$hostname]($style) ";
        style = "#fd9353 bold"; # base09 (orange)
        disabled = false;
      };

      # Nix Shell
      nix_shell = {
        format = "[$symbol$state( \\($name\\))]($style) ";
        symbol = "❄️ ";
        style = "#5AD4E6 bold"; # base0C (cyan)
        impure_msg = "[impure shell](bold red)";
        pure_msg = "[pure shell](bold green)";
        disabled = false;
      };

      # Package
      package = {
        format = "[$symbol$version]($style) ";
        symbol = "📦 ";
        style = "#7BD88F bold"; # base0B (green)
        display_private = false;
        disabled = false;
      };

      # Programming Languages
      nodejs = {
        format = "[$symbol($version )]($style)";
        version_format = "v\${raw}";
        symbol = " ";
        style = "#7BD88F bold"; # base0B (green)
        disabled = false;
        detect_extensions = ["js" "mjs" "cjs" "ts" "mts" "cts"];
        detect_files = ["package.json" ".nvmrc"];
        detect_folders = ["node_modules"];
      };

      python = {
        format = "[(\${symbol}\${pyenv_prefix}(\${version} )(\\($virtualenv\\) ))]($style)";
        version_format = "v\${raw}";
        symbol = " ";
        style = "#FCE566 bold"; # base0A (yellow)
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
        style = "#fd9353 bold"; # base09 (orange)
        disabled = false;
        detect_extensions = ["rs"];
        detect_files = ["Cargo.toml"];
        detect_folders = [];
      };

      golang = {
        format = "[$symbol($version )]($style)";
        version_format = "v\${raw}";
        symbol = " ";
        style = "#5AD4E6 bold"; # base0C (cyan)
        disabled = false;
        detect_extensions = ["go"];
        detect_files = ["go.mod" "go.sum" "glide.yaml" "Gopkg.yml" "Gopkg.lock" ".go-version"];
        detect_folders = ["Godeps"];
      };

      # Kubernetes
      kubernetes = {
        format = "[$symbol$context( \\($namespace\\))]($style) ";
        symbol = "☸ ";
        style = "#5AD4E6 bold"; # base0C (cyan)
        disabled = true;
      };

      # Username
      username = {
        style_root = "#FC618D"; # base08 (red)
        style_user = "#948ae3"; # base0D (purple)
        format = "[$user]($style) ";
        disabled = false;
        show_always = false;
      };
    };
  };
}
