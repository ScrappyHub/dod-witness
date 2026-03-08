param(
  [Parameter(Mandatory=$true)][string]$RepoRoot,
  [Parameter(Mandatory=$true)][string]$ProjectId,
  [Parameter(Mandatory=$true)][string]$MilestoneId,
  [Parameter(Mandatory=$true)][string]$OutPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference="Stop"

function EnsureDir([string]$p){
 if([string]::IsNullOrWhiteSpace($p)){ throw "ENSUREDIR_EMPTY" }
 if(-not (Test-Path -LiteralPath $p -PathType Container)){
   New-Item -ItemType Directory -Force -Path $p | Out-Null
 }
}

function WriteUtf8NoBomLf([string]$path,[string]$text){
 $enc = New-Object System.Text.UTF8Encoding($false)
 $t = ($text -replace "`r`n","`n") -replace "`r","`n"
 if(-not $t.EndsWith("`n")){ $t += "`n" }
 $dir = Split-Path -Parent $path
 if($dir){ EnsureDir $dir }
 [System.IO.File]::WriteAllText($path,$t,$enc)
}

$Overlay = [ordered]@{
 schema="dodwk.progress_overlay.v1"
 project_id=$ProjectId
 milestone_id=$MilestoneId
 tasks=@(
  [ordered]@{
   task_id="01"
   title="Example task"
   weight=100
   depends_on=@()
   completion_rules=@(
     [ordered]@{
       kind="file_exists"
       path="README.md"
     }
   )
  }
 )
}

$json = $Overlay | ConvertTo-Json -Depth 8 -Compress
WriteUtf8NoBomLf $OutPath $json

Write-Host ("OVERLAY_CREATED: " + $OutPath) -ForegroundColor Green
