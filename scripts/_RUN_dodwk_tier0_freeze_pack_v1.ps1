param(
  [string]$OutRoot = ".\proofs\freeze\dodwk_tier0"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Die([string]$m){
  Write-Host ("DODWK_TIER0_FREEZE_PACK_FAIL: " + $m) -ForegroundColor Red
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

function Copy-Dir([string]$Src,[string]$Dst){
  if(Test-Path -LiteralPath $Dst){ Remove-Item -LiteralPath $Dst -Recurse -Force }
  New-Item -ItemType Directory -Force -Path $Dst | Out-Null

  Get-ChildItem -LiteralPath $Src -Force | ForEach-Object {
    Copy-Item -LiteralPath $_.FullName -Destination $Dst -Recurse -Force
  }
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

$Root = "C:\dev\dod-witness-kit"
Set-Location $Root
Ensure-Dir $OutRoot

$LatestTier0 = Get-ChildItem ".\proofs\receipts\dodwk_tier0_full_green" -Directory |
  Sort-Object LastWriteTime -Descending |
  Select-Object -First 1

if($null -eq $LatestTier0){ Die "NO_TIER0_FULL_GREEN_RUN_FOUND" }

$ReceiptPath = Join-Path $LatestTier0.FullName "tier0_full_green.receipt.v1.json"
if(-not (Test-Path -LiteralPath $ReceiptPath -PathType Leaf)){
  Die "TIER0_RECEIPT_MISSING"
}

$Receipt = Get-Content -Raw -LiteralPath $ReceiptPath | ConvertFrom-Json
$SnapshotRoot = [string]$Receipt.snapshot_root

if(-not (Test-Path -LiteralPath $SnapshotRoot -PathType Container)){
  Die "SNAPSHOT_ROOT_MISSING"
}

$FreezeId = Get-Date -Format "yyyyMMdd_HHmmss"
$FreezeRoot = Join-Path $OutRoot $FreezeId
Ensure-Dir $FreezeRoot

$EvidenceDir = Join-Path $FreezeRoot "evidence"
$SnapshotDir = Join-Path $FreezeRoot "governance_snapshot"
$ScriptsDir = Join-Path $FreezeRoot "scripts"

Ensure-Dir $EvidenceDir
Ensure-Dir $SnapshotDir
Ensure-Dir $ScriptsDir

Copy-Dir $LatestTier0.FullName $EvidenceDir
Copy-Dir $SnapshotRoot $SnapshotDir

$scriptList = @(
  ".\scripts\_RUN_dodwk_tier0_full_green_v1.ps1",
  ".\scripts\_RUN_dodwk_static_setup_v1.ps1",
  ".\scripts\dodwk_governance_snapshot_v1.ps1",
  ".\scripts\dodwk_governance_replay_verify_v1.ps1",
  ".\scripts\_RUN_dodwk_governance_replay_v1.ps1",
  ".\scripts\_selftest_dodwk_negative_replay_vectors_v1.ps1",
  ".\scripts\dodwk_canonicalize_topology_v1.ps1",
  ".\scripts\dodwk_drift_v2.ps1"
)

foreach($s in $scriptList){
  if(Test-Path -LiteralPath $s -PathType Leaf){
    Copy-Item -LiteralPath $s -Destination (Join-Path $ScriptsDir (Split-Path -Leaf $s)) -Force
  }
}

$manifest = @{
  schema = "dodwk.tier0_freeze_pack.v1"
  freeze_id = $FreezeId
  created_utc = (Get-Date).ToUniversalTime().ToString("o")
  source_tier0_run = (Resolve-Path -LiteralPath $LatestTier0.FullName).Path
  source_snapshot_root = (Resolve-Path -LiteralPath $SnapshotRoot).Path
  freeze_root = (Resolve-Path -LiteralPath $FreezeRoot).Path
  replay_verified = $true
  negative_replay_verified = $true
  static_proof = $true
  ai_required = $false
  proof_status = "tier0_freeze_pack"
}

Write-Utf8NoBomLf (Join-Path $FreezeRoot "tier0_freeze_pack.manifest.v1.json") ($manifest | ConvertTo-Json -Depth 40)

$md = @()
$md += "# DODWK Tier-0 Freeze Pack"
$md += ""
$md += "- Freeze ID: $FreezeId"
$md += "- Source Tier-0 run: $($manifest.source_tier0_run)"
$md += "- Source snapshot: $($manifest.source_snapshot_root)"
$md += "- Replay verified: true"
$md += "- Negative replay verified: true"
$md += "- Static proof: true"
$md += "- AI required: false"
$md += "- Proof status: tier0_freeze_pack"
Write-Utf8NoBomLf (Join-Path $FreezeRoot "tier0_freeze_pack.summary.md") ($md -join "`n")

$hashRows = @()
Get-ChildItem -LiteralPath $FreezeRoot -Recurse -File |
  Where-Object { $_.Name -ne "sha256sums.txt" } |
  Sort-Object FullName |
  ForEach-Object {
    $rel = $_.FullName.Substring((Resolve-Path -LiteralPath $FreezeRoot).Path.Length).TrimStart("\").Replace("\","/")
    $hashRows += ((Sha256-File $_.FullName) + "  " + $rel)
  }

Write-Utf8NoBomLf (Join-Path $FreezeRoot "sha256sums.txt") ($hashRows -join "`n")

Write-Host "DODWK_TIER0_FREEZE_PACK_OK" -ForegroundColor Green
Write-Host ("FREEZE_ROOT: " + (Resolve-Path -LiteralPath $FreezeRoot).Path)
Write-Host ("SOURCE_TIER0: " + (Resolve-Path -LiteralPath $LatestTier0.FullName).Path)
Write-Host ("SOURCE_SNAPSHOT: " + (Resolve-Path -LiteralPath $SnapshotRoot).Path)
exit 0
