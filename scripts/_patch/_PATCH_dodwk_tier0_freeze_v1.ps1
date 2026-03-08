param([Parameter(Mandatory=$true)][string]$RepoRoot)

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

function Sha256HexFile([string]$Path){
  $sha = [System.Security.Cryptography.SHA256]::Create()
  $fs  = [System.IO.File]::OpenRead($Path)
  try {
    $h = $sha.ComputeHash($fs)
  } finally {
    $fs.Dispose()
    $sha.Dispose()
  }
  return ([BitConverter]::ToString($h) -replace "-","").ToLowerInvariant()
}

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path

$RunnerPath = Join-Path $RepoRoot "scripts\_RUN_dodwk_tier0_full_green_v1.ps1"
if(-not (Test-Path -LiteralPath $RunnerPath -PathType Leaf)){ throw ("MISSING_TIER0_RUNNER: " + $RunnerPath) }
Parse-GateFile $RunnerPath

$FreezeRoot = Join-Path $RepoRoot "proofs\freeze\dodwk_tier0"
$RunId      = [DateTime]::UtcNow.ToString("yyyyMMdd_HHmmssZ")
$FreezeDir  = Join-Path $FreezeRoot $RunId
Ensure-Dir $FreezeDir

$PSExe   = (Get-Command powershell.exe -ErrorAction Stop).Source
$StdOut  = Join-Path $FreezeDir "tier0_stdout.txt"
$StdErr  = Join-Path $FreezeDir "tier0_stderr.txt"

$p = Start-Process -FilePath $PSExe -WorkingDirectory $RepoRoot -ArgumentList @(
  "-NoProfile","-NonInteractive","-ExecutionPolicy","Bypass",
  "-File",$RunnerPath,
  "-RepoRoot",$RepoRoot
) -NoNewWindow -Wait -PassThru -RedirectStandardOutput $StdOut -RedirectStandardError $StdErr

if([int]$p.ExitCode -ne 0){
  throw ("FREEZE_TIER0_RUNNER_FAILED exit=" + [int]$p.ExitCode + " stdout=" + $StdOut + " stderr=" + $StdErr)
}

$stdoutText = ""
if(Test-Path -LiteralPath $StdOut -PathType Leaf){
  $stdoutText = Read-Utf8 $StdOut
}
if(-not $stdoutText.Contains("DODWK_TIER0_FULL_GREEN")){
  throw "FREEZE_MISSING_TIER0_GREEN_TOKEN"
}

$TargetFiles = @(
  "README.md",
  ".gitattributes",
  ".gitignore",
  "contracts\dodwk.progress_overlay.v1.sample.json",
  "schemas\dodwk.progress_report.v1.json",
  "docs\DODWK_PROGRESS_OVERLAY_V1.md",
  "scripts\dodwk_verify_progress_overlay_v1.ps1",
  "scripts\dodwk_certify_progress_report_v1.ps1",
  "scripts\dodwk_verify_certification_v1.ps1",
  "scripts\dodwk_new_progress_overlay_v1.ps1",
  "scripts\dodwk_import_and_verify_certification_v1.ps1",
  "scripts\_selftest_dodwk_progress_overlay_v1.ps1",
  "scripts\_selftest_dodwk_negative_vectors_v1.ps1",
  "scripts\_RUN_dodwk_progress_overlay_full_green_v1.ps1",
  "scripts\_RUN_dodwk_tier0_full_green_v1.ps1",
  "proofs\receipts\dodwk_progress_overlay_selftest\progress_report.v1.json"
)

$ManifestLines = New-Object System.Collections.Generic.List[string]
$HashLines     = New-Object System.Collections.Generic.List[string]

foreach($rel in $TargetFiles){
  $src = Join-Path $RepoRoot $rel
  if(-not (Test-Path -LiteralPath $src -PathType Leaf)){ throw ("FREEZE_MISSING_TARGET: " + $src) }

  $dst = Join-Path $FreezeDir $rel
  $dstDir = Split-Path -Parent $dst
  if($dstDir){ Ensure-Dir $dstDir }
  Copy-Item -LiteralPath $src -Destination $dst -Force

  $fi = Get-Item -LiteralPath $dst -ErrorAction Stop
  [void]$ManifestLines.Add(($rel -replace "\\","/") + "`t" + [string][int64]$fi.Length)
  [void]$HashLines.Add((Sha256HexFile $dst) + "  " + (($rel -replace "\\","/")))
}

[void]$ManifestLines.Add("tier0_stdout.txt" + "`t" + [string][int64](Get-Item -LiteralPath $StdOut -ErrorAction Stop).Length)
[void]$ManifestLines.Add("tier0_stderr.txt" + "`t" + [string][int64](Get-Item -LiteralPath $StdErr -ErrorAction Stop).Length)
[void]$HashLines.Add((Sha256HexFile $StdOut) + "  tier0_stdout.txt")
[void]$HashLines.Add((Sha256HexFile $StdErr) + "  tier0_stderr.txt")

Write-Utf8NoBomLf (Join-Path $FreezeDir "tier0_manifest.tsv") ((@($ManifestLines.ToArray()) -join "`n") + "`n")
Write-Utf8NoBomLf (Join-Path $FreezeDir "sha256sums.txt")      ((@($HashLines.ToArray()) -join "`n") + "`n")

$Receipt = [ordered]@{
  schema              = "dodwk.tier0.freeze.receipt.v1"
  run_id              = $RunId
  repo_root           = $RepoRoot
  tier0_runner        = "scripts/_RUN_dodwk_tier0_full_green_v1.ps1"
  tier0_runner_sha256 = Sha256HexFile $RunnerPath
  stdout_sha256       = Sha256HexFile $StdOut
  stderr_sha256       = Sha256HexFile $StdErr
  manifest_sha256     = Sha256HexFile (Join-Path $FreezeDir "tier0_manifest.tsv")
  sha256sums_sha256   = Sha256HexFile (Join-Path $FreezeDir "sha256sums.txt")
  freeze_dir          = $FreezeDir
  token               = "DODWK_TIER0_FREEZE_OK"
  frozen_utc          = (Get-Date).ToUniversalTime().ToString("o")
}
Write-Utf8NoBomLf (Join-Path $FreezeDir "freeze_receipt.json") (($Receipt | ConvertTo-Json -Depth 8 -Compress))

$Latest = Join-Path $FreezeRoot "LATEST.txt"
Write-Utf8NoBomLf $Latest ($FreezeDir + "`n")

Write-Host ("FREEZE_DIR_OK: " + $FreezeDir) -ForegroundColor Green
Write-Host "DODWK_TIER0_FREEZE_OK" -ForegroundColor Green
