param(
  [Parameter(Mandatory=$true)][ValidateSet("register","list")][string]$Mode,
  [string]$RepoPath = "",
  [string]$Name = "",
  [string]$Out = ".\dodwk\registry"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Ensure-Dir([string]$p){
  if(-not (Test-Path -LiteralPath $p -PathType Container)){
    New-Item -ItemType Directory -Force -Path $p | Out-Null
  }
}

function Write-Utf8NoBomLf([string]$Path,[string]$Text){
  $parent = Split-Path -Parent $Path
  if($parent){ Ensure-Dir $parent }
  $t = $Text.Replace("`r`n","`n").Replace("`r","`n")
  if(-not $t.EndsWith("`n")){ $t += "`n" }
  $enc = New-Object System.Text.UTF8Encoding($false)
  [System.IO.File]::WriteAllText($Path,$t,$enc)
}

function Hash-Text16([string]$Text){
  $sha = [System.Security.Cryptography.SHA256]::Create()
  try{
    $bytes = [Text.Encoding]::UTF8.GetBytes($Text)
    return (($sha.ComputeHash($bytes) | ForEach-Object { $_.ToString("x2") }) -join "").Substring(0,16)
  } finally {
    $sha.Dispose()
  }
}

function Read-JsonOrEmpty([string]$Path){
  if(-not (Test-Path -LiteralPath $Path -PathType Leaf)){
    return @{
      schema = "dodwk.repo_registry.v1"
      repos = @()
    }
  }
  return ((Get-Content -Raw -LiteralPath $Path) | ConvertFrom-Json)
}

Ensure-Dir $Out

$RegistryPath = Join-Path $Out "repo_registry.v1.json"

$registry = Read-JsonOrEmpty $RegistryPath
$repos = @($registry.repos)

if($Mode -eq "register"){
  if([string]::IsNullOrWhiteSpace($RepoPath)){ throw "REPO_PATH_REQUIRED" }

  $resolved = (Resolve-Path -LiteralPath $RepoPath).Path

  if([string]::IsNullOrWhiteSpace($Name)){
    $Name = Split-Path -Leaf $resolved
  }

  $repoId = Hash-Text16 $resolved

  $existing = @($repos | Where-Object { [string]$_.repo_id -eq $repoId })

  $entry = @{
    repo_id = $repoId
    name = $Name
    path = $resolved
    registered_utc = (Get-Date).ToUniversalTime().ToString("o")
    proof_status = "registered"
    static_truth_required = $true
    dynamic_advisory_allowed = $true
  }

  if(@($existing).Count -eq 0){
    $repos += $entry
  } else {
    $newRepos = @()
    foreach($r in $repos){
      if([string]$r.repo_id -eq $repoId){ $newRepos += $entry } else { $newRepos += $r }
    }
    $repos = $newRepos
  }
}

$result = @{
  schema = "dodwk.repo_registry.v1"
  repos_total = @($repos).Count
  repos = $repos
  static_registry = $true
  ai_required = $false
}

Write-Utf8NoBomLf $RegistryPath ($result | ConvertTo-Json -Depth 30)

$lines = @()
$lines += "# DODWK Repo Registry"
$lines += ""
$lines += "- Repos total: $(@($repos).Count)"
$lines += "- Static registry: true"
$lines += "- AI required: false"
$lines += ""
foreach($r in $repos){
  $lines += ("- " + $r.repo_id + " :: " + $r.name + " :: " + $r.path)
}

Write-Utf8NoBomLf (Join-Path $Out "repo_registry.summary.md") ($lines -join "`n")

Write-Host "DODWK_REPO_REGISTRY_OK"
Write-Host ("MODE: " + $Mode)
Write-Host ("REPOS_TOTAL: " + @($repos).Count)
exit 0
