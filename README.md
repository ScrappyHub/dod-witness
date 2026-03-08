# DoD Witness Kit

Deterministic milestone verification and portable evidence certification for WBS progress.

DoD Witness Kit verifies project milestones using explicit rule contracts and produces certification bundles that can be independently verified.

---

## Core Idea

A milestone claim must be provable.

Instead of:

> “Project is 70% complete.”

DoD Witness Kit produces a deterministic verification report backed by repository evidence and rule evaluation.

---

## Capabilities

* Deterministic milestone / WBS verification
* Weighted progress computation
* Rule-based completion verification
* Portable certification bundles
* Independent certification verification
* Deterministic evidence freeze artifacts

---

## Quickstart

### 1 Create an overlay contract

```powershell
scripts\dodwk_new_progress_overlay_v1.ps1 `
 -RepoRoot . `
 -ProjectId "example-project" `
 -MilestoneId "milestone-1" `
 -OutPath contracts\overlay.json
```

### 2 Verify milestone progress

```powershell
scripts\dodwk_verify_progress_overlay_v1.ps1 `
 -RepoRoot . `
 -OverlayPath contracts\overlay.json `
 -OutPath proofs\progress_report.json
```

### 3 Certify the progress report

```powershell
scripts\dodwk_certify_progress_report_v1.ps1 `
 -RepoRoot . `
 -ReportPath proofs\progress_report.json `
 -OutDir proofs\evidence
```

### 4 Verify certification bundle

```powershell
scripts\dodwk_verify_certification_v1.ps1 `
 -BundleDir proofs\evidence
```

---

## Tier-0 Instrument

The canonical Tier-0 runner is:

```
scripts/_RUN_dodwk_tier0_full_green_v1.ps1
```

It deterministically proves:

* overlay verification
* negative vectors
* certification bundle creation
* certification verification

Expected success token:

```
DODWK_TIER0_FULL_GREEN
```

---

## Tier-0 Freeze

A reproducible Tier-0 state can be frozen using:

```
scripts/_patch/_PATCH_dodwk_tier0_freeze_v1.ps1
```

Freeze artifacts are written to:

```
proofs/freeze/dodwk_tier0/
```

Each freeze includes:

* manifest of canonical files
* sha256sums
* runner stdout/stderr
* freeze receipt

---

## License

Open source instrument for deterministic milestone verification.

Enterprise hosted platform coming soon.
