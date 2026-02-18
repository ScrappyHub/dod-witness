param(
  [Parameter(Mandatory=$true)][string]$RepoRoot,
  [Parameter(Mandatory=$true)][string]$PayloadDir,
  [Parameter(Mandatory=$true)][string]$OutPacketDir,
  [Parameter(Mandatory=$true)][string]$Producer,
  [Parameter(Mandatory=$true)][string]$ProducerInstance,
  [Parameter(Mandatory=$true)][string]$Namespace,
  [Parameter(Mandatory=$true)][string]$Principal,
  [Parameter(Mandatory=$true)][string]$KeyId,
  [Parameter(Mandatory=$true)][string]$SigningKeyPath
)
$ErrorActionPreference="Stop"
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot "_lib_canonjson_v1.ps1")
. (Join-Path $PSScriptRoot "_lib_sha256_v1.ps1")
. (Join-Path $PSScriptRoot "_lib_neverlost_v1.ps1")
. (Join-Path $PSScriptRoot "_lib_receipts_v1.ps1")

function IsoUtcNow(){ [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ss.fffZ") }
function Write-Utf8NoBomLf([string]$Path,[string]$Text){
  $dir = Split-Path -Parent $Path
  if($dir -and -not (Test-Path -LiteralPath $dir -PathType Container)){ New-Item -ItemType Directory -Force -Path $dir | Out-Null }
  $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
  $norm = ($Text -replace "`r`n","`n") -replace "`r","`n"
  [System.IO.File]::WriteAllBytes($Path,$utf8NoBom.GetBytes($norm))
}

if(-not (Test-Path -LiteralPath $PayloadDir -PathType Container)){ throw ("PAYLOADDIR_NOT_FOUND: " + $PayloadDir) }
New-Item -ItemType Directory -Force -Path $OutPacketDir | Out-Null
$payloadOut = Join-Path $OutPacketDir "payload"
$sigOut     = Join-Path $OutPacketDir "signatures"
New-Item -ItemType Directory -Force -Path $payloadOut | Out-Null
New-Item -ItemType Directory -Force -Path $sigOut | Out-Null

# 1) Write ALL payload files first
# Copy payload directory tree deterministically (file bytes; metadata ignored)
$srcFiles = Get-ChildItem -LiteralPath $PayloadDir -Recurse -File | Sort-Object FullName
foreach($f in $srcFiles){
  $rel = $f.FullName.Substring($PayloadDir.Length).TrimStart("\","/")
  $dst = Join-Path $payloadOut $rel
  $ddir = Split-Path -Parent $dst
  if($ddir -and -not (Test-Path -LiteralPath $ddir -PathType Container)){ New-Item -ItemType Directory -Force -Path $ddir | Out-Null }
  Copy-Item -LiteralPath $f.FullName -Destination $dst -Force
}

# 2) Write manifest.json WITHOUT packet_id using canonical JSON bytes (Option A)
# Minimal manifest shape for transport physics; application may extend in payload, not here.
$manifest = @{
  schema="packet.manifest.v1";
  producer=$Producer;
  producer_instance=$ProducerInstance;
  produced_utc=(IsoUtcNow);
  option="A";
  files=@();
}
# enumerate required files (payload/** only here; packet-level files added later in sha256sums)
$files = Get-ChildItem -LiteralPath $payloadOut -Recurse -File | Sort-Object FullName
$list = New-Object System.Collections.Generic.List[hashtable]
foreach($f in $files){
  $rel = $f.FullName.Substring($OutPacketDir.Length).TrimStart("\","/") -replace "\\","/"
  [void]$list.Add(@{ path=$rel; bytes=[int64]$f.Length; sha256=(Sha256HexFile $f.FullName) })
}
$manifest.files = @($list)
$manifestPath = Join-Path $OutPacketDir "manifest.json"
Write-Utf8NoBomLf $manifestPath ((ConvertTo-CanonJson $manifest) + "`n")

# 3) Write detached signatures AFTER payload + manifest exist
$sigPath = Join-Path $sigOut "manifest.sig"
SshY-Sign -Namespace $Namespace -KeyPath $SigningKeyPath -MessagePath $manifestPath -SigOut $sigPath

# 4) Compute PacketId from canonical bytes of manifest-without-id (manifest.json on disk is already without id)
$mbytes = [System.IO.File]::ReadAllBytes($manifestPath)
$packetId = Sha256HexBytes $mbytes

# 5) Persist PacketId (Option A: packet_id.txt)
$pidPath = Join-Path $OutPacketDir "packet_id.txt"
Write-Utf8NoBomLf $pidPath ($packetId + "`n")

# 6) Generate sha256sums.txt LAST over final on-disk bytes of ALL required files
$shaPath = Join-Path $OutPacketDir "sha256sums.txt"
$all = Get-ChildItem -LiteralPath $OutPacketDir -Recurse -File | Sort-Object FullName
$lines = New-Object System.Collections.Generic.List[string]
foreach($f in $all){
  $rel = $f.FullName.Substring($OutPacketDir.Length).TrimStart("\","/") -replace "\\","/"
  $h = Sha256HexFile $f.FullName
  [void]$lines.Add(($h + "  " + $rel))
}
Write-Utf8NoBomLf $shaPath (($lines -join "`n") + "`n")

# 7) Emit receipts LAST
$rec = @{
  schema="packet.build.receipt.v1";
  time_utc=(IsoUtcNow);
  packet_id=$packetId;
  manifest_sha256=(Sha256HexFile $manifestPath);
  packet_id_txt_sha256=(Sha256HexFile $pidPath);
  signatures_manifest_sig_sha256=(Sha256HexFile $sigPath);
  sha256sums_sha256=(Sha256HexFile $shaPath);
  option="A"
}
Append-ReceiptLine -RepoRoot $RepoRoot -Obj $rec
Write-Host ("OK: packet built (Option A) packet_id=" + $packetId) -ForegroundColor Green
Write-Host ("DIR: " + $OutPacketDir) -ForegroundColor Green
