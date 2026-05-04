# PowerShell Profile — Monokai Spectrum
# Mirrors the zsh/starship configuration managed by home-manager.

# ── Monokai Spectrum palette ────────────────────────────────────────────────
$Monokai = @{
  Base00 = '#222222'  # Default background
  Base01 = '#363537'  # Lighter background
  Base02 = '#525053'  # Selection background
  Base03 = '#69676c'  # Comments
  Base04 = '#8b888f'  # Dark foreground
  Base05 = '#bab6c0'  # Default foreground
  Base06 = '#fbf8ff'  # Light foreground
  Base07 = '#f7f1ff'  # Light background
  Base08 = '#FC618D'  # Pink/red — variables
  Base09 = '#fd9353'  # Orange — constants
  Base0A = '#FCE566'  # Yellow — classes
  Base0B = '#7BD88F'  # Green — strings
  Base0C = '#5AD4E6'  # Cyan — support
  Base0D = '#948ae3'  # Purple — functions
  Base0E = '#fc618d'  # Pink/red — keywords
  Base0F = '#fef20a'  # Bright yellow — deprecated
}

# ── XDG-style directories ──────────────────────────────────────────────────
if (-not $env:XDG_BIN_HOME)    { $env:XDG_BIN_HOME    = Join-Path $HOME '.local\bin' }
if (-not $env:XDG_CACHE_HOME)  { $env:XDG_CACHE_HOME  = Join-Path $HOME '.cache' }
if (-not $env:XDG_CONFIG_HOME) { $env:XDG_CONFIG_HOME = Join-Path $HOME '.config' }
if (-not $env:XDG_DATA_HOME)   { $env:XDG_DATA_HOME   = Join-Path $HOME '.local\share' }
if (-not $env:XDG_LIB_HOME)    { $env:XDG_LIB_HOME    = Join-Path $HOME '.local\lib' }
if (-not $env:XDG_STATE_HOME)  { $env:XDG_STATE_HOME  = Join-Path $HOME '.local\state' }

# ── Editor ──────────────────────────────────────────────────────────────────
$env:EDITOR = 'nvim'

# ── PSReadLine ──────────────────────────────────────────────────────────────
if (Get-Module -ListAvailable PSReadLine) {
  Set-PSReadLineOption -EditMode Vi
  Set-PSReadLineOption -PredictionSource History
  Set-PSReadLineOption -PredictionViewStyle ListView
  Set-PSReadLineOption -HistoryNoDuplicates:$true
  Set-PSReadLineOption -MaximumHistoryCount 90000

  Set-PSReadLineOption -Colors @{
    Command            = $Monokai.Base0B  # green
    Parameter          = $Monokai.Base09  # orange
    Operator           = $Monokai.Base08  # pink/red
    Variable           = $Monokai.Base0C  # cyan
    String             = $Monokai.Base0A  # yellow
    Number             = $Monokai.Base09  # orange
    Type               = $Monokai.Base0D  # purple
    Comment            = $Monokai.Base03  # grey
    Keyword            = $Monokai.Base08  # pink/red
    Error              = $Monokai.Base08  # pink/red
    Member             = $Monokai.Base0C  # cyan
    InlinePrediction   = $Monokai.Base03  # grey
    ListPrediction     = $Monokai.Base0D  # purple
    ListPredictionSelected = $Monokai.Base0A # yellow
    Selection          = $Monokai.Base02  # selection background
    Emphasis           = $Monokai.Base0A  # yellow
    Default            = $Monokai.Base05  # default foreground
  }

  # Ctrl+R for reverse history search via fzf when available
  if (Get-Command fzf -ErrorAction SilentlyContinue) {
    Set-PSReadLineKeyHandler -Chord 'Ctrl+r' -ScriptBlock {
      $line = Get-Content (Get-PSReadLineOption).HistorySavePath |
        Select-Object -Unique |
        & fzf --tac --no-sort --layout=reverse --height=40%
      if ($line) {
        [Microsoft.PowerShell.PSConsoleReadLine]::RevertLine()
        [Microsoft.PowerShell.PSConsoleReadLine]::Insert($line)
      }
    }
  }
}

# ── Tool aliases ────────────────────────────────────────────────────────────
# bat
if (Get-Command bat -ErrorAction SilentlyContinue) {
  $env:BAT_THEME = 'Monokai Extended'
  function cat { bat --pager=never @args }
}

# eza (ls replacement)
if (Get-Command eza -ErrorAction SilentlyContinue) {
  function ls  { eza --icons @args }
  function l   { eza -lbF --git --icons @args }
  function ll  { eza -lbGF --git --icons @args }
  function ltr { eza -lbGd --git --sort=modified --icons @args }
  function la  { eza -lbhHigUmuSa --git --color-scale --icons @args }
}

# fd
if (Get-Command fd -ErrorAction SilentlyContinue) {
  $env:FZF_DEFAULT_COMMAND = 'fd --type f --hidden --follow --exclude .git'
}

# fzf
if (Get-Command fzf -ErrorAction SilentlyContinue) {
  $env:FZF_DEFAULT_OPTS = @(
    "--color=bg+:$($Monokai.Base01)"
    "--color=fg+:$($Monokai.Base06)"
    "--color=fg:$($Monokai.Base05)"
    "--color=header:$($Monokai.Base0D)"
    "--color=hl+:$($Monokai.Base0A)"
    "--color=hl:$($Monokai.Base0A)"
    "--color=info:$($Monokai.Base0C)"
    "--color=marker:$($Monokai.Base0B)"
    "--color=pointer:$($Monokai.Base08)"
    "--color=prompt:$($Monokai.Base0D)"
    "--color=spinner:$($Monokai.Base0B)"
    '--height=40%'
    '--layout=reverse'
    '--border'
  ) -join ' '
}

# ripgrep
if (Get-Command rg -ErrorAction SilentlyContinue) {
  function grep { rg --color=auto @args }
}

# zoxide
if (Get-Command zoxide -ErrorAction SilentlyContinue) {
  Invoke-Expression (& zoxide init powershell)
}

# direnv
if (Get-Command direnv -ErrorAction SilentlyContinue) {
  $env:DIRENV_LOG_FORMAT = ''
}

# ── Starship prompt ─────────────────────────────────────────────────────────
$env:STARSHIP_CONFIG = Join-Path $HOME '.config\starship.toml'

$starship = Get-Command starship -ErrorAction SilentlyContinue |
  Select-Object -ExpandProperty Source -First 1
if ([string]::IsNullOrWhiteSpace($starship)) {
  $starship = Resolve-Path (Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Packages\Starship.Starship_*\starship.exe') -ErrorAction SilentlyContinue |
    Select-Object -ExpandProperty Path -First 1
}

if (-not [string]::IsNullOrWhiteSpace($starship)) {
  Invoke-Expression (& $starship init powershell)
} else {
  Write-Warning 'starship is not installed. Install it with: winget install --id Starship.Starship -e --scope user'
}
