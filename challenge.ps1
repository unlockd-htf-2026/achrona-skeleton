# Windows without Git Bash:  .\challenge.ps1 <id>   or   .\challenge.ps1 all
# The same as ./challenge.
param([Parameter(Mandatory = $true)][string]$Id)
Set-Location $PSScriptRoot
$useFvm = [bool](Get-Command fvm -ErrorAction SilentlyContinue)
function flutter {
  if ($useFvm) { fvm flutter @args }
  else { & (Get-Command flutter -CommandType Application | Select-Object -First 1) @args }
}
function Run([string]$c) {
  switch ($c) {
    'base-01' { flutter test test/level_spec_test.dart test/level_reach_test.dart }
    'base-02' { flutter test test/challenges/base_02_camera_test.dart }
    'base-03' { flutter test test/challenges/base_03_facing_test.dart }
    'build-01' { flutter test test/challenges/build_01_feet_test.dart }
    'build-02' { flutter test test/challenges/build_02_lean_test.dart }
    'online-01' { flutter test test/run_link_test.dart --plain-name 'RunLink.submit' }
    default { Write-Host "unknown challenge: $c (see CHALLENGES.md)"; exit 2 }
  }
}
if ($Id -eq 'all') {
  foreach ($c in @('base-01', 'base-02', 'base-03', 'build-01', 'build-02', 'online-01')) {
    Run $c *> $null
    if ($LASTEXITCODE -eq 0) { Write-Host "GREEN $c" } else { Write-Host "red   $c" }
  }
} else {
  Run $Id
  exit $LASTEXITCODE
}
