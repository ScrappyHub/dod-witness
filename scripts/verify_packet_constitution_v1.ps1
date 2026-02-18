param([Parameter(Mandatory=$true)][string]$PacketDir)
$ErrorActionPreference="Stop"
Set-StrictMode -Version Latest
function Sha256HexFile([string]$p){ $sha=[System.Security.Cryptography.SHA256]::Create(); $fs=[System.IO.File]::OpenRead($p); try{ $h=$sha.ComputeHash($fs) } finally { $fs.Dispose(); $sha.Dispose() }; return ([BitConverter]::ToString($h) -replace "-","").ToLowerInvariant() }
$manifest = Join-Path $PacketDir "manifest.json"
$pidPath  = Join-Path $PacketDir "packet_id.txt"
$shaPath  = Join-Path $PacketDir "sha256sums.txt"
if(-not (Test-Path -LiteralPath $manifest -PathType Leaf)){ throw ("MANIFEST_MISSING: " + $manifest) }
if(-not (Test-Path -LiteralPath $pidPath  -PathType Leaf)){ throw ("PACKET_ID_MISSING: " + $pidPath) }
if(-not (Test-Path -LiteralPath $shaPath  -PathType Leaf)){ throw ("SHA256SUMS_MISSING: " + $shaPath) }
$expected = ([System.IO.File]::ReadAllText($pidPath,[System.Text.UTF8Encoding]::new($false)) -replace "`r`n","`n" -replace "`r","`n").Trim().ToLowerInvariant()
$actual   = Sha256HexFile $manifest
if($actual -ne $expected){ throw ("PACKET_ID_MISMATCH expected=" + $expected + " actual=" + $actual) }
$lines = @([System.IO.File]::ReadAllLines($shaPath,[System.Text.UTF8Encoding]::new($false)))
foreach($ln in $lines){
  if([string]::IsNullOrWhiteSpace($ln)){ continue }
  $m = [regex]::Match($ln, "^(?<hex>[0-9a-fA-F]{64})\s+(?<rel>.+)$")
  if(-not $m.Success){ throw ("SHA256SUMS_BAD_LINE: " + $ln) }
  $hex = $m.Groups["hex"].Value.ToLowerInvariant()
  $rel = $m.Groups["rel"].Value
  if($rel.Contains("..") -or $rel.StartsWith("\") -or $rel.StartsWith("/")){ throw ("SHA256SUMS_BAD_PATH: " + $rel) }
  $abs = Join-Path $PacketDir $rel
  if(-not (Test-Path -LiteralPath $abs -PathType Leaf)){ throw ("FILE_MISSING: " + $rel) }
  $got = Sha256HexFile $abs
  if($got -ne $hex){ throw ("HASH_MISMATCH: " + $rel + " expected=" + $hex + " got=" + $got) }
}
Write-Host "VERIFY_PACKET_CONSTITUTION_OK" -ForegroundColor Green
