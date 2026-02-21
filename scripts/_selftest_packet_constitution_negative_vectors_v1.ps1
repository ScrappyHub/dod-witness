param([Parameter(Mandatory=$true)][string]$RepoRoot)
$ErrorActionPreference="Stop"
Set-StrictMode -Version Latest
function Die([string]$m){ throw $m }
function EnsureDir([string]$p){ if([string]::IsNullOrWhiteSpace($p)){ return }; if(-not (Test-Path -LiteralPath $p -PathType Container)){ New-Item -ItemType Directory -Force -Path $p | Out-Null } }
function ReadAllTextUtf8NoBom([string]$p){ return [System.IO.File]::ReadAllText($p,[System.Text.UTF8Encoding]::new($false)) }

$tvRoot = Join-Path $RepoRoot "test_vectors\packet_constitution_v1\negative_suite_v1"
$ver = Join-Path $RepoRoot "scripts\verify_packet_constitution_v1.ps1"
$tmp = Join-Path $RepoRoot "scripts\_scratch\_tmp_neg"
EnsureDir $tmp
if(-not (Test-Path -LiteralPath $tvRoot -PathType Container)){ Die ("MISSING_NEG_ROOT: " + $tvRoot) }
if(-not (Test-Path -LiteralPath $ver -PathType Leaf)){ Die ("MISSING_VERIFIER: " + $ver) }

$cases = @(
  @{ name="01_packet_id_mismatch"; expect="PACKET_ID_MISMATCH" },
  @{ name="02_manifest_tampered"; expect="PACKET_ID_MISMATCH" },
  @{ name="03_sha256sums_wrong_hash"; expect="HASH_MISMATCH" },
  @{ name="04_missing_sha256sums"; expect="SHA256SUMS_MISSING" },
  @{ name="05_traversal_in_sha256sums"; expect="SHA256SUMS_BAD_PATH" },
  @{ name="06_payload_tampered"; expect="HASH_MISMATCH" }
)

$allOk = $true
foreach($c in $cases){
  $dir = Join-Path $tvRoot $c.name
  if(-not (Test-Path -LiteralPath $dir -PathType Container)){ Die ("MISSING_CASE_DIR: " + $dir) }
  $expect = [string]$c.expect
  $so = Join-Path $tmp ($c.name + ".stdout.txt")
  $se = Join-Path $tmp ($c.name + ".stderr.txt")
  if(Test-Path -LiteralPath $so -PathType Leaf){ Remove-Item -LiteralPath $so -Force }
  if(Test-Path -LiteralPath $se -PathType Leaf){ Remove-Item -LiteralPath $se -Force }

  $p = Start-Process -FilePath powershell.exe -ArgumentList @(
    "-NoProfile","-NonInteractive","-ExecutionPolicy","Bypass",
    "-File",$ver,"-PacketDir",$dir
  ) -NoNewWindow -Wait -PassThru -RedirectStandardOutput $so -RedirectStandardError $se

  $exit = [int]$p.ExitCode
  $out = ""
  if(Test-Path -LiteralPath $so -PathType Leaf){ $out += (ReadAllTextUtf8NoBom $so) }
  if(Test-Path -LiteralPath $se -PathType Leaf){ $out += "`n" + (ReadAllTextUtf8NoBom $se) }
  $out2 = ($out -replace "`r`n","`n") -replace "`r","`n"

  $ok = $true
  $why = ""
  if($exit -eq 0){ $ok = $false; $why = "UNEXPECTED_EXITCODE_0" }
  elseif($out2 -notmatch [regex]::Escape($expect)){ $ok = $false; $why = ("MISSING_EXPECT_TOKEN: " + $expect) }

  if(-not $ok){
    $allOk = $false
    Write-Host ("NEG_CASE_FAIL: " + $c.name + " exit=" + $exit + " " + $why) -ForegroundColor Red
  } else {
    Write-Host ("NEG_CASE_OK: " + $c.name + " exit=" + $exit + " token=" + $expect) -ForegroundColor Green
  }
}
if(-not $allOk){ Die "SELFTEST_NEGATIVE_VECTORS_FAILED" }
Write-Host "SELFTEST_NEGATIVE_VECTORS_OK" -ForegroundColor Green
