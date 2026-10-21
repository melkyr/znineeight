# SDD ledger — plan: docs/superpowers/plans/2026-10-21-phase1-m2-crypto-core-plan.md
Base: 0d61bb99 (M1 complete)
Seed under test: v111, archive 5dc851a1a96c0776ef36e8e5b29774b7, fixed point 21c957730d268f1e7883176fa5413b65
Task 1: complete (commits 2a2dc138 code + 381335bb report) — std_crypto SHA-384/512, HMAC-SHA256, HKDF, BLAKE2s/HMAC, RSA PKCS#1 v1.5 + PSS verify, generic <=4096-bit modexp; three new fixtures; full gate 315/315 + crosscheck 9/9. Review Approved 0C/0I; deferred minors: SHA-512 high length word practical limit, BLAKE2s key/out_len hardening, PSS salt_len overflow-safe validation, RSA vectors OpenSSL-generated rather than literal CAVP files.
Amendment: hybrid gate policy option 3 approved; spec §7 + M2–M7 plans amended at cf1049db. Per-task targeted for new modules; full gate after shared-module edits and at every milestone closeout.

