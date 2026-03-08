# DoD Witness Kit

Deterministic milestone / WBS verification plus portable evidence certification.

## What this is

DoD Witness Kit is a governance-first verification instrument for proving milestone completion against explicit overlay contracts and exporting portable evidence that can be independently reviewed.

It answers questions like:

- which weighted tasks are actually complete
- what objective rules back that completion
- what percentage is justified by evidence
- what portable artifact bundle proves the result

## Core idea

A project does not become "green" because someone says it is green.

A project becomes green when an explicit overlay contract defines completion rules and the verifier proves those rules against real repository artifacts.

Examples of completion rules include:

- file exists
- parse gate passes
- selftest passes
- expected output report exists

## Current Tier-0 surfaces

### 1. Progress Overlay verification

Artifacts:

- `contracts/dodwk.progress_overlay.v1.sample.json`
- `schemas/dodwk.progress_report.v1.json`
- `scripts/dodwk_verify_progress_overlay_v1.ps1`
- `scripts/_selftest_dodwk_progress_overlay_v1.ps1`
- `scripts/_RUN_dodwk_progress_overlay_full_green_v1.ps1`

Current output:

- weighted milestone progress report
- task-by-task pass/fail
- rule-by-rule pass/fail
- deterministic success token

Success token:

- `DODWK_PROGRESS_OVERLAY_ALL_GREEN`

### 2. Portable evidence certification

Artifacts:

- `scripts/_RUN_dod_witness_kit_ship_tier0_v1.ps1`

Current output root:

- `proofs/evidence/dod_witness_kit_tier0/<RunId>/`

Current evidence includes:

- `selftest_stdout.txt`
- `selftest_stderr.txt`
- `evidence_manifest.tsv`
- `sha256sums.txt`
- `sha256_selftest_stdout.txt`
- `sha256_selftest_stderr.txt`

## Why this tool exists

Most tools track tasks manually.
Most CI tools verify builds, not milestone governance.
Most artifact tools hash outputs, not WBS completion.

DoD Witness Kit is meant to combine:

- explicit governance overlays
- deterministic milestone verification
- weighted completion reporting
- portable evidence certification

## Current status

Current green surface:

- Progress Overlay bootstrap and full-green runner
- ship/evidence sealing runner

Current next expansion:

- richer verification rule kinds
- dependency-aware blocked/ready semantics
- portable signed certification packets
- overlay authoring helpers
- uploader/import verifier flow

## Quick start

### Run progress overlay full green

```powershell
$RepoRoot = (Resolve-Path -LiteralPath "C:\dev\dod-witness-kit").Path
& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File (Join-Path $RepoRoot "scripts\_RUN_dodwk_progress_overlay_full_green_v1.ps1") -RepoRoot $RepoRoot | Out-Host
```

Expected success token:

- `DODWK_PROGRESS_OVERLAY_ALL_GREEN`

### Run ship evidence certification

```powershell
$RepoRoot = (Resolve-Path -LiteralPath "C:\dev\dod-witness-kit").Path
& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File (Join-Path $RepoRoot "scripts\_RUN_dod_witness_kit_ship_tier0_v1.ps1") -RepoRoot $RepoRoot -Deterministic -RunId "20260223_011506Z" | Out-Host
```

Expected success token:

- `DOD_WITNESS_KIT_TIER0_SHIP_OK`

## Governance notes

- UTF-8 no BOM + LF
- deterministic file writes
- parse-gate before execution
- PowerShell 5.1 compatible discipline
- no interactive dependency for canonical runners
- private keys must never be committed

## Project goal

DoD Witness Kit is the deterministic verification layer for milestone / WBS completion and portable evidence certification.

That means:

- explicit overlays define completion
- verification computes weighted progress
- evidence bundles make the result portable
- later signing and witnessing can certify the result for third parties
