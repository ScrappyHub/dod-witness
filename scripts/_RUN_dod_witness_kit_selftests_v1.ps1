param(
  [Parameter(Mandatory=$true)][string]$RepoRoot,
  [switch]$Deterministic,
  [string]$RunId
)
$ErrorActionPreference="Stop"
Set-StrictMode -Version Latest

function Die([string]$m){ throw $m }
function EnsureDir([string]$p){ if([string]::IsNullOrWhiteSpace($p)){ return }; if(-not (Test-Path -LiteralPath $p -PathType Container)){ New-Item -ItemType Directory -Force -Path $p | Out-Null } }
function Write-Utf8NoBomLf([string]$Path,[string]$Text){ $dir=Split-Path -Parent $Path; if($dir){ EnsureDir $dir }; $u=New-Object System.Text.UTF8Encoding($false); $t=($Text -replace "`r`n","`n") -replace "`r","`n"; if(-not $t.EndsWith("`n")){ $t += "`n" }; [System.IO.File]::WriteAllBytes($Path,$u.GetBytes($t)) }
function Sha256HexBytes([byte[]]$b){ if($null -eq $b){ $b = @() }; $sha=[System.Security.Cryptography.SHA256]::Create(); try{ $h=$sha.ComputeHash($b) } finally { $sha.Dispose() }; return ([BitConverter]::ToString($h) -replace "-","").ToLowerInvariant() }
function Sha256HexFile([string]$p){ $sha=[System.Security.Cryptography.SHA256]::Create(); $fs=[System.IO.File]::OpenRead($p); try{ $h=$sha.ComputeHash($fs) } finally { $fs.Dispose(); $sha.Dispose() }; return ([BitConverter]::ToString($h) -replace "-","").ToLowerInvariant() }

if($Deterministic){ if([string]::IsNullOrWhiteSpace($RunId)){ Die "DETERMINISTIC_REQUIRES_RUNID" } } else { if([string]::IsNullOrWhiteSpace($RunId)){ $RunId = [DateTime]::UtcNow.ToString("yyyyMMdd_HHmmssZ") } }
$scripts = Join-Path $RepoRoot "scripts"
$proofs  = Join-Path $RepoRoot "proofs"
$rcptDir = Join-Path $proofs ("receipts\dod_witness_kit_selftest\" + $RunId)
EnsureDir $rcptDir
$receiptPath = Join-Path $rcptDir "receipt.ndjson"

$ver = Join-Path $scripts "verify_packet_constitution_v1.ps1"
$pos = Join-Path $scripts "_selftest_packet_constitution_v1.ps1"
$neg = Join-Path $scripts "_selftest_packet_constitution_negative_vectors_v1.ps1"
foreach($p in @($ver,$pos,$neg)){ if(-not (Test-Path -LiteralPath $p -PathType Leaf)){ Die ("MISSING_REQUIRED_SCRIPT: " + $p) } }

$tvBase = Join-Path $RepoRoot "test_vectors\packet_constitution_v1"
$tvPos  = Join-Path $tvBase "minimal_packet"
$tvNeg  = Join-Path $tvBase "negative_suite_v1"
foreach($p in @($tvPos,$tvNeg)){ if(-not (Test-Path -LiteralPath $p -PathType Container)){ Die ("MISSING_TEST_VECTOR_DIR: " + $p) } }

function List-FilesDet([string]$root){
  $items = Get-ChildItem -LiteralPath $root -Recurse -File | Sort-Object FullName
  $out = New-Object System.Collections.Generic.List[object]
  foreach($it in $items){
    $rel = $it.FullName.Substring($root.Length)
    if($rel.StartsWith("\") -or $rel.StartsWith("/")){ $rel = $rel.Substring(1) }
    $rel2 = ($rel -replace "\\","/")
    $h = Sha256HexFile $it.FullName
    $o = [ordered]@{ rel=$rel2; sha256=$h; bytes=[int64]$it.Length }
    [void]$out.Add($o)
  }
  return $out
}

function Run-ChildPs([string]$script,[string[]]$args,[string]$tag){
  $so = Join-Path $rcptDir ("stdout_" + $tag + ".txt")
  $se = Join-Path $rcptDir ("stderr_" + $tag + ".txt")
  if(Test-Path -LiteralPath $so){ Remove-Item -LiteralPath $so -Force }
  if(Test-Path -LiteralPath $se){ Remove-Item -LiteralPath $se -Force }
  $argList = @("-NoProfile","-NonInteractive","-ExecutionPolicy","Bypass","-File",$script) + $args
  $p = Start-Process -FilePath powershell.exe -ArgumentList $argList -NoNewWindow -Wait -PassThru -RedirectStandardOutput $so -RedirectStandardError $se
  $exit = [int]$p.ExitCode
  $out = ""
  if(Test-Path -LiteralPath $so -PathType Leaf){ $out += [System.IO.File]::ReadAllText($so,[System.Text.UTF8Encoding]::new($false)) }
  if(Test-Path -LiteralPath $se -PathType Leaf){ $out += "`n" + [System.IO.File]::ReadAllText($se,[System.Text.UTF8Encoding]::new($false)) }
  $out2 = (($out -replace "`r`n","`n") -replace "`r","`n")
  return [ordered]@{ tag=$tag; exit=$exit; output_sha256=Sha256HexBytes([System.Text.UTF8Encoding]::new($false).GetBytes($out2)); stdout_path=("stdout_" + $tag + ".txt"); stderr_path=("stderr_" + $tag + ".txt") }
}

# Run positive selftest (must PASS)
$rPos = Run-ChildPs $pos @("-RepoRoot",$RepoRoot) "pos"
if($rPos.exit -ne 0){ Die ("POSITIVE_SELFTEST_FAILED exit=" + $rPos.exit) }
# Run negative selftest (must PASS = it confirms all negatives fail)
$rNeg = Run-ChildPs $neg @("-RepoRoot",$RepoRoot) "neg"
if($rNeg.exit -ne 0){ Die ("NEGATIVE_SELFTEST_FAILED exit=" + $rNeg.exit) }

# Build receipt record (append-only NDJSON)
$rec = [ordered]@{}
$rec.schema   = "dod_witness_kit.selftest_receipt.v1"
$rec.run_id   = $RunId
$rec.run_utc  = (Get-Date).ToUniversalTime().ToString("o")
$rec.repo_root = $RepoRoot
$rec.verifier_sha256 = Sha256HexFile $ver
$rec.positive_selftest_sha256 = Sha256HexFile $pos
$rec.negative_selftest_sha256 = Sha256HexFile $neg
$rec.vectors_positive = List-FilesDet $tvPos
$rec.vectors_negative = List-FilesDet $tvNeg
$rec.results = @($rPos,$rNeg)

$json = ($rec | ConvertTo-Json -Compress)
$jsonLf = (($json -replace "`r`n","`n") -replace "`r","`n")
if(-not $jsonLf.EndsWith("`n")){ $jsonLf += "`n" }
$receipt_hash = Sha256HexBytes([System.Text.UTF8Encoding]::new($false).GetBytes($jsonLf))
$line = $jsonLf.TrimEnd("`n")
$line2 = ($line + "`n")
Write-Utf8NoBomLf $receiptPath $line2
Write-Host ("RECEIPT_OK: " + $receiptPath) -ForegroundColor Green
Write-Host ("RECEIPT_HASH_SHA256: " + $receipt_hash) -ForegroundColor Yellow
Write-Host "DOD_WITNESS_KIT_TIER0_SELFTEST_OK" -ForegroundColor Green
