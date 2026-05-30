param(
  [string]$Repo = "."
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

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

function Json-Escape([string]$s){
  $s = $s.Replace("\","\\").Replace('"','\"')
  $s = $s.Replace("`b","\b").Replace("`f","\f").Replace("`n","\n").Replace("`r","\r").Replace("`t","\t")
  return '"' + $s + '"'
}

function To-CanonJson($v){
  if($null -eq $v){ return "null" }

  if($v -is [string]){ return Json-Escape $v }
  if($v -is [bool]){ if($v){ return "true" } else { return "false" } }
  if($v -is [byte] -or $v -is [int16] -or $v -is [int32] -or $v -is [int64] -or $v -is [decimal] -or $v -is [double] -or $v -is [single]){
    return ([string]::Format([System.Globalization.CultureInfo]::InvariantCulture, "{0}", $v))
  }

  if($v -is [System.Collections.IEnumerable] -and -not ($v -is [string]) -and -not ($v -is [System.Management.Automation.PSCustomObject])){
    $items = @()
    foreach($x in $v){
      $items += (To-CanonJson $x)
    }
    $items = @($items | Sort-Object)
    return "[" + ($items -join ",") + "]"
  }

  $props = @($v.PSObject.Properties | Sort-Object Name)
  $parts = @()
  foreach($p in $props){
    $parts += ((Json-Escape ([string]$p.Name)) + ":" + (To-CanonJson $p.Value))
  }
  return "{" + ($parts -join ",") + "}"
}

$Root = (Resolve-Path -LiteralPath $Repo).Path
Set-Location $Root

$targets = @(
  ".\dodwk\graph\repo_graph.v1.json",
  ".\dodwk\graph\repo_graph_semantics.v1.json",
  ".\dodwk\graph\repo_graph_governance.v1.json",
  ".\dodwk\decision\governance_decisions.v1.json",
  ".\dodwk\symbols\symbol_graph.v1.json",
  ".\dodwk\symbols\symbol_relationship_graph.v1.json"
)

$changed = 0

foreach($t in $targets){
  if(-not (Test-Path -LiteralPath $t -PathType Leaf)){ continue }

  $obj = Get-Content -Raw -LiteralPath $t | ConvertFrom-Json
  $canon = To-CanonJson $obj

  $old = Get-Content -Raw -LiteralPath $t
  $oldNorm = $old.Replace("`r`n","`n").Replace("`r","`n")
  if(-not $oldNorm.EndsWith("`n")){ $oldNorm += "`n" }

  $newNorm = $canon
  if(-not $newNorm.EndsWith("`n")){ $newNorm += "`n" }

  if($oldNorm -ne $newNorm){
    Write-Utf8NoBomLf $t $canon
    $changed++
  }
}

Write-Host "DODWK_CANONICALIZE_TOPOLOGY_OK"
Write-Host ("FILES_CHANGED: " + $changed)
exit 0
