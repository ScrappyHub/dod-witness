param(
  [string]$Repo = "."
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Die([string]$m){
  Write-Host ("DODWK_TIER0_FULL_GREEN_FAIL: " + $m) -ForegroundColor Red
  exit 1
}

function Ensure-Dir([string]$p){
  if(-not (Test-Path -LiteralPath $p -PathType Container)){
    New-Item -ItemType Directory -Force -Path $p | Out-Null
  }
}

function Write-Utf8NoBomLf([string]$Path,[string]$Text){
  $dir = Split-Path -Parent $Path
  if($dir -and -not (Test-Path -LiteralPath $dir -PathType Container)){
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
  }

  $enc = New-Object System.Text.UTF8Encoding($false)
  $t = $Text.Replace("`r`n","`n").Replace("`r","`n")
  if(-not $t.EndsWith("`n")){ $t += "`n" }
  [System.IO.File]::WriteAllText($Path,$t,$enc)
}

function Sha256-File([string]$Path){
  if(-not (Test-Path -LiteralPath $Path -PathType Leaf)){ return "" }
  $sha = [System.Security.Cryptography.SHA256]::Create()
  try{
    $bytes = [System.IO.File]::ReadAllBytes((Resolve-Path -LiteralPath $Path).Path)
    return (($sha.ComputeHash($bytes) | ForEach-Object { $_.ToString("x2") }) -join "")
  } finally {
    $sha.Dispose()
  }
}

function Parse-Gate([string]$Path){
  if(-not (Test-Path -LiteralPath $Path -PathType Leaf)){
    Die ("SCRIPT_MISSING:" + $Path)
  }

  [void][ScriptBlock]::Create((Get-Content -Raw -LiteralPath $Path))
}

function Run-Captured([string]$Name,[string]$ScriptPath,[string[]]$ChildArgs,[string]$RunRoot){
  Parse-Gate $ScriptPath

  Write-Host ("STEP_START: " + $Name) -ForegroundColor Cyan

  $stdout = Join-Path $RunRoot ($Name + ".stdout.txt")
  $stderr = Join-Path $RunRoot ($Name + ".stderr.txt")

  $argList = @(
    "-NoProfile",
    "-NonInteractive",
    "-ExecutionPolicy",
    "Bypass",
    "-File",
    $ScriptPath
  ) + $ChildArgs

  $p = Start-Process `
    -FilePath "powershell.exe" `
    -ArgumentList $argList `
    -NoNewWindow `
    -Wait `
    -PassThru `
    -RedirectStandardOutput $stdout `
    -RedirectStandardError $stderr

  $code = $p.ExitCode

  if($code -eq 0){
    Write-Host ("STEP_OK: " + $Name) -ForegroundColor Green
  } else {
    Write-Host ("STEP_FAIL: " + $Name + " exit=" + $code) -ForegroundColor Red
  }

  return @{
    name = $Name
    script = $ScriptPath
    exit_code = $code
    stdout = $stdout
    stderr = $stderr
    stdout_sha256 = Sha256-File $stdout
    stderr_sha256 = Sha256-File $stderr
  }
}

$Root = "C:\dev\dod-witness-kit"
Set-Location $Root

$ResolvedRepo = (Resolve-Path -LiteralPath $Repo).Path

$RunId = Get-Date -Format "yyyyMMdd_HHmmss"
$RunRoot = Join-Path ".\proofs\receipts\dodwk_tier0_full_green" $RunId
Ensure-Dir $RunRoot

$tier0Scripts = @(
  "$Root\scripts\_RUN_dodwk_static_setup_v1.ps1",
  "$Root\scripts\dodwk_governance_snapshot_v1.ps1",
  "$Root\scripts\dodwk_governance_replay_verify_v1.ps1",
  "$Root\scripts\_RUN_dodwk_governance_replay_v1.ps1",
  "$Root\scripts\dodwk_canonicalize_topology_v1.ps1",
  "$Root\scripts\dodwk_drift_v2.ps1",
  "$Root\scripts\_selftest_dodwk_negative_replay_vectors_v1.ps1"
)

foreach($s in $tier0Scripts){
  Parse-Gate $s
}

$steps = @()

$steps += Run-Captured "static_setup" "$Root\scripts\_RUN_dodwk_static_setup_v1.ps1" @(
  "-Repo", $ResolvedRepo,
  "-Wbs", ".\specs\wbs.v1.json",
  "-Overlay", ".\specs\overlay.v1.json"
) $RunRoot

if([int]$steps[-1].exit_code -ne 0){ Die "STATIC_SETUP_FAILED" }

$steps += Run-Captured "snapshot" "$Root\scripts\dodwk_governance_snapshot_v1.ps1" @() $RunRoot
if([int]$steps[-1].exit_code -ne 0){ Die "SNAPSHOT_FAILED" }

$latestSnapshot = Get-ChildItem ".\dodwk\governance_snapshots" -Directory |
  Sort-Object LastWriteTime -Descending |
  Select-Object -First 1

if($null -eq $latestSnapshot){ Die "NO_SNAPSHOT_AFTER_CREATE" }

$steps += Run-Captured "replay_verify" "$Root\scripts\dodwk_governance_replay_verify_v1.ps1" @(
  "-SnapshotRoot", $latestSnapshot.FullName
) $RunRoot

if([int]$steps[-1].exit_code -ne 0){ Die "REPLAY_VERIFY_FAILED" }

$steps += Run-Captured "replay" "$Root\scripts\_RUN_dodwk_governance_replay_v1.ps1" @(
  "-SnapshotRoot", $latestSnapshot.FullName,
  "-Repo", $ResolvedRepo
) $RunRoot

if([int]$steps[-1].exit_code -ne 0){ Die "REPLAY_FAILED" }

$steps += Run-Captured "negative_replay_vectors" "$Root\scripts\_selftest_dodwk_negative_replay_vectors_v1.ps1" @(
  "-SnapshotRoot", $latestSnapshot.FullName
) $RunRoot

if([int]$steps[-1].exit_code -ne 0){ Die "NEGATIVE_REPLAY_VECTORS_FAILED" }

$negStdout = Get-Content -Raw -LiteralPath $steps[-1].stdout
if($negStdout -notmatch "DODWK_NEGATIVE_REPLAY_VECTORS_OK"){
  Die "NEGATIVE_REPLAY_VECTORS_OK_TOKEN_MISSING"
}

$replayStdout = Get-Content -Raw -LiteralPath $steps[-2].stdout
if($replayStdout -notmatch "DODWK_GOVERNANCE_REPLAY_OK"){
  Die "REPLAY_OK_TOKEN_MISSING"
}

$latestReplay = Get-ChildItem ".\dodwk\replay" -Directory |
  Where-Object { $_.Name -like "governance_replay_*" } |
  Sort-Object LastWriteTime -Descending |
  Select-Object -First 1

$replaySummary = ""
if($null -ne $latestReplay){
  $summaryPath = Join-Path $latestReplay.FullName "governance_replay.summary.md"
  if(Test-Path -LiteralPath $summaryPath -PathType Leaf){
    Copy-Item -LiteralPath $summaryPath -Destination (Join-Path $RunRoot "governance_replay.summary.md") -Force
    $replaySummary = (Resolve-Path -LiteralPath (Join-Path $RunRoot "governance_replay.summary.md")).Path
  }
}

$latestSurface = Get-ChildItem ".\proofs\receipts\dodwk_governance_surface" -Directory |
  Sort-Object LastWriteTime -Descending |
  Select-Object -First 1

$surfaceSummary = ""
if($null -ne $latestSurface){
  $surfacePath = Join-Path $latestSurface.FullName "governance_surface.summary.md"
  if(Test-Path -LiteralPath $surfacePath -PathType Leaf){
    Copy-Item -LiteralPath $surfacePath -Destination (Join-Path $RunRoot "governance_surface.summary.md") -Force
    $surfaceSummary = (Resolve-Path -LiteralPath (Join-Path $RunRoot "governance_surface.summary.md")).Path
  }
}

$receipt = @{
  schema = "dodwk.tier0_full_green.receipt.v1"
  run_id = $RunId
  repo = $ResolvedRepo
  status = "pass"
  snapshot_root = $latestSnapshot.FullName
  replay_summary = $replaySummary
  governance_surface_summary = $surfaceSummary
  scripts_parse_gated = @($tier0Scripts).Count
  steps = $steps
  static_proof = $true
  replay_verified = $true
  negative_replay_verified = $true
  ai_required = $false
  proof_status = "tier0_full_green"
}

Write-Utf8NoBomLf (Join-Path $RunRoot "tier0_full_green.receipt.v1.json") ($receipt | ConvertTo-Json -Depth 60)

$hashRows = @()
Get-ChildItem -LiteralPath $RunRoot -File |
  Where-Object { $_.Name -ne "sha256sums.txt" } |
  Sort-Object Name |
  ForEach-Object {
    $hashRows += ((Sha256-File $_.FullName) + "  " + $_.Name)
  }

Write-Utf8NoBomLf (Join-Path $RunRoot "sha256sums.txt") ($hashRows -join "`n")

Write-Host "DODWK_TIER0_FULL_GREEN" -ForegroundColor Green
Write-Host ("RUN_ROOT: " + (Resolve-Path -LiteralPath $RunRoot).Path)
Write-Host ("SNAPSHOT_ROOT: " + $latestSnapshot.FullName)
Write-Host "REPLAY_VERIFIED: true"
Write-Host "NEGATIVE_REPLAY_VERIFIED: true"
exit 0
