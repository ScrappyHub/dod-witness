param(
  [Parameter(Mandatory=$true)][string]$RepoRoot,
  [Parameter(Mandatory=$true)][string]$PacketDir,
  [Parameter(Mandatory=$true)][string]$Namespace,
  [Parameter(Mandatory=$true)][string]$Principal
)
$ErrorActionPreference="Stop"
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot "_lib_sha256_v1.ps1")
. (Join-Path $PSScriptRoot "_lib_neverlost_v1.ps1")
. (Join-Path $PSScriptRoot "_lib_receipts_v1.ps1")

function IsoUtcNow(){ [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ss.fffZ") }

$manifestPath = Join-Path $PacketDir "manifest.json"
$pidPath      = Join-Path $PacketDir "packet_id.txt"
$shaPath      = Join-Path $PacketDir "sha256sums.txt"
$sigPath      = Join-Path (Join-Path $PacketDir "signatures") "manifest.sig"
foreach($p in @($manifestPath,$pidPath,$shaPath,$sigPath)){ if(-not (Test-Path -LiteralPath $p -PathType Leaf)){ throw ("PACKET_MISSING_FILE: " + $p) } }

# Verify PacketId rule (Option A): packet_id.txt equals SHA256(bytes(manifest.json))
$want = ([System.IO.File]::ReadAllText($pidPath,[System.Text.UTF8Encoding]::new($false))).Trim()
$mbytes = [System.IO.File]::ReadAllBytes($manifestPath)
$derived = Sha256HexBytes $mbytes
if($derived -ne $want){ throw ("PACKET_ID_MISMATCH want=" + $want + " derived=" + $derived) }

# Verify sha256sums against on-disk bytes (NON-MUTATING)
$lines = @(@([System.IO.File]::ReadAllText($shaPath,[System.Text.UTF8Encoding]::new($false)) -split "`n",-1)) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
foreach($ln in $lines){
  $m = [regex]::Match($ln,'^([a-f0-9]{64})\s\s(.+)$')
  if(-not $m.Success){ throw ("SHA256SUMS_BAD_LINE: " + $ln) }
  $h = $m.Groups[1].Value
  $rel = $m.Groups[2].Value
  $abs = Join-Path $PacketDir ($rel -replace "/","\")
  if(-not (Test-Path -LiteralPath $abs -PathType Leaf)){ throw ("SHA256SUMS_MISSING_TARGET: " + $rel) }
  $got = Sha256HexFile $abs
  if($got -ne $h){ throw ("SHA256SUM_MISMATCH: " + $rel + " want=" + $h + " got=" + $got) }
}

# Verify signature over manifest.json via allowed_signers derived from trust_bundle (repo boundary)
$as = Join-Path $RepoRoot "proofs\trust\allowed_signers"
if(-not (Test-Path -LiteralPath $as -PathType Leaf)){ throw "ALLOWED_SIGNERS_MISSING (run scripts\\make_allowed_signers_v1.ps1)" }
[void](SshY-Verify -Namespace $Namespace -AllowedSigners $as -Principal $Principal -SigPath $sigPath -MessagePath $manifestPath)

# deterministic verify receipt (does not modify packet)
$rec = @{
  schema="packet.verify.receipt.v1";
  time_utc=(IsoUtcNow);
  packet_id=$want;
  ok=$true;
  manifest_sha256=(Sha256HexFile $manifestPath);
  packet_id_txt_sha256=(Sha256HexFile $pidPath);
  sha256sums_sha256=(Sha256HexFile $shaPath);
  signatures_manifest_sig_sha256=(Sha256HexFile $sigPath)
}
Append-ReceiptLine -RepoRoot $RepoRoot -Obj $rec
Write-Host ("OK: packet verified (non-mutating) packet_id=" + $want) -ForegroundColor Green
