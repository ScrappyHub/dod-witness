# UNIVERSAL TRANSPORT LAW - PACKET CONSTITUTION v1 (GLOBAL, PROJECT-AGNOSTIC)

## Scope (Global)
This law applies to EVERY project/tool that produces, moves, ingests, or verifies directory-bundle packets (offline/airgapped or online). No project is exempt.

## Locked definitions
- Canonical bytes = exact on-disk bytes used for hashing/verification:
  - UTF-8 no BOM
  - LF newlines
  - canonical JSON serialization (stable ordering; no whitespace; stable escaping)
- PacketId derivation (locked):
  PacketId = SHA-256( canonical_bytes( manifest-without-id ) )

## Design choice (locked)
### Option A (RECOMMENDED; default)
- manifest.json MUST NOT contain packet_id
- packet_id.txt contains PacketId
- sha256sums.txt hashes manifest.json, packet_id.txt, signatures/**, and all required files

### Option B (allowed but harder)
- manifest.json MAY contain packet_id
- PacketId MUST still be derived from canonical bytes of manifest-without-id
- sha256sums.txt generated only after final manifest is written

Option A is preferred because it removes manifest mutation as a class of bugs.

## Locked finalization pipeline (mandatory order)
1) Write ALL payload files first (payload/**).
2) Write manifest.json WITHOUT packet_id using canonical JSON bytes.
3) Write detached signatures AFTER payload + manifest exist (signatures/**).
4) Compute PacketId from canonical bytes of manifest-without-id.
5) Persist PacketId:
   - Option A: write packet_id.txt
   - Option B: embed into manifest (ONLY if hash input remains manifest-without-id bytes)
6) Generate sha256sums.txt LAST over final on-disk bytes of ALL required files.
7) Emit receipts LAST, referencing PacketId and hashes (manifest, sha256sums, signatures).

## Locked verification rules
- Verifiers MUST NOT mutate packets (no self-healing).
- Any repair/rewrite is a separate explicit command producing its own repair artifact + receipts.
- Verification computes hashes from on-disk bytes only and compares to sha256sums + PacketId rule.
- Signature verification must be deterministic and trust-bundle based.

## Test vectors (mandatory)
Maintain test_vectors/ with:
- minimal packet
- canonical manifest-without-id bytes (golden)
- expected PacketId
- expected sha256sums content (golden)
- expected verification result
Any compliant implementation must match the vectors exactly.

## No overseer principle
This law has no central service authority. Convergence is enforced by:
- the written law (spec)
- golden vectors
- deterministic verify receipts
Any two independent implementations must converge.

