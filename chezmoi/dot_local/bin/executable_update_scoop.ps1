$ErrorActionPreference = "Stop"

function Get-ScoopShim {
  $command = Get-Command scoop -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source -First 1
  if ($command) { return $command }

  $candidate = Join-Path $HOME "scoop\shims\scoop.ps1"
  if (Test-Path $candidate) { return $candidate }

  return $null
}

$scoopShim = Get-ScoopShim
if (-not $scoopShim) {
  Write-Error "Scoop is not installed."
  exit 1
}

Write-Host "Updating Scoop..."
& $scoopShim update

Write-Host "Updating all packages..."
& $scoopShim update --all

Write-Host "Removing old package versions..."
& $scoopShim cleanup --all

Write-Host "Scoop update complete."
