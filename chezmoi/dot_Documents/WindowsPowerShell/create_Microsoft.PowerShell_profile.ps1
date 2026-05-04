# Windows PowerShell 5.1 — delegate to the shared profile used by PowerShell 7.
$sharedProfile = Join-Path $HOME 'Documents\PowerShell\Microsoft.PowerShell_profile.ps1'
if (Test-Path $sharedProfile) {
  . $sharedProfile
}
