param(
  [string]$Repo = ".",
  [string]$Wbs = ".\specs\wbs.v1.json",
  [string]$Overlay = ".\specs\overlay.v1.json"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Die([string]$m){
  Write-Host ("DODWK_STATIC_SETUP_FAIL: " + $m) -ForegroundColor Red
  exit 1
}

function Run-Step([string]$Name,[string]$ScriptPath,[string[]]$ChildArgs){
  if(-not (Test-Path -LiteralPath $ScriptPath -PathType Leaf)){
    Die ("SCRIPT_MISSING:" + $ScriptPath)
  }

  [void][ScriptBlock]::Create((Get-Content -Raw -LiteralPath $ScriptPath))

  Write-Host ("RUNNING: " + $Name) -ForegroundColor Cyan

  & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $ScriptPath @ChildArgs
  $code = $LASTEXITCODE
  if($null -eq $code){ $code = 0 }

  if($code -ne 0){
    Die ($Name + "_EXIT_" + $code)
  }

  Write-Host ("PASSED: " + $Name) -ForegroundColor Green
}

$Root = "C:\dev\dod-witness-kit"
Set-Location $Root

$ResolvedRepo = (Resolve-Path -LiteralPath $Repo).Path

Run-Step "code_scan" "$Root\scripts\dodwk_code_scan_v1.ps1" @("-Repo",$ResolvedRepo,"-Out",".\dodwk\code")
Run-Step "repo_hygiene" "$Root\scripts\dodwk_repo_hygiene_v1.ps1" @("-Repo",$ResolvedRepo,"-Out",".\dodwk\repo")
Run-Step "repo_classify" "$Root\scripts\dodwk_repo_classify_v1.ps1" @("-Repo",$ResolvedRepo,"-Out",".\dodwk\repo")
Run-Step "semantic_intent" "$Root\scripts\dodwk_semantic_intent_v1.ps1" @("-Repo",$ResolvedRepo,"-Out",".\dodwk\semantic")
Run-Step "repo_graph" "$Root\scripts\dodwk_repo_graph_v1.ps1" @("-Repo",$ResolvedRepo,"-Out",".\dodwk\graph")
Run-Step "repo_graph_semantics" "$Root\scripts\dodwk_repo_graph_semantics_v1.ps1" @("-Graph",".\dodwk\graph\repo_graph.v1.json","-Out",".\dodwk\graph")
Run-Step "repo_graph_governance" "$Root\scripts\dodwk_repo_graph_governance_v1.ps1" @("-GraphSemantics",".\dodwk\graph\repo_graph_semantics.v1.json","-Out",".\dodwk\graph")
Run-Step "governance_decisions" "$Root\scripts\dodwk_governance_decision_v1.ps1" @("-GraphGovernance",".\dodwk\graph\repo_graph_governance.v1.json","-Out",".\dodwk\decision")
Run-Step "symbol_graph" "$Root\scripts\dodwk_symbol_graph_v1.ps1" @("-Repo",$ResolvedRepo,"-Out",".\dodwk\symbols")
Run-Step "symbol_relationship_graph" "$Root\scripts\dodwk_symbol_relationship_graph_v1.ps1" @("-SymbolGraph",".\dodwk\symbols\symbol_graph.v1.json","-Out",".\dodwk\symbols")
Run-Step "canonicalize_topology" "$Root\scripts\dodwk_canonicalize_topology_v1.ps1" @(
  "-Repo", $Root
)

Run-Step "dynamic_index" "$Root\scripts\dodwk_dynamic_index_v1.ps1" @("-DynamicDir",".\dodwk\dynamic","-Out",".\dodwk\dynamic")
Run-Step "ai_memory_index" "$Root\scripts\dodwk_ai_memory_index_v1.ps1" @("-MemoryDir",".\dodwk\ai_memory","-Out",".\dodwk\ai_memory")
Run-Step "status" "$Root\scripts\dodwk_status_v1.ps1" @("-Repo",$ResolvedRepo,"-Wbs",$Wbs,"-Overlay",$Overlay,"-Out",".\dodwk\status")
Run-Step "drift_v2" "$Root\scripts\dodwk_drift_v2.ps1" @("-Repo",$ResolvedRepo,"-Out",".\dodwk\drift")
Run-Step "governance_surface" "$Root\scripts\_RUN_dodwk_governance_surface_v1.ps1" @("-Repo",$ResolvedRepo,"-Wbs",$Wbs,"-Overlay",$Overlay)

Write-Host "DODWK_STATIC_SETUP_OK" -ForegroundColor Green
exit 0
