param([Parameter(Mandatory=$true)][string]$BundleDir)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

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

$BundleDir = (Resolve-Path -LiteralPath $BundleDir).Path
$ManifestPath = Join-Path $BundleDir "certification_manifest.json"
$ReportPath   = Join-Path $BundleDir "progress_report.v1.json"
$ShaPath      = Join-Path $BundleDir "progress_report.sha256"
$SumsPath     = Join-Path $BundleDir "sha256sums.txt"
$SumsSumsPath = Join-Path $BundleDir "sha256_sha256sums.txt"

foreach($p in @($ManifestPath,$ReportPath,$ShaPath,$SumsPath,$SumsSumsPath)){
  if(-not (Test-Path -LiteralPath $p -PathType Leaf)){ throw ("VERIFY_MISSING_FILE: " + $p) }
}

$Manifest = Get-Content -LiteralPath $ManifestPath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
if([string]$Manifest.schema -ne "dodwk.certification_manifest.v1"){ throw "VERIFY_BAD_MANIFEST_SCHEMA" }

$ActualReportSha = Sha256HexFile $ReportPath
$ExpectedReportSha = (Read-Utf8 $ShaPath).Trim()
if($ActualReportSha -ne $ExpectedReportSha){ throw "VERIFY_REPORT_SHA_FILE_MISMATCH" }
if($ActualReportSha -ne [string]$Manifest.report_sha256){ throw "VERIFY_REPORT_SHA_MANIFEST_MISMATCH" }

$files = Get-ChildItem -LiteralPath $BundleDir -Recurse -File |
  Where-Object { $_.Name -notin @("sha256sums.txt","sha256_sha256sums.txt") } |
  Sort-Object FullName
$rows = New-Object System.Collections.Generic.List[string]
foreach($f in $files){
  $rel = $f.FullName.Substring($BundleDir.Length).TrimStart("\","/").Replace("\","/")
  [void]$rows.Add((Sha256HexFile $f.FullName) + "  " + $rel)
}
$ExpectedSums = ((@($rows.ToArray()) -join "`n") + "`n")
$ActualSums   = Read-Utf8 $SumsPath
if($ExpectedSums -ne $ActualSums){ throw "VERIFY_SHA256SUMS_MISMATCH" }

$ActualSumsSha = Sha256HexFile $SumsPath
$ExpectedSumsSha = (Read-Utf8 $SumsSumsPath).Trim()
if($ActualSumsSha -ne $ExpectedSumsSha){ throw "VERIFY_SHA256_SHA256SUMS_MISMATCH" }

Write-Host ("CERTIFICATION_VERIFY_OK: " + $BundleDir) -ForegroundColor Green
