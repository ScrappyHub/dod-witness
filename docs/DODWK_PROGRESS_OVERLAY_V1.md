# DoD Witness Kit - Progress Overlay v1

Purpose: deterministic milestone / WBS verification plus portable evidence certification.

## Supported rule kinds

- file_exists
- path_not_exists
- parse_gate
- stdout_contains
- exit_code
- json_field_equals
- sha256_equals

## Current sample overlay

The sample overlay proves:
- verifier exists and parse-gates
- report schema exists
- selftest exists
- full-green runner emits the expected token
- selftest report proves 100 percent completion

## Outputs

Verifier output:
- reports weighted progress
- records rule-by-rule pass or fail
- records blocked_by dependencies
- writes a deterministic progress report JSON

Success tokens:
- SELFTEST_DODWK_PROGRESS_OVERLAY_OK
- DODWK_PROGRESS_OVERLAY_ALL_GREEN
