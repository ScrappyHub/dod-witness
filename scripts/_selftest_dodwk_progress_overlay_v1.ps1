param([Parameter(Mandatory=$true)][string]$RepoRoot)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$Verifier = Join-Path $RepoRoot 'scripts\dodwk_verify_progress_overlay_v1.ps1'
$Overlay  = Join-Path $RepoRoot 'contracts\dodwk.progress_overlay.v1.sample.json'
$OutDir   = Join-Path $RepoRoot 'proofs\receipts\dodwk_progress_overlay_selftest'

if(-not (Test-Path -LiteralPath $OutDir -PathType Container)){
  New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
}

$OutPath = Join-Path $OutDir 'progress_report.v1.json'

& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $Verifier -RepoRoot $RepoRoot -OverlayPath $Overlay -OutPath $OutPath | Out-Host
if($LASTEXITCODE -ne 0){
  throw ('SELFTEST_VERIFY_FAILED exit=' + $LASTEXITCODE)
}
if(-not (Test-Path -LiteralPath $OutPath -PathType Leaf)){
  throw ('SELFTEST_MISSING_REPORT: ' + $OutPath)
}

$report = Get-Content -LiteralPath $OutPath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
if([string]$report.schema -ne 'dodwk.progress_report.v1'){
  throw 'SELFTEST_BAD_SCHEMA'
}
if([double]$report.progress_percent -lt 100.0){
  throw ('SELFTEST_PROGRESS_NOT_GREEN: ' + [string]$report.progress_percent)
}

Write-Host 'SELFTEST_DODWK_PROGRESS_OVERLAY_OK' -ForegroundColor Green
