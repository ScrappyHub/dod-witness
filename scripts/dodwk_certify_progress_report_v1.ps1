param(
  [Parameter(Mandatory=$true)][string]$RepoRoot,
  [Parameter(Mandatory=$true)][string]$ReportPath,
  [Parameter(Mandatory=$true)][string]$OutDir
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

function Read-Utf8([string]$Path){
  $enc = New-Object System.Text.UTF8Encoding($false)
  return [System.IO.File]::ReadAllText($Path,$enc)
}

function Sha256HexFile([string]$Path){
  $sha = [System.Security.Cryptography.SHA256]::Create()
  $fs = [System.IO.File]::OpenRead($Path)
  try {
    $h = $sha.ComputeHash($fs)
  } finally {
    $fs.Dispose()
    $sha.Dispose()
  }
  return ([BitConverter]::ToString($h) -replace "-","").ToLowerInvariant()
}

$RepoRoot  = (Resolve-Path -LiteralPath $RepoRoot).Path
$ReportPath = (Resolve-Path -LiteralPath $ReportPath).Path
Ensure-Dir $OutDir

$ReportCopy = Join-Path $OutDir "progress_report.v1.json"
Copy-Item -LiteralPath $ReportPath -Destination $ReportCopy -Force

$ReportSha = Sha256HexFile $ReportCopy
Write-Utf8NoBomLf (Join-Path $OutDir "progress_report.sha256") ($ReportSha + "`n")

$ReportObj = Get-Content -LiteralPath $ReportCopy -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
$Manifest = [ordered]@{
  schema = "dodwk.certification_manifest.v1"
  project_id = [string]$ReportObj.project_id
  milestone_id = [string]$ReportObj.milestone_id
  progress_percent = [double]$ReportObj.progress_percent
  report_file = "progress_report.v1.json"
  report_sha256 = $ReportSha
}
Write-Utf8NoBomLf (Join-Path $OutDir "certification_manifest.json") (($Manifest | ConvertTo-Json -Depth 8 -Compress))

$files = Get-ChildItem -LiteralPath $OutDir -Recurse -File |
  Where-Object { $_.Name -notin @("sha256sums.txt","sha256_sha256sums.txt") } |
  Sort-Object FullName
$rows = New-Object System.Collections.Generic.List[string]
foreach($f in $files){
  $rel = $f.FullName.Substring($OutDir.Length).TrimStart("\","/").Replace("\","/")
  [void]$rows.Add((Sha256HexFile $f.FullName) + "  " + $rel)
}
Write-Utf8NoBomLf (Join-Path $OutDir "sha256sums.txt") ((@($rows.ToArray()) -join "`n") + "`n")
Write-Utf8NoBomLf (Join-Path $OutDir "sha256_sha256sums.txt") ((Sha256HexFile (Join-Path $OutDir "sha256sums.txt")) + "`n")

Write-Host ("CERTIFICATION_OK: " + $OutDir) -ForegroundColor Green
