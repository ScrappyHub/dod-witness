param(
  [Parameter(Mandatory=$true)][string]$RepoRoot,
  [Parameter(Mandatory=$true)][string]$OverlayPath,
  [Parameter(Mandatory=$true)][string]$OutPath
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

function Ensure-Dir([string]$Path){
  if([string]::IsNullOrWhiteSpace($Path)){ throw "ENSURE_DIR_EMPTY" }
  if(-not (Test-Path -LiteralPath $Path -PathType Container)){
    New-Item -ItemType Directory -Force -Path $Path | Out-Null
  }
}

function Write-Utf8NoBomLf([string]$Path,[string]$Text){
  $enc = New-Object System.Text.UTF8Encoding($false)
  $t = ($Text -replace "`r`n","`n") -replace "`r","`n"
  if(-not $t.EndsWith("`n")){ $t += "`n" }
  $dir = Split-Path -Parent $Path
  if($dir){ Ensure-Dir $dir }
  [System.IO.File]::WriteAllText($Path,$t,$enc)
}

function Parse-GateFile([string]$Path){
  if(-not (Test-Path -LiteralPath $Path -PathType Leaf)){ throw ("PARSE_GATE_MISSING: " + $Path) }
  $tok = $null
  $err = $null
  [void][System.Management.Automation.Language.Parser]::ParseFile($Path,[ref]$tok,[ref]$err)
  if($err -and $err.Count -gt 0){
    $msg = ($err | ForEach-Object { $_.ToString() }) -join "`n"
    throw ("PARSE_GATE_FAIL: " + $Path + "`n" + $msg)
  }
}

$RepoRoot    = (Resolve-Path -LiteralPath $RepoRoot).Path
$OverlayPath = (Resolve-Path -LiteralPath $OverlayPath).Path
$raw = Get-Content -LiteralPath $OverlayPath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop

$results = New-Object System.Collections.Generic.List[object]
$totalWeight = 0
$doneWeight  = 0

foreach($task in @($raw.tasks)){
  $taskOk = $true
  $ruleResults = New-Object System.Collections.Generic.List[object]
  $totalWeight += [int]$task.weight

  foreach($rule in @($task.completion_rules)){
    $ok = $false

    if([string]$rule.kind -eq "file_exists"){
      $target = Join-Path $RepoRoot ([string]$rule.path)
      $ok = (Test-Path -LiteralPath $target -PathType Leaf)
    }
    elseif([string]$rule.kind -eq "parse_gate"){
      $target = Join-Path $RepoRoot ([string]$rule.path)
      if(Test-Path -LiteralPath $target -PathType Leaf){
        try {
          Parse-GateFile $target
          $ok = $true
        } catch {
          $ok = $false
        }
      } else {
        $ok = $false
      }
    }

    if(-not $ok){ $taskOk = $false }

    $rr = [ordered]@{
      kind = [string]$rule.kind
      ok   = [bool]$ok
    }
    if($rule.PSObject.Properties.Name -contains "path"){
      $rr.path = [string]$rule.path
    }
    [void]$ruleResults.Add($rr)
  }

  if($taskOk){
    $doneWeight += [int]$task.weight
  }

  $r = [ordered]@{
    task_id = [string]$task.task_id
    title   = [string]$task.title
    weight  = [int]$task.weight
    ok      = [bool]$taskOk
    rules   = $ruleResults
  }
  [void]$results.Add($r)
}

$pct = 0.0
if($totalWeight -gt 0){
  $pct = [math]::Round((100.0 * $doneWeight / $totalWeight),2)
}

$report = [ordered]@{
  schema           = "dodwk.progress_report.v1"
  project_id       = [string]$raw.project_id
  milestone_id     = [string]$raw.milestone_id
  total_weight     = [int]$totalWeight
  completed_weight = [int]$doneWeight
  progress_percent = [double]$pct
  tasks            = $results
}

Write-Utf8NoBomLf $OutPath (($report | ConvertTo-Json -Depth 8 -Compress))
Write-Host ("PROGRESS_REPORT_OK: " + $OutPath) -ForegroundColor Green
