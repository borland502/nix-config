{
  pkgs,
  lib,
  ...
}: let
  starshipSettings = import ./lib/starship-settings.nix;
  windowsBootstrap = {
    # Set these explicitly if Windows path discovery is unreliable on a given host.
    userProfilePath = null;
    documentsPath = null;
    localAppDataPath = null;
    terminalPackageFamily = "Microsoft.WindowsTerminal_8wekyb3d8bbwe";
    terminalFontFace = "FiraCode Nerd Font Mono";
  };
  starshipToml = pkgs.formats.toml {};
  windowsStarshipConfig = starshipToml.generate "windows-starship.toml" starshipSettings;
  windowsPowerShellProfile = pkgs.writeText "Microsoft.PowerShell_profile.ps1" ''
    $starshipConfig = Join-Path $HOME ".config\starship.toml"
    $env:STARSHIP_CONFIG = $starshipConfig

    $starship = Get-Command starship -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source -First 1
    if ([string]::IsNullOrWhiteSpace($starship)) {
      $starship = Resolve-Path (Join-Path $env:LOCALAPPDATA "Microsoft\WinGet\Packages\Starship.Starship_*\starship.exe") -ErrorAction SilentlyContinue |
        Select-Object -ExpandProperty Path -First 1
    }

    if ([string]::IsNullOrWhiteSpace($starship)) {
      Write-Warning "starship is not installed. Install it with winget install --id Starship.Starship -e --scope user"
      return
    }

    Invoke-Expression (& $starship init powershell)
  '';
  linuxPackages = with pkgs; [
    iotop
    iftop
    strace
    ltrace
    sysstat
    lm_sensors
    ethtool
    pciutils
    usbutils
    dbus
    nerd-fonts.fira-code
  ];
  vivaldiBrowserWrapper = pkgs.writeShellApplication {
    name = "vivaldi";
    runtimeInputs = [pkgs.coreutils];
    text = ''
      set -eu

      windows_powershell_exe="/mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe"
      wslpath_exe="/sbin/wslpath"
      vivaldi_exe=""

      if [ -x "$windows_powershell_exe" ] && [ -x "$wslpath_exe" ]; then
        windows_local_appdata_win="$($windows_powershell_exe -NoProfile -Command "[Environment]::GetFolderPath('LocalApplicationData')" | tr -d '\r')"
        if [ -n "$windows_local_appdata_win" ]; then
          windows_local_appdata_unix="$($wslpath_exe -u "$windows_local_appdata_win")"
          candidate="$windows_local_appdata_unix/Vivaldi/Application/vivaldi.exe"
          if [ -f "$candidate" ]; then
            vivaldi_exe="$candidate"
          fi
        fi
      fi

      if [ -z "$vivaldi_exe" ] && [ -f "/mnt/c/Program Files/Vivaldi/Application/vivaldi.exe" ]; then
        vivaldi_exe="/mnt/c/Program Files/Vivaldi/Application/vivaldi.exe"
      fi

      if [ -z "$vivaldi_exe" ] && [ -f "/mnt/c/Program Files (x86)/Vivaldi/Application/vivaldi.exe" ]; then
        vivaldi_exe="/mnt/c/Program Files (x86)/Vivaldi/Application/vivaldi.exe"
      fi

      if [ -z "$vivaldi_exe" ]; then
        echo "Vivaldi is not installed on the Windows host." >&2
        exit 1
      fi

      exec "$vivaldi_exe" "$@"
    '';
  };

  availableOnHost = pkg: lib.meta.availableOn pkgs.stdenv.hostPlatform pkg;
  availableLinuxPackages = lib.filter availableOnHost linuxPackages;
  codeEditorUserSettings = import ./lib/code-editor-user-settings.nix {inherit pkgs;};
in {
  _module.args.isWsl = true;

  imports = [
    ./common.nix
    ./profiles/development-linux.nix
  ];

  home = {
    username = lib.mkDefault "nixos";
    homeDirectory = lib.mkDefault "/home/nixos";

    packages = availableLinuxPackages ++ [vivaldiBrowserWrapper];
    sessionVariables.BROWSER = "vivaldi";

    activation.dconfSettings = lib.mkForce (
      lib.hm.dag.entryAfter ["checkLinkTargets"] ''
        echo "Skipping dconfSettings in WSL (no dconf service available)."
      ''
    );

    activation.windowsPowerShellBootstrap = lib.hm.dag.entryAfter ["writeBoundary"] ''
      windows_powershell_exe="/mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe"
      wslpath_exe="/sbin/wslpath"
      mkdir_exe="${pkgs.coreutils}/bin/mkdir"
      install_exe="${pkgs.coreutils}/bin/install"
      tr_exe="${pkgs.coreutils}/bin/tr"
      windows_terminal_package_family='${windowsBootstrap.terminalPackageFamily}'

      if [ ! -x "$windows_powershell_exe" ]; then
        echo "Skipping Windows PowerShell bootstrap: $windows_powershell_exe is unavailable."
      elif [ ! -x "$wslpath_exe" ]; then
        echo "Skipping Windows PowerShell bootstrap: $wslpath_exe is unavailable."
      elif ! "$windows_powershell_exe" -NoProfile -Command '$PSVersionTable.PSVersion.ToString()' >/dev/null 2>&1; then
        echo "Skipping Windows PowerShell bootstrap: Windows executable interop is unavailable."
      else
        ${
        if windowsBootstrap.userProfilePath != null
        then "windows_home_win='${windowsBootstrap.userProfilePath}'"
        else ''windows_home_win="$($windows_powershell_exe -NoProfile -Command "[Environment]::GetFolderPath('UserProfile')" | $tr_exe -d '\r')"''
      }
        ${
        if windowsBootstrap.documentsPath != null
        then "windows_documents_win='${windowsBootstrap.documentsPath}'"
        else ''windows_documents_win="$($windows_powershell_exe -NoProfile -Command "[Environment]::GetFolderPath('MyDocuments')" | $tr_exe -d '\r')"''
      }
        ${
        if windowsBootstrap.localAppDataPath != null
        then "windows_local_appdata_win='${windowsBootstrap.localAppDataPath}'"
        else ''windows_local_appdata_win="$($windows_powershell_exe -NoProfile -Command "[Environment]::GetFolderPath('LocalApplicationData')" | $tr_exe -d '\r')"''
      }

        if [ -z "$windows_home_win" ] || [ -z "$windows_documents_win" ] || [ -z "$windows_local_appdata_win" ]; then
          echo "Skipping Windows PowerShell bootstrap: could not resolve Windows profile paths."
        else
          windows_home_unix="$($wslpath_exe -u "$windows_home_win")"
          windows_documents_unix="$($wslpath_exe -u "$windows_documents_win")"
          windows_local_appdata_unix="$($wslpath_exe -u "$windows_local_appdata_win")"
          windows_config_dir="$windows_home_unix/.config"
          powershell7_dir="$windows_documents_unix/PowerShell"
          windows_powershell_dir="$windows_documents_unix/WindowsPowerShell"

          $mkdir_exe -p "$windows_config_dir" "$powershell7_dir" "$windows_powershell_dir"
          $install_exe -m 0644 ${windowsStarshipConfig} "$windows_config_dir/starship.toml"
          $install_exe -m 0644 ${windowsPowerShellProfile} "$powershell7_dir/Microsoft.PowerShell_profile.ps1"
          $install_exe -m 0644 ${windowsPowerShellProfile} "$windows_powershell_dir/Microsoft.PowerShell_profile.ps1"

          if ! "$windows_powershell_exe" -NoProfile -Command '$starship = Get-Command starship -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source -First 1; if (-not $starship) { $starship = Resolve-Path (Join-Path $env:LOCALAPPDATA "Microsoft\WinGet\Packages\Starship.Starship_*\starship.exe") -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Path -First 1 }; if ($starship) { exit 0 } else { exit 1 }'; then
            if "$windows_powershell_exe" -NoProfile -Command 'Get-Command winget -ErrorAction SilentlyContinue | Out-Null; if ($?) { exit 0 } else { exit 1 }'; then
              echo "Installing starship on Windows via winget..."
              if ! "$windows_powershell_exe" -NoProfile -Command 'winget install --id Starship.Starship -e --scope user --silent --accept-package-agreements --accept-source-agreements'; then
                echo "Warning: failed to install starship via winget."
              fi
            else
              echo "Skipping starship bootstrap: winget is unavailable in Windows PowerShell."
            fi
          fi

          if ! "$windows_powershell_exe" -NoProfile -Command 'Get-Command pwsh -ErrorAction SilentlyContinue | Out-Null; if ($?) { exit 0 } else { exit 1 }'; then
            if "$windows_powershell_exe" -NoProfile -Command 'Get-Command winget -ErrorAction SilentlyContinue | Out-Null; if ($?) { exit 0 } else { exit 1 }'; then
              echo "Installing PowerShell 7 on Windows via winget..."
              if ! "$windows_powershell_exe" -NoProfile -Command 'winget install --id Microsoft.PowerShell -e --scope user --silent --accept-package-agreements --accept-source-agreements'; then
                echo "Warning: failed to install PowerShell 7 via winget."
              fi
            else
              echo "Skipping PowerShell 7 bootstrap: winget is unavailable in Windows PowerShell."
            fi
          fi
        fi
      fi
    '';

    file = {
      ".vscode-server/data/User/settings.json".text = builtins.toJSON codeEditorUserSettings;
      ".vscode-server-insiders/data/User/settings.json".text = builtins.toJSON codeEditorUserSettings;
      ".vscode-server/data/Machine/settings.json".text = builtins.toJSON {
        "terminal.integrated.automationProfile.linux" = {
          path = "${pkgs.zsh}/bin/zsh";
          args = ["-l"];
        };
      };
      ".vscode-server-insiders/data/Machine/settings.json".text = builtins.toJSON {
        "terminal.integrated.automationProfile.linux" = {
          path = "${pkgs.zsh}/bin/zsh";
          args = ["-l"];
        };
      };
    };
  };

  stylix.targets = {
    bat.enable = lib.mkForce true;
    btop.enable = lib.mkForce true;
    fzf.enable = lib.mkForce true;
    kitty.enable = true;
    starship.enable = lib.mkForce true;
    vim.enable = lib.mkForce true;
    vscode.enable = true;
    gtk.enable = lib.mkForce false;
    kde.enable = lib.mkForce false;
  };

  programs.starship.settings = {
    format = lib.mkForce "$os$username$hostname$directory$git_branch$git_status$nix_shell$nodejs$python$rust$golang$docker_context$aws$cmd_duration$line_break$character";

    os = {
      disabled = false;
      format = "[$symbol]($style) ";
      style = "#7BD88F bold";
      symbols = {
        NixOS = " ";
        Windows = "󰍲 ";
      };
    };

    username.show_always = lib.mkForce true;

    hostname = {
      ssh_only = lib.mkForce false;
      format = lib.mkForce "[wsl@$hostname]($style) ";
      style = lib.mkForce "#fd9353 bold";
    };

    directory.truncation_length = lib.mkForce 5;
  };

  fonts.fontconfig.defaultFonts = {
    sansSerif = lib.mkAfter ["DejaVu Sans"];
    serif = lib.mkAfter ["DejaVu Serif"];
  };
}
