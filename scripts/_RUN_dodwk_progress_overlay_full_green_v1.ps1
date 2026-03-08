param([Parameter(Mandatory=$true)][string]$RepoRoot)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path

$files = @(
  (Join-Path $RepoRoot 'scripts\dodwk_verify_progress_overlay_v1.ps1'),
  (Join-Path $RepoRoot 'scripts\_selftest_dodwk_progress_overlay_v1.ps1'),
  (Join-Path $RepoRoot 'scripts\_RUN_dodwk_progress_overlay_full_green_v1.ps1')
)

foreach($f in $files){
  $tok = $null
  $err = $null
  [void][System.Management.Automation.Language.Parser]::ParseFile($f,[ref]$tok,[ref]$err)
  if($err -and $err.Count -gt 0){
    throw ('PARSE_FAIL: ' + $f)
  }
}

& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File (Join-Path $RepoRoot 'scripts\_selftest_dodwk_progress_overlay_v1.ps1') -RepoRoot $RepoRoot | Out-Host
if($LASTEXITCODE -ne 0){
  throw ('RUNNER_SELFTEST_FAILED exit=' + $LASTEXITCODE)
}

Write-Host 'DODWK_PROGRESS_OVERLAY_ALL_GREEN' -ForegroundColor Green
