#!/usr/bin/env bash
set -euo pipefail

windows_powershell_exe="${WINDOWS_POWERSHELL_EXE:-/mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe}"
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
bootstrap_ps1="$script_dir/bootstrap-windows.ps1"

if [[ ! -f "$windows_powershell_exe" ]]; then
  echo "Windows PowerShell not found at $windows_powershell_exe" >&2
  exit 1
fi

# Ensure WSL interop binfmt handler is registered (required with systemd=true).
if [[ ! -f /proc/sys/fs/binfmt_misc/WSLInterop ]]; then
  echo "WSL interop handler not registered; attempting to re-register..." >&2
  if [[ -f /init ]]; then
    sudo sh -c 'echo :WSLInterop:M::MZ::/init:PF > /proc/sys/fs/binfmt_misc/register' 2>/dev/null || true
  fi
  if [[ ! -f /proc/sys/fs/binfmt_misc/WSLInterop ]]; then
    echo "Could not register WSL interop handler. Run 'wsl --shutdown' and restart WSL, then retry." >&2
    exit 1
  fi
fi

if [[ ! -f "$bootstrap_ps1" ]]; then
  echo "Bootstrap script missing: $bootstrap_ps1" >&2
  exit 1
fi

terminal_package_family="${WINDOWS_TERMINAL_PACKAGE_FAMILY:-Microsoft.WindowsTerminal_8wekyb3d8bbwe}"
terminal_font_face="${WINDOWS_TERMINAL_FONT_FACE:-FiraCode Nerd Font Mono}"

exec "$windows_powershell_exe" -NoProfile -ExecutionPolicy Bypass -File "$bootstrap_ps1" \
  -WindowsTerminalPackageFamily "$terminal_package_family" \
  -TerminalFontFace "$terminal_font_face"