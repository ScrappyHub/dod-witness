param(
  [string]$SnapshotRoot = "",
  [string]$Out = ".\proofs\receipts\dodwk_negative_replay_vectors"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Die([string]$m){
  Write-Host ("DODWK_NEGATIVE_REPLAY_VECTORS_FAIL: " + $m) -ForegroundColor Red
  exit 1
}

function Ensure-Dir([string]$p){
  if(-not (Test-Path -LiteralPath $p -PathType Container)){
    New-Item -ItemType Directory -Force -Path $p | Out-Null
  }
}

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

function Copy-Dir([string]$Src,[string]$Dst){
  if(Test-Path -LiteralPath $Dst){ Remove-Item -LiteralPath $Dst -Recurse -Force }
  New-Item -ItemType Directory -Force -Path $Dst | Out-Null

  Get-ChildItem -LiteralPath $Src -Force | ForEach-Object {
    Copy-Item -LiteralPath $_.FullName -Destination $Dst -Recurse -Force
  }
}

function Run-Verify([string]$CaseName,[string]$CaseRoot,[string]$RunRoot){
  $stdout = Join-Path $RunRoot ($CaseName + ".stdout.txt")
  $stderr = Join-Path $RunRoot ($CaseName + ".stderr.txt")

  $p = Start-Process `
    -FilePath "powershell.exe" `
    -ArgumentList @(
      "-NoProfile",
      "-NonInteractive",
      "-ExecutionPolicy",
      "Bypass",
      "-File",
      ".\scripts\dodwk_governance_replay_verify_v1.ps1",
      "-SnapshotRoot",
      $CaseRoot,
      "-Out",
      ".\dodwk\replay"
    ) `
    -NoNewWindow `
    -Wait `
    -PassThru `
    -RedirectStandardOutput $stdout `
    -RedirectStandardError $stderr

  $out = ""
  if(Test-Path -LiteralPath $stdout -PathType Leaf){
    $out = Get-Content -Raw -LiteralPath $stdout
  }

  return @{
    case = $CaseName
    case_root = $CaseRoot
    exit_code = $p.ExitCode
    stdout = $stdout
    stderr = $stderr
    stdout_sha256 = Sha256-File $stdout
    stderr_sha256 = Sha256-File $stderr
    stdout_text = $out
  }
}

$Root = "C:\dev\dod-witness-kit"
Set-Location $Root

if([string]::IsNullOrWhiteSpace($SnapshotRoot)){
  $latest = Get-ChildItem ".\dodwk\governance_snapshots" -Directory |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1

  if($null -eq $latest){ Die "NO_SNAPSHOT_FOUND" }
  $SnapshotRoot = $latest.FullName
}

$ResolvedSnapshot = (Resolve-Path -LiteralPath $SnapshotRoot).Path

$RunId = Get-Date -Format "yyyyMMdd_HHmmss"
$RunRoot = Join-Path $Out $RunId
$CasesRoot = Join-Path $RunRoot "cases"
Ensure-Dir $CasesRoot

$cases = @()

# Case 1: tamper snapshot manifest, causing snapshot_id mismatch.
$case1 = Join-Path $CasesRoot "neg_manifest_hash_mismatch"
Copy-Dir $ResolvedSnapshot $case1
Add-Content -LiteralPath (Join-Path $case1 "snapshot_manifest.v1.json") -Value " " -Encoding UTF8
$cases += @{
  name = "neg_manifest_hash_mismatch"
  root = $case1
  expected_nonzero = $true
  expected_token = "DODWK_GOVERNANCE_REPLAY_VERIFY_FAIL"
}

# Case 2: missing artifact.
$case2 = Join-Path $CasesRoot "neg_missing_artifact"
Copy-Dir $ResolvedSnapshot $case2
Remove-Item -LiteralPath (Join-Path $case2 "repo_graph.v1.json") -Force
$cases += @{
  name = "neg_missing_artifact"
  root = $case2
  expected_nonzero = $true
  expected_token = "DODWK_GOVERNANCE_REPLAY_VERIFY_FAIL"
}

# Case 3: corrupt sha256sums.
$case3 = Join-Path $CasesRoot "neg_sha256sums_corrupt"
Copy-Dir $ResolvedSnapshot $case3
$sumPath = Join-Path $case3 "sha256sums.txt"
$sumText = Get-Content -Raw -LiteralPath $sumPath
$sumText = $sumText.Replace("a","b")
Write-Utf8NoBomLf $sumPath $sumText
$cases += @{
  name = "neg_sha256sums_corrupt"
  root = $case3
  expected_nonzero = $true
  expected_token = "DODWK_GOVERNANCE_REPLAY_VERIFY_FAIL"
}

# Case 4: tamper symbol graph.
$case4 = Join-Path $CasesRoot "neg_symbol_graph_tamper"
Copy-Dir $ResolvedSnapshot $case4
Add-Content -LiteralPath (Join-Path $case4 "symbol_graph.v1.json") -Value " " -Encoding UTF8
$cases += @{
  name = "neg_symbol_graph_tamper"
  root = $case4
  expected_nonzero = $true
  expected_token = "DODWK_GOVERNANCE_REPLAY_VERIFY_FAIL"
}

# Case 5: tamper governance decisions.
$case5 = Join-Path $CasesRoot "neg_governance_decision_tamper"
Copy-Dir $ResolvedSnapshot $case5
Add-Content -LiteralPath (Join-Path $case5 "governance_decisions.v1.json") -Value " " -Encoding UTF8
$cases += @{
  name = "neg_governance_decision_tamper"
  root = $case5
  expected_nonzero = $true
  expected_token = "DODWK_GOVERNANCE_REPLAY_VERIFY_FAIL"
}

$results = @()
$failures = @()

foreach($c in $cases){
  $r = Run-Verify ([string]$c.name) ([string]$c.root) $RunRoot

  $nonzeroOk = ([int]$r.exit_code -ne 0)
  $tokenOk = ([string]$r.stdout_text -like ("*" + [string]$c.expected_token + "*"))

  $status = "pass"
  if(-not $nonzeroOk -or -not $tokenOk){
    $status = "fail"
    $failures += ([string]$c.name)
  }

  $results += @{
    case = [string]$c.name
    status = $status
    exit_code = [int]$r.exit_code
    expected_nonzero = $true
    expected_token = [string]$c.expected_token
    token_found = $tokenOk
    stdout = [string]$r.stdout
    stderr = [string]$r.stderr
    stdout_sha256 = [string]$r.stdout_sha256
    stderr_sha256 = [string]$r.stderr_sha256
  }

  if($status -eq "pass"){
    Write-Host ("NEG_CASE_OK: " + [string]$c.name) -ForegroundColor Green
  } else {
    Write-Host ("NEG_CASE_FAIL: " + [string]$c.name) -ForegroundColor Red
  }
}

$statusAll = "pass"
if(@($failures).Count -gt 0){ $statusAll = "fail" }

$receipt = @{
  schema = "dodwk.negative_replay_vectors.v1"
  run_id = $RunId
  source_snapshot = $ResolvedSnapshot
  status = $statusAll
  cases_total = @($cases).Count
  passed = @($results | Where-Object { $_.status -eq "pass" }).Count
  failed = @($failures).Count
  static_analysis = $true
  ai_required = $false
  proof_status = "negative_replay_vectors"
  results = $results
}

Write-Utf8NoBomLf (Join-Path $RunRoot "negative_replay_vectors.v1.json") ($receipt | ConvertTo-Json -Depth 60)

$md = @()
$md += "# DODWK Negative Replay Vectors"
$md += ""
$md += "- Status: $statusAll"
$md += "- Cases total: $(@($cases).Count)"
$md += "- Passed: $($receipt.passed)"
$md += "- Failed: $($receipt.failed)"
$md += "- Source snapshot: $ResolvedSnapshot"
$md += "- AI required: false"
$md += ""
$md += "## Cases"
foreach($r in $results){
  $md += ("- [" + $r.status + "] " + $r.case + " exit=" + $r.exit_code + " token_found=" + $r.token_found)
}
Write-Utf8NoBomLf (Join-Path $RunRoot "negative_replay_vectors.summary.md") ($md -join "`n")

$hashRows = @()
Get-ChildItem -LiteralPath $RunRoot -File |
  Where-Object { $_.Name -ne "sha256sums.txt" } |
  Sort-Object Name |
  ForEach-Object {
    $hashRows += ((Sha256-File $_.FullName) + "  " + $_.Name)
  }

Write-Utf8NoBomLf (Join-Path $RunRoot "sha256sums.txt") ($hashRows -join "`n")

if($statusAll -ne "pass"){
  Write-Host "DODWK_NEGATIVE_REPLAY_VECTORS_FAIL" -ForegroundColor Red
  Write-Host ("RUN_ROOT: " + $RunRoot)
  exit 1
}

Write-Host "DODWK_NEGATIVE_REPLAY_VECTORS_OK" -ForegroundColor Green
Write-Host ("RUN_ROOT: " + $RunRoot)
Write-Host ("CASES: " + @($cases).Count)
exit 0
