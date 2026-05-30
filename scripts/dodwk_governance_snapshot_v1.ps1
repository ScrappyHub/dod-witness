param(
  [string]$OutRoot = ".\dodwk\governance_snapshots"
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

$Root = "C:\dev\dod-witness-kit"
Set-Location $Root
Ensure-Dir $OutRoot

$latestSurface = Get-ChildItem ".\proofs\receipts\dodwk_governance_surface" -Directory |
  Sort-Object LastWriteTime -Descending |
  Select-Object -First 1

if($null -eq $latestSurface){ throw "NO_GOVERNANCE_SURFACE_FOUND" }

$inputs = @(
  @{ name="governance_surface.v1.json"; path=(Join-Path $latestSurface.FullName "governance_surface.v1.json") },
  @{ name="repo_graph.v1.json"; path=".\dodwk\graph\repo_graph.v1.json" },
  @{ name="repo_graph_semantics.v1.json"; path=".\dodwk\graph\repo_graph_semantics.v1.json" },
  @{ name="repo_graph_governance.v1.json"; path=".\dodwk\graph\repo_graph_governance.v1.json" },
  @{ name="governance_decisions.v1.json"; path=".\dodwk\decision\governance_decisions.v1.json" },
  @{ name="symbol_graph.v1.json"; path=".\dodwk\symbols\symbol_graph.v1.json" },
  @{ name="symbol_relationship_graph.v1.json"; path=".\dodwk\symbols\symbol_relationship_graph.v1.json" },
  @{ name="drift_report.v2.json"; path=".\dodwk\drift\drift_report.v2.json" },
  @{ name="release_readiness.v1.json"; path=".\dodwk\release\release_readiness.v1.json" },
  @{ name="federation_surface.v1.json"; path=".\dodwk\federation\federation_surface.v1.json" },
  @{ name="cross_repo_governance.v1.json"; path=".\dodwk\federation\cross_repo_governance.v1.json" },
  @{ name="release_propagation.v1.json"; path=".\dodwk\federation\release_propagation.v1.json" },
  @{ name="standalone_law.md"; path=".\docs\DODWK_STANDALONE_LAW_V1.md" }
)

$artifactRows = @()
foreach($i in $inputs){
  if(-not (Test-Path -LiteralPath $i.path -PathType Leaf)){
    throw ("SNAPSHOT_INPUT_MISSING:" + $i.path)
  }

  $resolved = (Resolve-Path -LiteralPath $i.path).Path
  $artifactRows += @{
    name = [string]$i.name
    source_path = $resolved
    sha256 = Sha256-File $resolved
    bytes = (Get-Item -LiteralPath $resolved).Length
  }
}

$manifest = @{
  schema = "dodwk.governance_snapshot_manifest.v1"
  created_utc = (Get-Date).ToUniversalTime().ToString("o")
  law = "snapshot_id = sha256(snapshot_manifest.v1.json bytes without snapshot_id)"
  artifact_count = @($artifactRows).Count
  artifacts = $artifactRows
  static_analysis = $true
  ai_required = $false
  proof_status = "static_snapshot"
}

$manifestText = ($manifest | ConvertTo-Json -Depth 60)
$manifestText = $manifestText.Replace("`r`n","`n").Replace("`r","`n")
if(-not $manifestText.EndsWith("`n")){ $manifestText += "`n" }

$snapshotId = Sha256-Text $manifestText
$snapshotDir = Join-Path $OutRoot $snapshotId
Ensure-Dir $snapshotDir

foreach($row in $artifactRows){
  Copy-Item -LiteralPath $row.source_path -Destination (Join-Path $snapshotDir $row.name) -Force
}

Write-Utf8NoBomLf (Join-Path $snapshotDir "snapshot_manifest.v1.json") $manifestText
Write-Utf8NoBomLf (Join-Path $snapshotDir "snapshot_id.txt") $snapshotId

$sumLines = @()
foreach($row in $artifactRows | Sort-Object name){
  $sumLines += ($row.sha256 + "  " + $row.name)
}
$sumLines += ((Sha256-File (Join-Path $snapshotDir "snapshot_manifest.v1.json")) + "  snapshot_manifest.v1.json")
$sumLines += ((Sha256-File (Join-Path $snapshotDir "snapshot_id.txt")) + "  snapshot_id.txt")
Write-Utf8NoBomLf (Join-Path $snapshotDir "sha256sums.txt") ($sumLines -join "`n")

$md = @()
$md += "# DODWK Governance Snapshot"
$md += ""
$md += "- Snapshot ID: $snapshotId"
$md += "- Artifact count: $(@($artifactRows).Count)"
$md += "- Snapshot root: $snapshotDir"
$md += "- Static analysis: true"
$md += "- AI required: false"
$md += "- Proof status: static_snapshot"
$md += ""
$md += "## Artifacts"
foreach($row in $artifactRows | Sort-Object name){
  $md += ("- " + $row.name + " :: " + $row.sha256)
}
Write-Utf8NoBomLf (Join-Path $snapshotDir "snapshot.summary.md") ($md -join "`n")

Write-Host "DODWK_GOVERNANCE_SNAPSHOT_OK"
Write-Host ("SNAPSHOT_ID: " + $snapshotId)
Write-Host ("SNAPSHOT_ROOT: " + $snapshotDir)
Write-Host ("ARTIFACTS: " + @($artifactRows).Count)
exit 0
