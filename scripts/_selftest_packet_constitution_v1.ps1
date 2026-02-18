param([Parameter(Mandatory=$true)][string]$RepoRoot)
$ErrorActionPreference="Stop"
Set-StrictMode -Version Latest
$packet = Join-Path $RepoRoot "test_vectors\packet_constitution_v1\minimal_packet"
$ver = Join-Path $RepoRoot "scripts\verify_packet_constitution_v1.ps1"
& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $ver -PacketDir $packet | Out-Host
if($LASTEXITCODE -ne 0){ throw ("SELFTEST_PACKET_CONSTITUTION_FAILED exit=" + $LASTEXITCODE) }
foreach($p in @("manifest_without_id.bytes","expected_packet_id.txt","expected_sha256sums.txt")){ $f=Join-Path $packet $p; if(-not (Test-Path -LiteralPath $f -PathType Leaf)){ throw ("MISSING_GOLDEN: " + $f) } }
Write-Host "SELFTEST_PACKET_CONSTITUTION_OK" -ForegroundColor Green
