param(
  [string]$Registry = ".\dodwk\registry\repo_registry.v1.json",
  [string]$Out = ".\dodwk\federation"
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
  if(-not (Test-Path -LiteralPath $Path -PathType Leaf)){ return "" }
  $sha = [System.Security.Cryptography.SHA256]::Create()
  try{
    $bytes = [System.IO.File]::ReadAllBytes((Resolve-Path -LiteralPath $Path).Path)
    return (($sha.ComputeHash($bytes) | ForEach-Object { $_.ToString("x2") }) -join "")
  } finally {
    $sha.Dispose()
  }
}

function Read-Json([string]$Path){
  if(-not (Test-Path -LiteralPath $Path -PathType Leaf)){
    throw ("JSON_MISSING: " + $Path)
  }
  return ((Get-Content -Raw -LiteralPath $Path) | ConvertFrom-Json)
}

Ensure-Dir $Out

$Root = "C:\dev\dod-witness-kit"
Set-Location $Root

$reg = Read-Json $Registry

$latestBatch = Get-ChildItem ".\dodwk\registry" -Directory -ErrorAction SilentlyContinue |
  Where-Object { $_.Name -like "registry_ingest_all_*" } |
  Sort-Object LastWriteTime -Descending |
  Select-Object -First 1

$latestSurface = Get-ChildItem ".\proofs\receipts\dodwk_governance_surface" -Directory -ErrorAction SilentlyContinue |
  Sort-Object LastWriteTime -Descending |
  Select-Object -First 1

$batchJson = ""
$batchSha = ""
if($null -ne $latestBatch){
  $batchJson = Join-Path $latestBatch.FullName "registry_ingest_all.v1.json"
  $batchSha = Sha256-File $batchJson
}

$surfaceJson = ""
$surfaceSha = ""
if($null -ne $latestSurface){
  $surfaceJson = Join-Path $latestSurface.FullName "governance_surface.v1.json"
  $surfaceSha = Sha256-File $surfaceJson
}

$repos = @()
foreach($r in @($reg.repos)){
  $repos += @{
    repo_id = [string]$r.repo_id
    name = [string]$r.name
    path = [string]$r.path
    static_truth_required = $true
    dynamic_advisory_allowed = $true
  }
}

$result = @{
  schema = "dodwk.federation_surface.v1"
  created_utc = (Get-Date).ToUniversalTime().ToString("o")
  registry = @{
    path = (Resolve-Path -LiteralPath $Registry).Path
    sha256 = Sha256-File $Registry
    repos_total = @($repos).Count
  }
  latest_registry_ingest = @{
    path = $batchJson
    sha256 = $batchSha
  }
  latest_governance_surface = @{
    path = $surfaceJson
    sha256 = $surfaceSha
  }
  repos = $repos
  local_first = $true
  hosted_sync_ready = $false
  static_proof_required = $true
  dynamic_advisory_allowed = $true
  ai_required = $false
  proof_status = "static_analysis"
}

$json = Join-Path $Out "federation_surface.v1.json"
Write-Utf8NoBomLf $json ($result | ConvertTo-Json -Depth 40)

$lines = @()
$lines += "# DODWK Federation Surface"
$lines += ""
$lines += "- Repos total: $(@($repos).Count)"
$lines += "- Local first: true"
$lines += "- Hosted sync ready: false"
$lines += "- Static proof required: true"
$lines += "- Dynamic advisory allowed: true"
$lines += "- AI required: false"
$lines += "- Proof status: static_analysis"
$lines += ""
$lines += "## Registry"
$lines += "- Path: $((Resolve-Path -LiteralPath $Registry).Path)"
$lines += "- SHA-256: $(Sha256-File $Registry)"
$lines += ""
$lines += "## Latest Registry Ingest"
$lines += "- Path: $batchJson"
$lines += "- SHA-256: $batchSha"
$lines += ""
$lines += "## Latest Governance Surface"
$lines += "- Path: $surfaceJson"
$lines += "- SHA-256: $surfaceSha"
$lines += ""
$lines += "## Repos"
foreach($repo in $repos){
  $lines += ("- " + $repo.repo_id + " :: " + $repo.name + " :: " + $repo.path)
}

Write-Utf8NoBomLf (Join-Path $Out "federation_surface.summary.md") ($lines -join "`n")

Write-Host "DODWK_FEDERATION_SURFACE_OK"
Write-Host ("REPOS_TOTAL: " + @($repos).Count)
Write-Host ("OUT: " + $json)
exit 0
