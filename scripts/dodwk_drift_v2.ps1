param(
  [string]$Repo = ".",
  [string]$BaselineDir = ".\dodwk\drift\baseline",
  [string]$Out = ".\dodwk\drift"
)

Set-StrictMode -Version Latest

# DODWK_DRIFT_REPLAY_ISOLATION_V1
# Replay outputs, snapshots, and update receipts are not source governance truth.
# Drift remains useful operationally, but regeneration replay must not fail solely because drift observed replay-created state.
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
  if(-not (Test-Path -LiteralPath $Path -PathType Leaf)){
    return ""
  }
  $sha = [System.Security.Cryptography.SHA256]::Create()
  try{
    $bytes = [System.IO.File]::ReadAllBytes((Resolve-Path -LiteralPath $Path).Path)
    $hash = $sha.ComputeHash($bytes)
    return (($hash | ForEach-Object { $_.ToString("x2") }) -join "")
  } finally {
    $sha.Dispose()
  }
}

function Read-JsonOrNull([string]$Path){
  if(-not (Test-Path -LiteralPath $Path -PathType Leaf)){ return $null }
  try { return ((Get-Content -Raw -LiteralPath $Path) | ConvertFrom-Json) } catch { return $null }
}

Ensure-Dir $Out
Ensure-Dir $BaselineDir

$ResolvedRepo = (Resolve-Path -LiteralPath $Repo).Path

$artifacts = @(
  @{ name="repo_graph"; path=".\dodwk\graph\repo_graph.v1.json" },
  @{ name="repo_graph_semantics"; path=".\dodwk\graph\repo_graph_semantics.v1.json" },
  @{ name="repo_graph_governance"; path=".\dodwk\graph\repo_graph_governance.v1.json" },
  @{ name="governance_decisions"; path=".\dodwk\decision\governance_decisions.v1.json" },
  @{ name="symbol_graph"; path=".\dodwk\symbols\symbol_graph.v1.json" },
  @{ name="symbol_relationship_graph"; path=".\dodwk\symbols\symbol_relationship_graph.v1.json" },
  @{ name="release_readiness"; path=".\dodwk\release\release_readiness.v1.json" },
  @{ name="status"; path=".\dodwk\status\status.v1.json" }
)

$current = @()
foreach($a in $artifacts){
  $resolved = ""
  $exists = Test-Path -LiteralPath $a.path -PathType Leaf
  if($exists){ $resolved = (Resolve-Path -LiteralPath $a.path).Path }

  $current += @{
    name = $a.name
    path = $resolved
    exists = $exists
    sha256 = Sha256-File $a.path
  }
}

$currentObj = @{
  schema = "dodwk.drift_snapshot.v2"
  repo = $ResolvedRepo
  created_utc = (Get-Date).ToUniversalTime().ToString("o")
  artifacts = $current
}

$currentPath = Join-Path $Out "drift.current.v2.json"
Write-Utf8NoBomLf $currentPath ($currentObj | ConvertTo-Json -Depth 30)

$baselinePath = Join-Path $BaselineDir "drift.baseline.v2.json"
$baselineObj = Read-JsonOrNull $baselinePath

$events = @()
$status = "pass"

if($null -eq $baselineObj){
  $status = "baseline_created"
  Copy-Item -LiteralPath $currentPath -Destination $baselinePath -Force
} else {
  $baseByName = @{}
  foreach($b in @($baselineObj.artifacts)){
    $baseByName[[string]$b.name] = $b
  }

  foreach($c in $current){
    $name = [string]$c.name

    if(-not $baseByName.ContainsKey($name)){
      $events += @{
        event = "ARTIFACT_NEW"
        artifact = $name
        severity = "medium"
        current_sha256 = [string]$c.sha256
      }
      continue
    }

    $b = $baseByName[$name]

    if([string]$b.exists -ne [string]$c.exists){
      $events += @{
        event = "ARTIFACT_EXISTENCE_DRIFT"
        artifact = $name
        severity = "high"
        baseline_exists = $b.exists
        current_exists = $c.exists
      }
      continue
    }

    if([string]$b.sha256 -ne [string]$c.sha256){
      $sev = "medium"
      if($name -in @("repo_graph_governance","governance_decisions","symbol_relationship_graph","release_readiness")){
        $sev = "high"
      }

      $events += @{
        event = "ARTIFACT_HASH_DRIFT"
        artifact = $name
        severity = $sev
        baseline_sha256 = [string]$b.sha256
        current_sha256 = [string]$c.sha256
      }
    }
  }

  if(@($events).Count -gt 0){ $status = "drift_detected" }
}

$eventCounts = @{}
foreach($e in $events){
  $k = [string]$e.event
  if(-not $eventCounts.ContainsKey($k)){ $eventCounts[$k] = 0 }
  $eventCounts[$k] = [int]$eventCounts[$k] + 1
}

$result = @{
  schema = "dodwk.drift_report.v2"
  repo = $ResolvedRepo
  status = $status
  events_total = @($events).Count
  event_counts = $eventCounts
  baseline = $baselinePath
  current = $currentPath
  static_analysis = $true
  ai_required = $false
  proof_status = "static_analysis"
  events = $events
}

Write-Utf8NoBomLf (Join-Path $Out "drift_report.v2.json") ($result | ConvertTo-Json -Depth 40)

$lines = @()
$lines += "# DODWK Drift v2"
$lines += ""
$lines += "- Status: $status"
$lines += "- Events: $(@($events).Count)"
$lines += "- Baseline: $baselinePath"
$lines += "- Current: $currentPath"
$lines += "- Static analysis: true"
$lines += "- AI required: false"
$lines += "- Proof status: static_analysis"
$lines += ""
$lines += "## Event Counts"
if($eventCounts.Keys.Count -eq 0){
  $lines += "- none"
} else {
  foreach($k in ($eventCounts.Keys | Sort-Object)){
    $lines += ("- " + $k + ": " + $eventCounts[$k])
  }
}
$lines += ""
$lines += "## Events"
if(@($events).Count -eq 0){
  $lines += "- none"
} else {
  foreach($e in $events){
    $lines += ("- [" + $e.severity + "] " + $e.event + " :: " + $e.artifact)
  }
}

Write-Utf8NoBomLf (Join-Path $Out "drift_report.summary.md") ($lines -join "`n")

Write-Host ("DODWK_DRIFT_V2_OK: " + $Out)
Write-Host ("STATUS: " + $status)
Write-Host ("EVENTS: " + @($events).Count)
exit 0
