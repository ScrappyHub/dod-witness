param(
  [Parameter(Mandatory=$true)][string]$SnapshotRoot,
  [string]$Repo = ".",
  [string]$Out = ".\dodwk\replay"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Die([string]$m){
  Write-Host ("DODWK_GOVERNANCE_REPLAY_FAIL: " + $m) -ForegroundColor Red
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
  if(-not (Test-Path -LiteralPath $Path -PathType Leaf)){ throw "JSON_MISSING:$Path" }
  return ((Get-Content -Raw -LiteralPath $Path) | ConvertFrom-Json)
}

function Run-Step([string]$Name,[string]$ScriptPath,[string[]]$ChildArgs){
  if(-not (Test-Path -LiteralPath $ScriptPath -PathType Leaf)){
    Die ("SCRIPT_MISSING:" + $ScriptPath)
  }

  [void][ScriptBlock]::Create((Get-Content -Raw -LiteralPath $ScriptPath))

  Write-Host ("RUNNING: " + $Name) -ForegroundColor Cyan

  & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $ScriptPath @ChildArgs
  $code = $LASTEXITCODE
  if($null -eq $code){ $code = 0 }

  if($code -ne 0){
    Die ($Name + "_EXIT_" + $code)
  }

  Write-Host ("PASSED: " + $Name) -ForegroundColor Green
}

$Root = "C:\dev\dod-witness-kit"
Set-Location $Root
Ensure-Dir $Out

$ResolvedSnapshot = (Resolve-Path -LiteralPath $SnapshotRoot).Path
$ResolvedRepo = (Resolve-Path -LiteralPath $Repo).Path

$RunId = Get-Date -Format "yyyyMMdd_HHmmss"
$RunRoot = Join-Path $Out ("governance_replay_" + $RunId)
Ensure-Dir $RunRoot

Run-Step "snapshot_verify" "$Root\scripts\dodwk_governance_replay_verify_v1.ps1" @(
  "-SnapshotRoot", $ResolvedSnapshot,
  "-Out", ".\dodwk\replay"
)

Run-Step "static_setup_regeneration" "$Root\scripts\_RUN_dodwk_static_setup_v1.ps1" @(
  "-Repo", $ResolvedRepo,
  "-Wbs", ".\specs\wbs.v1.json",
  "-Overlay", ".\specs\overlay.v1.json"
)

$manifestPath = Join-Path $ResolvedSnapshot "snapshot_manifest.v1.json"
$manifest = Read-Json $manifestPath

$currentMap = @{
  "repo_graph.v1.json" = ".\dodwk\graph\repo_graph.v1.json"
  "repo_graph_semantics.v1.json" = ".\dodwk\graph\repo_graph_semantics.v1.json"
  "repo_graph_governance.v1.json" = ".\dodwk\graph\repo_graph_governance.v1.json"
  "governance_decisions.v1.json" = ".\dodwk\decision\governance_decisions.v1.json"
  "symbol_graph.v1.json" = ".\dodwk\symbols\symbol_graph.v1.json"
  "symbol_relationship_graph.v1.json" = ".\dodwk\symbols\symbol_relationship_graph.v1.json"
  "drift_report.v2.json" = ".\dodwk\drift\drift_report.v2.json"
  "release_readiness.v1.json" = ".\dodwk\release\release_readiness.v1.json"
  "federation_surface.v1.json" = ".\dodwk\federation\federation_surface.v1.json"
  "cross_repo_governance.v1.json" = ".\dodwk\federation\cross_repo_governance.v1.json"
  "release_propagation.v1.json" = ".\dodwk\federation\release_propagation.v1.json"
  "standalone_law.md" = ".\docs\DODWK_STANDALONE_LAW_V1.md"
}

$checks = @()
$failures = @()

foreach($a in @($manifest.artifacts)){
  $name = [string]$a.name
  if($name -eq "governance_surface.v1.json"){
    # Governance surface contains run-specific receipt paths; verify it through snapshot integrity v1, not regeneration v1.
    continue
  }

  if($name -eq "drift_report.v2.json"){
    # Drift is stateful by design and may observe replay-created state.
    # Snapshot integrity verifies frozen drift; regeneration replay verifies deterministic governance surfaces.
    continue
  }

  if(-not $currentMap.ContainsKey($name)){
    $failures += ("NO_CURRENT_MAPPING:" + $name)
    continue
  }

  $currentPath = [string]$currentMap[$name]
  $expected = [string]$a.sha256
  $actual = Sha256-File $currentPath

  $ok = ($expected -eq $actual)

  if(-not $ok){
    $failures += ("REPLAY_HASH_MISMATCH:" + $name)
  }

  $checks += @{
    artifact = $name
    expected = $expected
    actual = $actual
    status = $(if($ok){"pass"}else{"fail"})
  }
}

$status = "pass"
if(@($failures).Count -gt 0){ $status = "fail" }

$result = @{
  schema = "dodwk.governance_replay.v1"
  run_id = $RunId
  snapshot_root = $ResolvedSnapshot
  repo = $ResolvedRepo
  status = $status
  checks_total = @($checks).Count
  failures_total = @($failures).Count
  regenerated_static_setup = $true
  non_mutating_snapshot_verify = $true
  ai_required = $false
  proof_status = "replay_regeneration"
  checks = $checks
  failures = $failures
}

Write-Utf8NoBomLf (Join-Path $RunRoot "governance_replay.v1.json") ($result | ConvertTo-Json -Depth 60)

$md = @()
$md += "# DODWK Governance Replay"
$md += ""
$md += "- Status: $status"
$md += "- Snapshot root: $ResolvedSnapshot"
$md += "- Repo: $ResolvedRepo"
$md += "- Checks: $(@($checks).Count)"
$md += "- Failures: $(@($failures).Count)"
$md += "- Regenerated static setup: true"
$md += "- AI required: false"
$md += "- Proof status: replay_regeneration"
$md += ""
$md += "## Failures"
if(@($failures).Count -eq 0){
  $md += "- none"
} else {
  foreach($f in $failures){ $md += ("- " + $f) }
}
$md += ""
$md += "## Checks"
foreach($c in $checks){
  $md += ("- [" + $c.status + "] " + $c.artifact)
}

Write-Utf8NoBomLf (Join-Path $RunRoot "governance_replay.summary.md") ($md -join "`n")

if($status -eq "pass"){
  Write-Host "DODWK_GOVERNANCE_REPLAY_OK" -ForegroundColor Green
} else {
  Write-Host "DODWK_GOVERNANCE_REPLAY_FAIL" -ForegroundColor Red
}
Write-Host ("STATUS: " + $status)
Write-Host ("RUN_ROOT: " + $RunRoot)
Write-Host ("CHECKS: " + @($checks).Count)
Write-Host ("FAILURES: " + @($failures).Count)

if($status -ne "pass"){ exit 1 }
exit 0
