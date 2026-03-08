param(
 [Parameter(Mandatory=$true)][string]$BundlePath
)

Set-StrictMode -Version Latest
$ErrorActionPreference="Stop"

$BundlePath=(Resolve-Path -LiteralPath $BundlePath).Path
$Verifier = Join-Path (Split-Path $BundlePath -Parent) "..\scripts\dodwk_verify_certification_v1.ps1"

& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $Verifier -BundleDir $BundlePath | Out-Host

if($LASTEXITCODE -ne 0){
 throw ("IMPORT_VERIFY_FAILED exit=" + $LASTEXITCODE)
}

Write-Host "IMPORT_CERTIFICATION_VERIFY_OK" -ForegroundColor Green
