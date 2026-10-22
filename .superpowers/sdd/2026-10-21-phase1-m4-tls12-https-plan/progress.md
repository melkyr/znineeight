# SDD ledger — plan: docs/superpowers/plans/2026-10-21-phase1-m4-tls12-https-plan.md

Base: `6124dcf1` (M3 complete)
Seed under test: v115, 44 lib files, binary/fixed point `45158dcede81125a39a2c2c58478e21e`
Task 1: complete (commits 962f8328 std_tls record + 385f31a8 std_http transport + 5c4d81d8 report) — targeted 3×, full stdlib 326/0 + crosscheck 9/9; review PASS 0C/0I/3 Low (max-size protected-record framing must be handled in Task 2; report/code wording nits).
Task 2: complete (commits 3b98ebb3 handshake + 76f993ea report; fixes e79a20ef/f8f28ecf fragmented cert/handshake/x25519/SKE/atomic write, ae88c9d5/8ae40ffa arbitrary input + record limits) — targeted 8/8 3×, -fsafe; scoped reviews PASS after fixes. Full gate remains Task 4.
Security carry-over: complete (commits 9c849209 x509 + 2c9d829b report) — same-subject path backtracking, leaf RSA ≥2048, inner/outer sigalg equality; full stdlib 327/0 + crosscheck 9/9; review PASS 0C/0I (non-blocking validity-path/malformed-intermediate/PSS-SPKI notes). No seed rotation; v116 will include x509 + std_tls.
