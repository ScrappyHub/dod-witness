# Packet Constitution v1 — test_vectors

This folder holds golden vectors used to prove independent implementations converge.

Required items per vector:
- canonical manifest-without-id bytes (golden)
- expected PacketId
- expected sha256sums content (golden)
- expected verification result

NOTE: signatures require a fixed test keypair and fixed allowed_signers for reproducible vectors.
