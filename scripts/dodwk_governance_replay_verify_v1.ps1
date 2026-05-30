param(
  [Parameter(Mandatory=$true)][string]$SnapshotRoot,
  [string]$Out = ".\dodwk\replay"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Ensure-Dir([string]$p){
  if(-not (Test-Path -LiteralPath $p -PathType Container)){
    New-Item -ItemType Directory -Force -Path $p | Out-Null
  }
}

function Write-Utf8NoBomLf([string]$Path,[string]$Text){
  $parent = Split-Path -Parent $Path
  if($parent){ Ensure-Dir $parent }
  $t = $Text.Replace("`r`n","`n").Replace("`r","`n")
  if(-not $t.EndsWith("`n")){ $t += "`n" }
  $enc = New-Object System.Text.UTF8Encoding($false)
  [System.IO.File]::WriteAllText($Path,$t,$enc)
}

function Sha256-File([string]$Path){
  if(-not (Test-Path -LiteralPath $Path -PathType Leaf)){ throw "HASH_FILE_MISSING:$Path" }
  $sha = [System.Security.Cryptography.SHA256]::Create()
  try{
    $bytes = [System.IO.File]::ReadAllBytes((Resolve-Path -LiteralPath $Path).Path)
    return (($sha.ComputeHash($bytes) | ForEach-Object { $_.ToString("x2") }) -join "")
  } finally {
    $sha.Dispose()
  }
}

function Sha256-Text([string]$Text){
  $sha = [System.Security.Cryptography.SHA256]::Create()
  try{
    $bytes = [Text.Encoding]::UTF8.GetBytes($Text)
    return (($sha.ComputeHash($bytes) | ForEach-Object { $_.ToString("x2") }) -join "")
  } finally {
    $sha.Dispose()
  }
}

function Read-Json([string]$Path){
  if(-not (Test-Path -LiteralPath $Path -PathType Leaf)){ throw "JSON_MISSING:$Path" }
  return ((Get-Content -Raw -LiteralPath $Path) | ConvertFrom-Json)
}

$Root = "C:\dev\dod-witness-kit"
Set-Location $Root
Ensure-Dir $Out

$ResolvedSnapshot = (Resolve-Path -LiteralPath $SnapshotRoot).Path
$RunId = Get-Date -Format "yyyyMMdd_HHmmss"
$RunRoot = Join-Path $Out ("governance_replay_verify_" + $RunId)
Ensure-Dir $RunRoot

$manifestPath = Join-Path $ResolvedSnapshot "snapshot_manifest.v1.json"
$snapshotIdPath = Join-Path $ResolvedSnapshot "snapshot_id.txt"
$shaPath = Join-Path $ResolvedSnapshot "sha256sums.txt"

$failures = @()
$checks = @()

if(-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)){ $failures += "MISSING:snapshot_manifest.v1.json" }
if(-not (Test-Path -LiteralPath $snapshotIdPath -PathType Leaf)){ $failures += "MISSING:snapshot_id.txt" }
if(-not (Test-Path -LiteralPath $shaPath -PathType Leaf)){ $failures += "MISSING:sha256sums.txt" }

if(@($failures).Count -eq 0){
  $manifestText = Get-Content -Raw -LiteralPath $manifestPath
  $manifestText = $manifestText.Replace("`r`n","`n").Replace("`r","`n")
  if(-not $manifestText.EndsWith("`n")){ $manifestText += "`n" }

  $expectedSnapshotId = Sha256-Text $manifestText
  $actualSnapshotId = (Get-Content -Raw -LiteralPath $snapshotIdPath).Trim()

  if($expectedSnapshotId -ne $actualSnapshotId){
    $failures += "SNAPSHOT_ID_MISMATCH"
  }

  $checks += @{
    check = "snapshot_id"
    expected = $expectedSnapshotId
    actual = $actualSnapshotId
    status = $(if($expectedSnapshotId -eq $actualSnapshotId){"pass"}else{"fail"})
  }

  $manifest = Read-Json $manifestPath

  foreach($a in @($manifest.artifacts)){
    $name = [string]$a.name
    $expectedHash = [string]$a.sha256
    $artifactPath = Join-Path $ResolvedSnapshot $name

    if(-not (Test-Path -LiteralPath $artifactPath -PathType Leaf)){
      $failures += ("ARTIFACT_MISSING:" + $name)
      $checks += @{ check=$name; expected=$expectedHash; actual=""; status="fail" }
      continue
    }

    $actualHash = Sha256-File $artifactPath
    if($actualHash -ne $expectedHash){
      $failures += ("ARTIFACT_HASH_MISMATCH:" + $name)
    }

    $checks += @{
      check = $name
      expected = $expectedHash
      actual = $actualHash
      status = $(if($actualHash -eq $expectedHash){"pass"}else{"fail"})
    }
  }

  $sumLines = @(Get-Content -LiteralPath $shaPath | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
  foreach($line in $sumLines){
    if($line -notmatch '^([a-fA-F0-9]{64})\s+(.+)$'){
      $failures += "SHA256SUMS_BAD_FORMAT"
      continue
    }

    $expected = $Matches[1].ToLowerInvariant()
    $name = $Matches[2].Trim()
    $p = Join-Path $ResolvedSnapshot $name

    if(-not (Test-Path -LiteralPath $p -PathType Leaf)){
      $failures += ("SHA256SUMS_FILE_MISSING:" + $name)
      continue
    }

    $actual = Sha256-File $p
    if($actual -ne $expected){
      $failures += ("SHA256SUMS_HASH_MISMATCH:" + $name)
    }
  }
}

$status = "pass"
if(@($failures).Count -gt 0){ $status = "fail" }

$result = @{
  schema = "dodwk.governance_replay_verify.v1"
  run_id = $RunId
  snapshot_root = $ResolvedSnapshot
  status = $status
  failures_total = @($failures).Count
  checks_total = @($checks).Count
  non_mutating = $true
  static_analysis = $true
  ai_required = $false
  proof_status = "replay_verify"
  checks = $checks
  failures = $failures
}

Write-Utf8NoBomLf (Join-Path $RunRoot "governance_replay_verify.v1.json") ($result | ConvertTo-Json -Depth 60)

$md = @()
$md += "# DODWK Governance Replay Verify"
$md += ""
$md += "- Status: $status"
$md += "- Snapshot root: $ResolvedSnapshot"
$md += "- Checks: $(@($checks).Count)"
$md += "- Failures: $(@($failures).Count)"
$md += "- Non-mutating: true"
$md += "- Static analysis: true"
$md += "- AI required: false"
$md += "- Proof status: replay_verify"
$md += ""
$md += "## Failures"
if(@($failures).Count -eq 0){ $md += "- none" } else { foreach($f in $failures){ $md += ("- " + $f) } }

Write-Utf8NoBomLf (Join-Path $RunRoot "governance_replay_verify.summary.md") ($md -join "`n")

if($status -eq "pass"){
  Write-Host "DODWK_GOVERNANCE_REPLAY_VERIFY_OK"
} else {
  Write-Host "DODWK_GOVERNANCE_REPLAY_VERIFY_FAIL" -ForegroundColor Red
}
Write-Host ("STATUS: " + $status)
Write-Host ("RUN_ROOT: " + $RunRoot)
Write-Host ("FAILURES: " + @($failures).Count)

if($status -ne "pass"){ exit 1 }
exit 0
