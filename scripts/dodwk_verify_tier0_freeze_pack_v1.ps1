param(
  [Parameter(Mandatory=$true)][string]$FreezeRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Fail([string]$m){
  Write-Host ("DODWK_TIER0_FREEZE_PACK_VERIFY_FAIL: " + $m) -ForegroundColor Red
  exit 1
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

$Root = (Resolve-Path -LiteralPath $FreezeRoot).Path

$Manifest = Join-Path $Root "tier0_freeze_pack.manifest.v1.json"
$Summary = Join-Path $Root "tier0_freeze_pack.summary.md"
$Sums = Join-Path $Root "sha256sums.txt"
$Evidence = Join-Path $Root "evidence"
$Snapshot = Join-Path $Root "governance_snapshot"
$Scripts = Join-Path $Root "scripts"

foreach($p in @($Manifest,$Summary,$Sums)){
  if(-not (Test-Path -LiteralPath $p -PathType Leaf)){ Fail ("MISSING_FILE:" + $p) }
}

foreach($p in @($Evidence,$Snapshot,$Scripts)){
  if(-not (Test-Path -LiteralPath $p -PathType Container)){ Fail ("MISSING_DIR:" + $p) }
}

$M = Get-Content -Raw -LiteralPath $Manifest | ConvertFrom-Json

if([string]$M.schema -ne "dodwk.tier0_freeze_pack.v1"){ Fail "BAD_SCHEMA" }
if([bool]$M.replay_verified -ne $true){ Fail "REPLAY_NOT_VERIFIED" }
if([bool]$M.negative_replay_verified -ne $true){ Fail "NEGATIVE_REPLAY_NOT_VERIFIED" }
if([bool]$M.static_proof -ne $true){ Fail "STATIC_PROOF_FALSE" }
if([bool]$M.ai_required -ne $false){ Fail "AI_REQUIRED_TRUE" }

$requiredEvidence = @(
  "tier0_full_green.receipt.v1.json",
  "sha256sums.txt",
  "static_setup.stdout.txt",
  "snapshot.stdout.txt",
  "replay_verify.stdout.txt",
  "replay.stdout.txt",
  "negative_replay_vectors.stdout.txt"
)

foreach($name in $requiredEvidence){
  $p = Join-Path $Evidence $name
  if(-not (Test-Path -LiteralPath $p -PathType Leaf)){
    Fail ("MISSING_EVIDENCE:" + $name)
  }
}

$requiredSnapshot = @(
  "snapshot_manifest.v1.json",
  "snapshot_id.txt",
  "sha256sums.txt"
)

foreach($name in $requiredSnapshot){
  $p = Join-Path $Snapshot $name
  if(-not (Test-Path -LiteralPath $p -PathType Leaf)){
    Fail ("MISSING_SNAPSHOT_FILE:" + $name)
  }
}

$lines = @(Get-Content -LiteralPath $Sums | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
foreach($line in $lines){
  if($line -notmatch '^([a-fA-F0-9]{64})\s+(.+)$'){
    Fail "SHA256SUMS_BAD_FORMAT"
  }

  $expected = $Matches[1].ToLowerInvariant()
  $rel = $Matches[2].Trim()
  $p = Join-Path $Root ($rel.Replace("/","\"))

  if(-not (Test-Path -LiteralPath $p -PathType Leaf)){
    Fail ("SHA256SUMS_FILE_MISSING:" + $rel)
  }

  $actual = Sha256-File $p
  if($actual -ne $expected){
    Fail ("SHA256SUMS_HASH_MISMATCH:" + $rel)
  }
}

Write-Host "DODWK_TIER0_FREEZE_PACK_VERIFY_OK" -ForegroundColor Green
Write-Host ("FREEZE_ROOT: " + $Root)
Write-Host ("FILES_VERIFIED: " + @($lines).Count)
Write-Host "REPLAY_VERIFIED: true"
Write-Host "NEGATIVE_REPLAY_VERIFIED: true"
exit 0
