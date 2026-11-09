#!/usr/bin/env -S zsh -f
# Bootstrap the Windows side of a WSL install: run bootstrap-windows.ps1 through
# Windows PowerShell once WSL interop is available. Run by install.sh on WSL.
emulate -R zsh
setopt err_exit no_unset pipe_fail

windows_powershell_exe=${WINDOWS_POWERSHELL_EXE:-/mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe}
bootstrap_ps1=${0:A:h}/bootstrap-windows.ps1

if [[ ! -f $windows_powershell_exe ]]; then
	print -ru2 -- "Windows PowerShell not found at $windows_powershell_exe"
	exit 1
fi

# Ensure WSL interop binfmt handler is registered (required with systemd=true).
if [[ ! -f /proc/sys/fs/binfmt_misc/WSLInterop ]]; then
	print -ru2 -- 'WSL interop handler not registered; attempting to re-register...'
	if [[ -f /init ]]; then
		sudo sh -c 'echo :WSLInterop:M::MZ::/init:PF > /proc/sys/fs/binfmt_misc/register' 2>/dev/null || true
	fi
	if [[ ! -f /proc/sys/fs/binfmt_misc/WSLInterop ]]; then
		print -ru2 -- "Could not register WSL interop handler. Run 'wsl --shutdown' and restart WSL, then retry."
		exit 1
	fi
fi

if [[ ! -f $bootstrap_ps1 ]]; then
	print -ru2 -- "Bootstrap script missing: $bootstrap_ps1"
	exit 1
fi

terminal_package_family=${WINDOWS_TERMINAL_PACKAGE_FAMILY:-Microsoft.WindowsTerminal_8wekyb3d8bbwe}
terminal_font_face=${WINDOWS_TERMINAL_FONT_FACE:-FiraCode Nerd Font Mono}

exec $windows_powershell_exe -NoProfile -ExecutionPolicy Bypass -File $bootstrap_ps1 \
	-WindowsTerminalPackageFamily $terminal_package_family \
	-TerminalFontFace $terminal_font_face
