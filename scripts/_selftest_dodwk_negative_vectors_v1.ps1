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

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$Verifier = Join-Path $RepoRoot "scripts\dodwk_verify_progress_overlay_v1.ps1"
$BaseOut = Join-Path $RepoRoot "proofs\receipts\dodwk_negative_vectors"
Ensure-Dir $BaseOut

# vector 1: missing file
$V1Dir = Join-Path $BaseOut "missing_file"
Ensure-Dir $V1Dir
$V1Overlay = Join-Path $V1Dir "overlay.json"
$V1Report  = Join-Path $V1Dir "report.json"
$V1 = [ordered]@{
  schema = "dodwk.progress_overlay.v1"
  project_id = "dod-witness-kit"
  milestone_id = "negative-missing-file"
  tasks = @(
    [ordered]@{
      task_id = "N1"
      title = "Missing file must fail"
      weight = 100
      depends_on = @()
      completion_rules = @(
        [ordered]@{ kind = "file_exists"; path = "scripts\THIS_FILE_DOES_NOT_EXIST.ps1" }
      )
    }
  )
}
Write-Utf8NoBomLf $V1Overlay (($V1 | ConvertTo-Json -Depth 8 -Compress))
& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $Verifier -RepoRoot $RepoRoot -OverlayPath $V1Overlay -OutPath $V1Report | Out-Host
if($LASTEXITCODE -ne 0){ throw "NEGATIVE_VECTOR_1_VERIFIER_FAILED" }
$R1 = Get-Content -LiteralPath $V1Report -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
if([double]$R1.progress_percent -ne 0){ throw "NEGATIVE_VECTOR_1_EXPECTED_ZERO" }

# vector 2: bad json field equals
$V2Dir = Join-Path $BaseOut "json_field_mismatch"
Ensure-Dir $V2Dir
$Probe = Join-Path $V2Dir "probe.json"
Write-Utf8NoBomLf $Probe '{"schema":"wrong.value"}'
$V2Overlay = Join-Path $V2Dir "overlay.json"
$V2Report  = Join-Path $V2Dir "report.json"
$V2 = [ordered]@{
  schema = "dodwk.progress_overlay.v1"
  project_id = "dod-witness-kit"
  milestone_id = "negative-json-field"
  tasks = @(
    [ordered]@{
      task_id = "N2"
      title = "Json field mismatch must fail"
      weight = 100
      depends_on = @()
      completion_rules = @(
        [ordered]@{ kind = "json_field_equals"; path = "proofs/receipts/dodwk_negative_vectors/json_field_mismatch/probe.json"; field = "schema"; expected = "expected.value" }
      )
    }
  )
}
Write-Utf8NoBomLf $V2Overlay (($V2 | ConvertTo-Json -Depth 8 -Compress))
& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $Verifier -RepoRoot $RepoRoot -OverlayPath $V2Overlay -OutPath $V2Report | Out-Host
if($LASTEXITCODE -ne 0){ throw "NEGATIVE_VECTOR_2_VERIFIER_FAILED" }
$R2 = Get-Content -LiteralPath $V2Report -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
if([double]$R2.progress_percent -ne 0){ throw "NEGATIVE_VECTOR_2_EXPECTED_ZERO" }

Write-Host "SELFTEST_DODWK_NEGATIVE_VECTORS_OK" -ForegroundColor Green
