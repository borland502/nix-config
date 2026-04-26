param(
  [string]$WindowsTerminalPackageFamily = "Microsoft.WindowsTerminal_8wekyb3d8bbwe",
  [string]$TerminalFontFace = "FiraCode Nerd Font Mono"
)

$ErrorActionPreference = "Stop"

function Get-ScoopShim {
  $command = Get-Command scoop -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source -First 1
  if ($command) {
    return $command
  }

  $candidate = Join-Path $HOME "scoop\shims\scoop.ps1"
  if (Test-Path $candidate) {
    return $candidate
  }

  return $null
}

function Ensure-Scoop {
  $scoop = Get-ScoopShim
  if ($scoop) {
    Write-Host "Scoop already installed at $scoop"
    return $scoop
  }

  Write-Host "Installing Scoop..."
  Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser -Force
  Invoke-RestMethod -Uri "https://get.scoop.sh" | Invoke-Expression

  $scoop = Get-ScoopShim
  if (-not $scoop) {
    throw "Scoop installation completed but scoop shim was not found."
  }

  return $scoop
}

function Invoke-Scoop {
  param(
    [Parameter(Mandatory = $true)]
    [string]$ScoopShim,

    [Parameter(Mandatory = $true, ValueFromRemainingArguments = $true)]
    [string[]]$Arguments
  )

  & $ScoopShim @Arguments
}

function Ensure-ScoopBucket {
  param(
    [string]$ScoopShim,
    [string]$BucketName
  )

  $bucketList = Invoke-Scoop -ScoopShim $ScoopShim bucket list | Out-String
  if ($bucketList -match "(^|\s)$([regex]::Escape($BucketName))(\s|$)") {
    Write-Host "Scoop bucket '$BucketName' already present"
    return
  }

  Write-Host "Adding Scoop bucket '$BucketName'"
  Invoke-Scoop -ScoopShim $ScoopShim bucket add $BucketName | Out-Host
}

function Resolve-FontManifest {
  param(
    [string]$ScoopShim
  )

  $candidates = @(
    "FiraCode-NF-Mono",
    "FiraCode-NF",
    "firacode-nf-mono",
    "firacode-nf"
  )

  foreach ($candidate in $candidates) {
    try {
      Invoke-Scoop -ScoopShim $ScoopShim info $candidate *> $null
      return $candidate
    } catch {
    }
  }

  throw "Unable to find a Scoop manifest for the desired FiraCode Nerd Font."
}

function Ensure-ScoopPackage {
  param(
    [string]$ScoopShim,
    [string]$PackageName
  )

  $installed = Invoke-Scoop -ScoopShim $ScoopShim list | Out-String
  if ($installed -match "(^|\s)$([regex]::Escape($PackageName))(\s|$)") {
    Write-Host "Scoop package '$PackageName' already installed"
    return
  }

  Write-Host "Installing Scoop package '$PackageName'"
  Invoke-Scoop -ScoopShim $ScoopShim install $PackageName | Out-Host
}

function Normalize-FontToken {
  param(
    [string]$FontName
  )

  if ([string]::IsNullOrWhiteSpace($FontName)) {
    return ""
  }

  return (($FontName -replace "[^a-zA-Z0-9]", "").ToLowerInvariant())
}

function Resolve-TerminalFontFace {
  param(
    [string]$RequestedFontFace,
    [string]$InstalledManifest
  )

  $requestedToken = Normalize-FontToken -FontName $RequestedFontFace
  $monoTokens = @(
    "firacodenerdfontmono",
    "firacodenfmono"
  )

  if ($InstalledManifest -match "(?i)mono") {
    if (-not [string]::IsNullOrWhiteSpace($RequestedFontFace)) {
      return $RequestedFontFace
    }
    return "FiraCode Nerd Font Mono"
  }

  if ($monoTokens -contains $requestedToken) {
    Write-Warning "Installed manifest '$InstalledManifest' does not provide the Mono family. Falling back to 'FiraCode Nerd Font'."
    return "FiraCode Nerd Font"
  }

  if (-not [string]::IsNullOrWhiteSpace($RequestedFontFace)) {
    return $RequestedFontFace
  }

  return "FiraCode Nerd Font"
}

function Should-UpdateFiraCodeFont {
  param(
    [AllowNull()]
    [object]$CurrentValue
  )

  if ($null -eq $CurrentValue) {
    return $false
  }

  $token = Normalize-FontToken -FontName ([string]$CurrentValue)
  if ([string]::IsNullOrWhiteSpace($token)) {
    return $false
  }

  return @(
    "firacodenerdfontmono",
    "firacodenerdfont",
    "firacodenerdfontpropo",
    "firacodenfmono",
    "firacodenf"
  ) -contains $token
}

function Set-WindowsTerminalFont {
  param(
    [string]$PackageFamily,
    [string]$FontFace
  )

  $settingsPath = Join-Path $env:LOCALAPPDATA "Packages\$PackageFamily\LocalState\settings.json"
  if (-not (Test-Path $settingsPath)) {
    Write-Warning "Windows Terminal settings file not found at $settingsPath"
    return
  }

  $settings = Get-Content -Raw -Path $settingsPath | ConvertFrom-Json
  if (-not $settings.profiles) {
    $settings | Add-Member -MemberType NoteProperty -Name profiles -Value ([pscustomobject]@{})
  }
  if (-not $settings.profiles.defaults) {
    $settings.profiles | Add-Member -MemberType NoteProperty -Name defaults -Value ([pscustomobject]@{})
  }

  $fontObject = $settings.profiles.defaults.font
  if ($null -eq $fontObject -or $fontObject -isnot [pscustomobject]) {
    if ($settings.profiles.defaults.PSObject.Properties.Match("font").Count -gt 0) {
      $settings.profiles.defaults.PSObject.Properties.Remove("font")
    }
    $fontObject = [pscustomobject]@{}
    $settings.profiles.defaults | Add-Member -MemberType NoteProperty -Name font -Value $fontObject
  }

  $fontObject | Add-Member -MemberType NoteProperty -Name face -Value $FontFace -Force
  $settings.profiles.defaults | Add-Member -MemberType NoteProperty -Name fontFace -Value $FontFace -Force

  $profilesList = $settings.profiles.list
  if ($profilesList -is [System.Collections.IEnumerable]) {
    foreach ($profile in $profilesList) {
      if ($null -eq $profile) {
        continue
      }

      if ($profile.PSObject.Properties.Match("fontFace").Count -gt 0 -and (Should-UpdateFiraCodeFont -CurrentValue $profile.fontFace)) {
        $profile | Add-Member -MemberType NoteProperty -Name fontFace -Value $FontFace -Force
      }

      if ($profile.PSObject.Properties.Match("font").Count -gt 0 -and $profile.font -is [pscustomobject]) {
        if ($profile.font.PSObject.Properties.Match("face").Count -gt 0 -and (Should-UpdateFiraCodeFont -CurrentValue $profile.font.face)) {
          $profile.font | Add-Member -MemberType NoteProperty -Name face -Value $FontFace -Force
        }
      }
    }
  }

  $settings | ConvertTo-Json -Depth 100 | Set-Content -Path $settingsPath -Encoding utf8
  Write-Host "Set Windows Terminal default font to '$FontFace'"
}

$scoopShim = Ensure-Scoop
Ensure-ScoopBucket -ScoopShim $scoopShim -BucketName "extras"
Ensure-ScoopBucket -ScoopShim $scoopShim -BucketName "nerd-fonts"

$fontManifest = Resolve-FontManifest -ScoopShim $scoopShim
Ensure-ScoopPackage -ScoopShim $scoopShim -PackageName $fontManifest
$resolvedTerminalFontFace = Resolve-TerminalFontFace -RequestedFontFace $TerminalFontFace -InstalledManifest $fontManifest
Set-WindowsTerminalFont -PackageFamily $WindowsTerminalPackageFamily -FontFace $resolvedTerminalFontFace

Write-Host "Windows bootstrap complete."