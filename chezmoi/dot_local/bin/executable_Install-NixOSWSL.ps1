#Requires -Version 5.1
<#
.SYNOPSIS
    Interactive installer for NixOS-WSL. Verifies WSL prerequisites, downloads
    the latest NixOS-WSL image for this machine's architecture, verifies its
    SHA-256, and registers it as a WSL distribution.

.DESCRIPTION
    Checks that the host can run WSL2 (64-bit Windows, a supported build, the
    "Virtual Machine Platform" and "Windows Subsystem for Linux" optional
    features, and a working/updated `wsl` command). Anything missing is fixed
    with a single elevation (UAC) prompt. It then queries the
    nix-community/NixOS-WSL GitHub releases for the newest image, downloads and
    checksum-verifies it, and installs it with either:

      * wsl --install --from-file   (recommended; runs NixOS-WSL first-boot
                                      setup; requires WSL >= 2.4.4)
      * wsl --import <Name> <Dir>   (custom distro name and/or install folder;
                                      works on any WSL2; first boot is as root)

.PARAMETER Name
    Distribution name to register. Default: NixOS. A non-default name forces the
    --import method.

.PARAMETER InstallLocation
    Folder for the distribution's virtual disk (only used by --import).
    Default: %LOCALAPPDATA%\WSL\<Name>.

.PARAMETER Tag
    Pin a specific NixOS-WSL release tag (e.g. 2605.7.2). Default: latest.

.PARAMETER DownloadDir
    Where to save the downloaded image. Default: %TEMP%.

.PARAMETER Method
    Install method: Auto (default), FromFile, or Import.

.PARAMETER KeepDownload
    Keep the downloaded .wsl image instead of deleting it afterwards.

.PARAMETER NonInteractive
    Run without prompts, using parameter values and defaults.

.PARAMETER SetDefault
    Make the new distribution the default WSL distribution.

.PARAMETER Launch
    Launch the distribution when installation completes.

.EXAMPLE
    .\Install-NixOSWSL.ps1

.EXAMPLE
    .\Install-NixOSWSL.ps1 -Name NixOS-dev -Method Import -SetDefault -Launch

.LINK
    https://github.com/nix-community/NixOS-WSL
#>
[CmdletBinding()]
param(
    [string]$Name = 'NixOS',
    [string]$InstallLocation,
    [string]$Tag,
    [string]$DownloadDir = $env:TEMP,
    [ValidateSet('Auto', 'FromFile', 'Import')]
    [string]$Method = 'Auto',
    [switch]$KeepDownload,
    [switch]$NonInteractive,
    [switch]$SetDefault,
    [switch]$Launch
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
# TLS 1.2 for older PowerShell 5.1 defaults; make wsl.exe emit UTF-8 not UTF-16.
[Net.ServicePointManager]::SecurityProtocol = `
    [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
$env:WSL_UTF8 = '1'

$Repo          = 'nix-community/NixOS-WSL'
$MinWslVersion = [version]'2.4.4'   # required for `wsl --install --from-file`
$MinBuild      = 19041              # Windows 10 2004 -- WSL2 baseline

# ---------------------------------------------------------------------------
# Color palette — "Monokai Spectrumish", this repo's shared palette
# (chezmoi/dot_config/colors/monokai.toml). Truecolor ANSI on capable terminals
# (Windows Terminal, VS Code), with a graceful fall back to the nearest 16-color
# ConsoleColor on legacy consoles.
# ---------------------------------------------------------------------------
$script:Palette = @{
    fg      = '#bab6c0'  # base05 default foreground
    fgLight = '#fbf8ff'  # base06 light foreground (titles)
    dim     = '#8b888f'  # base04 muted foreground (hints, URLs)
    red     = '#fc618d'  # base08 pink/red (errors)
    orange  = '#fd9353'  # base09 orange (accents)
    yellow  = '#fce566'  # base0A yellow (warnings)
    green   = '#7bd88f'  # base0B green (success)
    cyan    = '#5ad4e6'  # base0C cyan (section headers)
    purple  = '#948ae3'  # base0D purple (menu choices)
}
$script:PaletteFallback = @{
    fg = 'Gray'; fgLight = 'White'; dim = 'DarkGray'; red = 'Red'
    orange = 'DarkYellow'; yellow = 'Yellow'; green = 'Green'
    cyan = 'Cyan'; purple = 'Magenta'
}
$script:UseAnsi = $false
try { $script:UseAnsi = [bool]$Host.UI.SupportsVirtualTerminal } catch { }
if ($env:WT_SESSION -or $env:TERM_PROGRAM) { $script:UseAnsi = $true }

# ---------------------------------------------------------------------------
# Output / prompt helpers
# ---------------------------------------------------------------------------
function Write-Palette {
    param(
        [Parameter(Mandatory)][string]$Text,
        [string]$Color = 'fg',
        [switch]$NoNewline
    )
    if ($script:UseAnsi -and $script:Palette.ContainsKey($Color)) {
        $hex = $script:Palette[$Color]
        $r = [Convert]::ToInt32($hex.Substring(1, 2), 16)
        $g = [Convert]::ToInt32($hex.Substring(3, 2), 16)
        $b = [Convert]::ToInt32($hex.Substring(5, 2), 16)
        $esc = [char]27
        Write-Host ("$esc[38;2;$r;$g;${b}m" + $Text + "$esc[0m") -NoNewline:$NoNewline
    }
    else {
        $fc = $script:PaletteFallback[$Color]
        if ($fc) { Write-Host $Text -ForegroundColor $fc -NoNewline:$NoNewline }
        else     { Write-Host $Text -NoNewline:$NoNewline }
    }
}

function Write-Step { param([string]$m) Write-Host ''; Write-Palette "==> $m" cyan }
function Write-Ok   { param([string]$m) Write-Palette "  [ OK ] $m" green }
function Write-Warn { param([string]$m) Write-Palette "  [WARN] $m" yellow }
function Write-Info { param([string]$m) Write-Palette "  [ .. ] $m" dim }
function Die        { param([string]$m) Write-Host ''; Write-Palette "[ERROR] $m" red; exit 1 }

function Confirm-Yes {
    param([string]$Prompt, [bool]$Default = $true)
    if ($NonInteractive) { return $Default }
    $suffix = if ($Default) { '[Y/n]' } else { '[y/N]' }
    while ($true) {
        $a = (Read-Host "$Prompt $suffix").Trim()
        if ([string]::IsNullOrEmpty($a)) { return $Default }
        switch -Regex ($a) {
            '^(y|yes)$' { return $true }
            '^(n|no)$'  { return $false }
            default     { Write-Warn 'Please answer y or n.' }
        }
    }
}

# ---------------------------------------------------------------------------
# Environment probing
# ---------------------------------------------------------------------------
function Test-Admin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    (New-Object Security.Principal.WindowsPrincipal $id).IsInRole(
        [Security.Principal.WindowsBuiltinRole]::Administrator)
}

function Get-HostArch {
    # Honor PROCESSOR_ARCHITEW6432 in case we're a 32-bit shell on 64-bit Windows.
    $arch = if ($env:PROCESSOR_ARCHITEW6432) { $env:PROCESSOR_ARCHITEW6432 }
            else { $env:PROCESSOR_ARCHITECTURE }
    switch ($arch) {
        'ARM64' { return 'nixos.aarch64.wsl' }
        'AMD64' { return 'nixos.wsl' }
        default { Die "Unsupported architecture '$arch'. NixOS-WSL ships x86_64 and aarch64 only." }
    }
}

function Get-WslExe {
    $cmd = Get-Command wsl.exe -CommandType Application -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if ($cmd) { return $cmd.Source }
    $sys = Join-Path $env:WINDIR 'System32\wsl.exe'
    if (Test-Path $sys) { return $sys }
    return $null
}

function Get-WslVersion {
    param([string]$WslExe)
    if (-not $WslExe) { return $null }
    try {
        $out = & $WslExe --version 2>$null
        foreach ($line in $out) {
            if ($line -match '(\d+\.\d+\.\d+(\.\d+)?)') { return [version]$Matches[1] }
        }
    } catch { }
    return $null
}

function Test-WslFunctional {
    param([string]$WslExe)
    if (-not $WslExe) { return $false }
    try { & $WslExe --status *> $null; return ($LASTEXITCODE -eq 0) }
    catch { return $false }
}

function Get-FeatureState {
    # Returns Enabled / Disabled / DisabledWithPayloadRemoved / Unknown.
    # Querying optional features usually needs elevation; Unknown means we
    # could not read it (and will let the elevated step enable it anyway).
    param([string]$FeatureName)
    try {
        (Get-WindowsOptionalFeature -Online -FeatureName $FeatureName -ErrorAction Stop).State.ToString()
    } catch { 'Unknown' }
}

function Get-WslDistros {
    param([string]$WslExe)
    if (-not $WslExe) { return @() }
    try { @(& $WslExe --list --quiet | ForEach-Object { $_.Trim() } | Where-Object { $_ }) }
    catch { @() }
}

# ---------------------------------------------------------------------------
# Elevated prerequisite remediation (enable features, install/update WSL)
# ---------------------------------------------------------------------------
$ElevatedSetupScript = @'
$ErrorActionPreference = 'Continue'
$restart = $false
Write-Host '== Elevated NixOS-WSL prerequisite setup ==' -ForegroundColor Magenta

foreach ($f in 'Microsoft-Windows-Subsystem-Linux', 'VirtualMachinePlatform') {
    try {
        $state = (Get-WindowsOptionalFeature -Online -FeatureName $f -ErrorAction Stop).State
    } catch { $state = 'Unknown' }
    if ($state -ne 'Enabled') {
        Write-Host "Enabling optional feature: $f" -ForegroundColor Cyan
        $r = Enable-WindowsOptionalFeature -Online -FeatureName $f -All -NoRestart
        if ($r.RestartNeeded) { $restart = $true }
    } else {
        Write-Host "Optional feature already enabled: $f" -ForegroundColor Green
    }
}

$wsl = Get-Command wsl.exe -CommandType Application -ErrorAction SilentlyContinue
if (-not $wsl) {
    Write-Host 'Installing WSL (no distribution)...' -ForegroundColor Cyan
    wsl.exe --install --no-distribution
} else {
    Write-Host 'Updating WSL to the latest version...' -ForegroundColor Cyan
    wsl.exe --update
}

if ($restart) {
    Write-Host 'A restart is required to finish enabling Windows features.' -ForegroundColor Yellow
    exit 3010
}
exit 0
'@

function Invoke-ElevatedSetup {
    param([string]$Body)
    $tmp = Join-Path $env:TEMP ("nixos-wsl-prereq-{0}.ps1" -f ([guid]::NewGuid().ToString('N')))
    Set-Content -LiteralPath $tmp -Value $Body -Encoding UTF8
    try {
        if (Test-Admin) {
            & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $tmp
            return $LASTEXITCODE
        }
        $p = Start-Process powershell.exe -Verb RunAs -Wait -PassThru -ArgumentList @(
            '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ('"{0}"' -f $tmp))
        return $p.ExitCode
    } finally {
        Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
    }
}

# ---------------------------------------------------------------------------
# Release lookup, download, verification
# ---------------------------------------------------------------------------
function Get-Release {
    param([string]$Tag)
    $headers = @{ 'User-Agent' = 'NixOS-WSL-Installer'; 'Accept' = 'application/vnd.github+json' }
    $url = if ($Tag) { "https://api.github.com/repos/$Repo/releases/tags/$Tag" }
           else       { "https://api.github.com/repos/$Repo/releases/latest" }
    try { Invoke-RestMethod -Uri $url -Headers $headers }
    catch { Die "Could not query GitHub releases ($url): $($_.Exception.Message)" }
}

function Save-File {
    param([string]$Url, [string]$OutFile)
    if (Test-Path $OutFile) { Remove-Item -LiteralPath $OutFile -Force }
    if (Get-Command Start-BitsTransfer -ErrorAction SilentlyContinue) {
        try {
            Start-BitsTransfer -Source $Url -Destination $OutFile -Description 'NixOS-WSL image'
            return
        } catch { Write-Warn "BITS transfer failed ($($_.Exception.Message)); using web request." }
    }
    $old = $ProgressPreference
    $ProgressPreference = 'SilentlyContinue'   # avoids the huge slowdown IWR's bar causes on big files
    try { Invoke-WebRequest -Uri $Url -OutFile $OutFile -UseBasicParsing }
    finally { $ProgressPreference = $old }
}

function Test-Checksum {
    param([string]$File, [string]$Sha256File)
    $expected = ((Get-Content -LiteralPath $Sha256File -Raw).Trim() -split '\s+')[0].ToLower()
    $actual   = (Get-FileHash -LiteralPath $File -Algorithm SHA256).Hash.ToLower()
    if ($expected -ne $actual) {
        Die "SHA-256 mismatch -- download is corrupt or tampered.`n  expected: $expected`n  actual:   $actual"
    }
    Write-Ok "SHA-256 verified: $actual"
}

# ===========================================================================
# Main
# ===========================================================================
Write-Host ''
Write-Palette '  NixOS-WSL interactive installer' fgLight
Write-Palette '  https://github.com/nix-community/NixOS-WSL' dim

# --- Static host checks -----------------------------------------------------
Write-Step 'Checking prerequisites'

if (-not [Environment]::Is64BitOperatingSystem) { Die 'WSL2 requires 64-bit Windows.' }
Write-Ok '64-bit Windows'

$build = [int][Environment]::OSVersion.Version.Build
if ($build -lt $MinBuild) {
    Die "Windows build $build is too old for WSL2 (need >= $MinBuild / Windows 10 2004). Run Windows Update."
}
Write-Ok "Windows build $build (>= $MinBuild)"

$assetName = Get-HostArch
Write-Ok "Architecture image: $assetName"

# --- WSL + feature state ----------------------------------------------------
$featWSL = Get-FeatureState 'Microsoft-Windows-Subsystem-Linux'
$featVMP = Get-FeatureState 'VirtualMachinePlatform'
$wslExe  = Get-WslExe
$wslVer  = Get-WslVersion $wslExe
$wslFun  = Test-WslFunctional $wslExe

function Show-FeatureLine {
    param([string]$Label, [string]$State)
    switch ($State) {
        'Enabled' { Write-Ok "$Label : Enabled" }
        'Unknown' { Write-Info "$Label : unknown (needs elevation to query; will be enabled if missing)" }
        default   { Write-Warn "$Label : $State" }
    }
}
Show-FeatureLine 'Windows Subsystem for Linux feature' $featWSL
Show-FeatureLine 'Virtual Machine Platform feature   ' $featVMP

if ($wslExe) {
    if ($wslVer) { Write-Ok "wsl.exe present (version $wslVer)" }
    else         { Write-Warn 'wsl.exe present but the Store WSL app is missing/old (no `wsl --version`).' }
} else {
    Write-Warn 'wsl.exe not found.'
}

$disabledStates = @('Disabled', 'DisabledWithPayloadRemoved')
$needSetup = (-not $wslFun) -or
             ($featWSL -in $disabledStates) -or
             ($featVMP -in $disabledStates) -or
             (-not $wslExe)

# --- Remediate if needed ----------------------------------------------------
if ($needSetup) {
    Write-Step 'Some prerequisites are missing'
    Write-Palette '  This will enable the required Windows features and install/update WSL.' dim
    if (-not (Test-Admin)) {
        Write-Palette '  Administrator rights are required -- a UAC prompt will appear.' dim
    }
    if (-not (Confirm-Yes 'Proceed with prerequisite setup?' $true)) { Die 'Aborted by user.' }

    $code = Invoke-ElevatedSetup $ElevatedSetupScript
    if ($code -eq 3010) {
        Write-Warn 'Windows features were enabled but a RESTART is required.'
        Write-Palette '  Reboot, then re-run this script to finish installing NixOS.' yellow
        exit 3010
    }
    if ($code -ne 0) { Die "Prerequisite setup failed (exit code $code)." }

    # Re-probe after remediation.
    $wslExe = Get-WslExe
    $wslVer = Get-WslVersion $wslExe
    $wslFun = Test-WslFunctional $wslExe
    if (-not $wslFun) {
        Write-Warn 'WSL is still not fully functional. A reboot is often required after first enabling it.'
        Write-Palette '  Please reboot and re-run this script.' yellow
        exit 3010
    }
    Write-Ok 'Prerequisites are now in place.'
} else {
    Write-Ok 'All prerequisites satisfied.'
}

if (-not $wslExe) { Die 'wsl.exe is unavailable; cannot continue.' }

# Ensure new distributions default to WSL2.
& $wslExe --set-default-version 2 *> $null

# --- Decide install method --------------------------------------------------
$customName     = ($Name -ne 'NixOS')
$customLocation = [bool]$InstallLocation
$canFromFile    = ($wslVer -and $wslVer -ge $MinWslVersion)

if ($Method -eq 'Auto') {
    if (-not $canFromFile) {
        $Method = 'Import'
    } elseif ($customName -or $customLocation) {
        $Method = 'Import'
    } elseif (-not $NonInteractive) {
        Write-Step 'Choose installation method'
        Write-Palette '  [1] Recommended - wsl --install --from-file' purple
        Write-Host '        Registers as "NixOS" in the default location and runs NixOS-WSL first-boot setup.'
        Write-Palette '  [2] Custom      - wsl --import' purple
        Write-Host '        Pick the distro name and folder. First boot lands you as root.'
        $sel = (Read-Host 'Selection [1]').Trim()
        $Method = if ($sel -eq '2') { 'Import' } else { 'FromFile' }
    } else {
        $Method = 'FromFile'
    }
}

if ($Method -eq 'FromFile' -and -not $canFromFile) {
    Write-Warn "`wsl --install --from-file` needs WSL >= $MinWslVersion (have $wslVer); using --import instead."
    $Method = 'Import'
}
if ($Method -eq 'FromFile' -and $customName) {
    Write-Warn "--from-file always registers the distro as 'NixOS'; ignoring -Name '$Name'."
    $Name = 'NixOS'
}

$targetName = if ($Method -eq 'FromFile') { 'NixOS' } else { $Name }
Write-Ok "Install method: $Method  (distribution name: $targetName)"

# --- Guard against clobbering an existing distro ----------------------------
$existing = Get-WslDistros $wslExe
if ($existing -contains $targetName) {
    Write-Warn "A WSL distribution named '$targetName' already exists."
    if ($NonInteractive) {
        Die "Refusing to overwrite '$targetName'. Re-run with a different -Name, or `wsl --unregister $targetName` first."
    }
    Write-Palette '  [1] Unregister it and reinstall  (DESTROYS its data)' purple
    Write-Palette '  [2] Pick a different name         (switches to --import)' purple
    Write-Palette '  [3] Abort' purple
    switch ((Read-Host 'Selection [3]').Trim()) {
        '1' {
            if (-not (Confirm-Yes "Permanently delete the existing '$targetName' distribution?" $false)) { Die 'Aborted.' }
            & $wslExe --unregister "$targetName"
            if ($LASTEXITCODE -ne 0) { Die 'wsl --unregister failed.' }
            Write-Ok "Unregistered '$targetName'."
        }
        '2' {
            $new = (Read-Host 'New distribution name').Trim()
            if (-not $new) { Die 'No name provided.' }
            if ($existing -contains $new) { Die "'$new' also already exists." }
            $Name = $new; $Method = 'Import'; $targetName = $new
            Write-Ok "Will install as '$targetName' via --import."
        }
        default { Die 'Aborted.' }
    }
}

# --- Resolve release + download ---------------------------------------------
Write-Step 'Resolving release'
$release = Get-Release $Tag
$tagName = $release.tag_name
$asset   = $release.assets | Where-Object { $_.name -eq $assetName }          | Select-Object -First 1
$shasum  = $release.assets | Where-Object { $_.name -eq "$assetName.sha256" } | Select-Object -First 1
if (-not $asset) { Die "Release '$tagName' has no asset named '$assetName'." }
$sizeMB = [math]::Round($asset.size / 1MB, 1)
Write-Ok "NixOS-WSL $tagName -> $assetName ($sizeMB MB)"

if (-not (Test-Path $DownloadDir)) { New-Item -ItemType Directory -Force -Path $DownloadDir | Out-Null }
$image    = Join-Path $DownloadDir $assetName
$imageSha = "$image.sha256"

Write-Step "Downloading to $image"
Save-File $asset.browser_download_url $image
Write-Ok "Downloaded $assetName"

if ($shasum) {
    Save-File $shasum.browser_download_url $imageSha
    Test-Checksum $image $imageSha
} else {
    Write-Warn 'No .sha256 published for this asset; skipping checksum verification.'
}

# --- Install ----------------------------------------------------------------
Write-Step "Installing '$targetName' (method: $Method)"
if ($Method -eq 'FromFile') {
    Write-Info "wsl --install --from-file `"$image`""
    & $wslExe --install --from-file "$image"
    if ($LASTEXITCODE -ne 0) { Die "wsl --install --from-file failed (exit $LASTEXITCODE)." }
} else {
    if (-not $InstallLocation) { $InstallLocation = Join-Path $env:LOCALAPPDATA "WSL\$targetName" }
    New-Item -ItemType Directory -Force -Path $InstallLocation | Out-Null
    Write-Info "wsl --import `"$targetName`" `"$InstallLocation`" `"$image`" --version 2"
    & $wslExe --import "$targetName" "$InstallLocation" "$image" --version 2
    if ($LASTEXITCODE -ne 0) { Die "wsl --import failed (exit $LASTEXITCODE)." }
    Write-Ok "Imported to $InstallLocation"
}
Write-Ok "Installed distribution '$targetName'."

if (-not $KeepDownload) {
    Remove-Item -LiteralPath $image -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $imageSha -Force -ErrorAction SilentlyContinue
}

# --- Post-install -----------------------------------------------------------
Write-Step 'Installed WSL distributions'
& $wslExe --list --verbose

if ($SetDefault -or (-not $NonInteractive -and (Confirm-Yes "Set '$targetName' as the default WSL distribution?" $false))) {
    & $wslExe --set-default "$targetName"
    if ($LASTEXITCODE -eq 0) { Write-Ok "'$targetName' is now the default." }
}

Write-Step 'Next steps'
Write-Host "  * Enter NixOS:        wsl -d $targetName"
Write-Host '  * Update channels:    sudo nix-channel --update'
Write-Host '  * Edit config:        sudo nano /etc/nixos/configuration.nix'
Write-Host '  * Apply config:       sudo nixos-rebuild switch'
if ($Method -eq 'Import') {
    Write-Palette '  * Note: --import boots you as root. Define your user in configuration.nix' yellow
    Write-Palette "          (wsl.defaultUser), rebuild, then `wsl -t $targetName` to restart it." yellow
}
Write-Palette '  * Docs:               https://nix-community.github.io/NixOS-WSL/' dim

if ($Launch -or (-not $NonInteractive -and (Confirm-Yes "Launch '$targetName' now?" $true))) {
    Write-Step "Launching '$targetName'"
    & $wslExe -d "$targetName"
}

Write-Host ''; Write-Palette 'Done.' green
