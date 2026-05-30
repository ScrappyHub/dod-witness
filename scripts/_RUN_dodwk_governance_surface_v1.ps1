param(
  [string]$Repo = ".",
  [string]$Wbs = ".\specs\wbs.v1.json",
  [string]$Overlay = ".\specs\overlay.v1.json"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Die([string]$m){
  Write-Host ("DODWK_GOVERNANCE_SURFACE_FAIL: " + $m) -ForegroundColor Red
  exit 1
}

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
  $sha = [System.Security.Cryptography.SHA256]::Create()
  try{
    $bytes = [System.IO.File]::ReadAllBytes($Path)
    $hash = $sha.ComputeHash($bytes)
    return (($hash | ForEach-Object { $_.ToString("x2") }) -join "")
  } finally {
    $sha.Dispose()
  }
}

$Root = "C:\dev\dod-witness-kit"
Set-Location $Root

$RunId = Get-Date -Format "yyyyMMdd_HHmmss"

$OutRoot = Join-Path $Root ("proofs\receipts\dodwk_governance_surface\" + $RunId)
Ensure-Dir $OutRoot

$Artifacts = @(
  ".\dodwk\code\code.inventory.v1.json",
  ".\dodwk\repo\repo.hygiene.v1.json",
  ".\dodwk\repo\repo.classification.v1.json",
  ".\dodwk\alignment\spec_code_alignment.v1.json",
  ".\dodwk\status\status.v1.json",
  ".\dodwk\semantic\semantic_intent.v1.json",
  ".\dodwk\graph\repo_graph.v1.json",
  ".\dodwk\graph\repo_graph_semantics.v1.json",
  ".\dodwk\graph\repo_graph_governance.v1.json",
  ".\dodwk\dynamic\dynamic_index.v1.json",
  ".\dodwk\ai_memory\ai_project_memory_index.v1.json",
  ".\dodwk\release\release_readiness.v1.json",
  ".\docs\wbs\DODWK_CANONICAL_PROGRESS_LEDGER.md",
  ".\dodwk\drift\drift_report.v2.json",
  ".\dodwk\federation\federation_surface.v1.json",
  ".\docs\DODWK_STANDALONE_LAW_V1.md",
  "C:\dev\dod-witness-kit\proofs\receipts\dodwk_tier0_full_green\20260528_145048\tier0_full_green.receipt.v1.json",
  ".\docs\DODWK_STANDALONE_LAW_V1.md",
  "C:\dev\dod-witness-kit\proofs\receipts\dodwk_tier0_full_green\20260528_145048\tier0_full_green.receipt.v1.json"
)

$Rows = @()

foreach($a in $Artifacts){
  if(-not (Test-Path -LiteralPath $a -PathType Leaf)){
    Die ("ARTIFACT_MISSING:" + $a)
  }

  $resolved = (Resolve-Path -LiteralPath $a).Path

  $Rows += @{
    path = $resolved
    sha256 = Sha256-File $resolved
  }
}

$result = @{
  schema = "dodwk.governance_surface.v1"
  run_id = $RunId
  repo = (Resolve-Path -LiteralPath $Repo).Path
  status = "pass"
  static_governance = $true
  dynamic_advisory = $true
  dynamic_is_proof = $false
  ai_memory_advisory = $true
  ai_memory_is_proof = $false
  artifacts = $Rows
}

$jsonPath = Join-Path $OutRoot "governance_surface.v1.json"
Write-Utf8NoBomLf $jsonPath ($result | ConvertTo-Json -Depth 30)

$sum = @()
foreach($r in $Rows){
  $sum += ($r.sha256 + "  " + $r.path)
}
$sum += ((Sha256-File $jsonPath) + "  " + $jsonPath)

Write-Utf8NoBomLf (Join-Path $OutRoot "sha256sums.txt") ($sum -join "`n")

$lines = @()
$lines += "# DODWK Governance Surface"
$lines += ""
$lines += "- Status: pass"
$lines += "- Static governance: true"
$lines += "- Dynamic advisory: true"
$lines += "- Dynamic is proof: false"
$lines += "- AI memory advisory: true"
$lines += "- AI memory is proof: false"
$lines += "- Repo graph included: true"
$lines += "- Graph semantics included: true"
$lines += "- Graph governance included: true"
$lines += "- Progress ledger included: true"
$lines += "- Artifact count: $($Rows.Count)"
$lines += ""

foreach($r in $Rows){
  $lines += ("- " + $r.path + " :: " + $r.sha256)
}

Write-Utf8NoBomLf (Join-Path $OutRoot "governance_surface.summary.md") ($lines -join "`n")

Write-Host "DODWK_GOVERNANCE_SURFACE_OK"
Write-Host ("OUT_ROOT: " + $OutRoot)
Write-Host ("ARTIFACTS: " + $Rows.Count)
exit 0
