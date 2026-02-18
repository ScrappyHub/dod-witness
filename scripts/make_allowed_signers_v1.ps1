param([Parameter(Mandatory=$true)][string]$RepoRoot)
$ErrorActionPreference="Stop"
Set-StrictMode -Version Latest
$tbPath = Join-Path $RepoRoot "proofs\trust\trust_bundle.json"
if(-not (Test-Path -LiteralPath $tbPath -PathType Leaf)){ throw ("TRUST_BUNDLE_MISSING: " + $tbPath) }
$tb = ([System.IO.File]::ReadAllText($tbPath,[System.Text.UTF8Encoding]::new($false)) | ConvertFrom-Json)
$principal = [string]$tb.principal; $pub=[string]$tb.public_key; $ns=@(@($tb.namespaces))
if([string]::IsNullOrWhiteSpace($principal)){ throw "TRUST_BUNDLE_BAD_PRINCIPAL" }
if([string]::IsNullOrWhiteSpace($pub)){ throw "TRUST_BUNDLE_BAD_PUBLIC_KEY" }
if($ns.Count -lt 1){ throw "TRUST_BUNDLE_BAD_NAMESPACES" }
$asPath = Join-Path $RepoRoot "proofs\trust\allowed_signers"
$line = $principal + " " + $pub + "`n"
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllBytes($asPath,$utf8NoBom.GetBytes($line))
Write-Host ("ALLOWED_SIGNERS_OK: " + $asPath) -ForegroundColor Green
