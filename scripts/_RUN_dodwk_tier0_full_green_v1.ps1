param([Parameter(Mandatory=$true)][string]$RepoRoot)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

function Parse-GateFile([string]$Path){
  if(-not (Test-Path -LiteralPath $Path -PathType Leaf)){ throw ("PARSE_GATE_MISSING: " + $Path) }
  $tok = $null
  $err = $null
  [void][System.Management.Automation.Language.Parser]::ParseFile($Path,[ref]$tok,[ref]$err)
  if($err -and @(@($err)).Count -gt 0){ throw ("PARSE_FAIL: " + $Path) }
}

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$files = @(
  (Join-Path $RepoRoot "scripts\dodwk_verify_progress_overlay_v1.ps1"),
  (Join-Path $RepoRoot "scripts\_selftest_dodwk_progress_overlay_v1.ps1"),
  (Join-Path $RepoRoot "scripts\_RUN_dodwk_progress_overlay_full_green_v1.ps1"),
  (Join-Path $RepoRoot "scripts\dodwk_certify_progress_report_v1.ps1"),
  (Join-Path $RepoRoot "scripts\dodwk_verify_certification_v1.ps1"),
  (Join-Path $RepoRoot "scripts\_selftest_dodwk_negative_vectors_v1.ps1"),
  (Join-Path $RepoRoot "scripts\_RUN_dodwk_tier0_full_green_v1.ps1")
)
foreach($f in $files){ Parse-GateFile $f }

& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File (Join-Path $RepoRoot "scripts\_RUN_dodwk_progress_overlay_full_green_v1.ps1") -RepoRoot $RepoRoot | Out-Host
if($LASTEXITCODE -ne 0){ throw ("TIER0_PROGRESS_RUNNER_FAILED exit=" + $LASTEXITCODE) }

& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File (Join-Path $RepoRoot "scripts\_selftest_dodwk_negative_vectors_v1.ps1") -RepoRoot $RepoRoot | Out-Host
if($LASTEXITCODE -ne 0){ throw ("TIER0_NEGATIVE_SELFTEST_FAILED exit=" + $LASTEXITCODE) }

$ReportPath = Join-Path $RepoRoot "proofs\receipts\dodwk_progress_overlay_selftest\progress_report.v1.json"
$BundleDir  = Join-Path $RepoRoot "proofs\evidence\dodwk_progress_overlay_certification"
& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File (Join-Path $RepoRoot "scripts\dodwk_certify_progress_report_v1.ps1") -RepoRoot $RepoRoot -ReportPath $ReportPath -OutDir $BundleDir | Out-Host
if($LASTEXITCODE -ne 0){ throw ("TIER0_CERTIFY_FAILED exit=" + $LASTEXITCODE) }

& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File (Join-Path $RepoRoot "scripts\dodwk_verify_certification_v1.ps1") -BundleDir $BundleDir | Out-Host
if($LASTEXITCODE -ne 0){ throw ("TIER0_VERIFY_CERT_FAILED exit=" + $LASTEXITCODE) }

Write-Host "DODWK_TIER0_FULL_GREEN" -ForegroundColor Green
