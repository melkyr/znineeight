# SDD ledger — plan: docs/superpowers/plans/2026-10-21-phase1-m4-tls12-https-plan.md

Base: `6124dcf1` (M3 complete)
Seed under test: v115, 44 lib files, binary/fixed point `45158dcede81125a39a2c2c58478e21e`
Task 1: complete (commits 962f8328 std_tls record + 385f31a8 std_http transport + 5c4d81d8 report) — targeted 3×, full stdlib 326/0 + crosscheck 9/9; review PASS 0C/0I/3 Low (max-size protected-record framing must be handled in Task 2; report/code wording nits).
Task 2: complete (commits 3b98ebb3 handshake + 76f993ea report; fixes e79a20ef/f8f28ecf fragmented cert/handshake/x25519/SKE/atomic write, ae88c9d5/8ae40ffa arbitrary input + record limits) — targeted 8/8 3×, -fsafe; scoped reviews PASS after fixes. Full gate remains Task 4.
Security carry-over: complete (commits 9c849209 x509 + 2c9d829b report) — same-subject path backtracking, leaf RSA ≥2048, inner/outer sigalg equality; full stdlib 327/0 + crosscheck 9/9; review PASS 0C/0I (non-blocking validity-path/malformed-intermediate/PSS-SPKI notes). No seed rotation; v116 will include x509 + std_tls.
Task 3: complete (commits b9fb17bd demo + dc591c3b tier + fix e9c039df + reports) — tier_tls 13/13 ×2 with Z98_NET=1, RAM 2.5 MB under 32 MB, -osw PE32 KERNEL32+WSOCK32 gate, Wine smoke PASS; review PASS after Medium Winsock-lifetime/clock-overflow fixes. Full gate/seed remain Task 4.
Task 4: complete (commits f363eddd docs + b6682127 seed v116 + 42cc6889 report; fixes 4bc22f34 plan TlsError + f9c654f7 truth-ups) — seed v116 archive `ca0c46dcd671d50fd4f22497f5bc525a`, manifest `0c022fe049c808828704b702e6a2b2e7`, 45 files, fixed point `45158dce…`; full stdlib 327/0 + crosscheck 9/9; review PASS after exact TlsError amendment; docs-only fixes.
