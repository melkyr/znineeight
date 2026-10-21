# SDD ledger — plan: docs/superpowers/plans/2026-10-21-phase1-m1-preflight-rss-plan.md
Base: 6cc1485f (Phase 1 plans committed)
Seed under test: v111, archive 5dc851a1a96c0776ef36e8e5b29774b7, fixed point 21c957730d268f1e7883176fa5413b65
Task 1: complete (commits 7fe42597 report + 7da7cd69 fix round 1) — measured fixed-point binary explicitly. Compiler-only RSS: seed-build self-emission 20792 KiB / 5.66 s, pool 18871 KiB; z9play -fsafe emit 8140 KiB / 0.36 s, pool 4609 KiB; gate compiler-only max 28836 KiB / 0.32 s. Whole-gate process-tree max 364936 KiB and whole seed build 164176/172260 KiB are gcc-dominated and explicitly non-consumable as compiler RSS. <16 MB target FAILS on RSS and pool.
Task 1 review: initial FAIL (C1 arena omitted, I1 mixed process-tree/compiler scopes, I2 unmeasured gcc dominance, M1/M2 evidence/label); fix round ADDRESSED all; no new Critical/Important.
Task 2: complete (commits 66caf63b docs + e3b4553a fix round 1) — README + QUICK_REF carry compiler-only 3-row table (20792/28836/8140 KiB), pools (18871K/n-a/4609K), exact /usr/bin/time -v recipe, honest <16 MB failure, and 16/32 MB demo budget with ulimit -v 32768. Old -s0..-s6 ladder labeled historical at 553a39b4…; current -s0 pool 18871K distinct; no gcc process-tree maxima mislabeled as compiler RSS.
Task 2 review: initial FAIL (stale current spill ladder); fix round ADDRESSED; scoped re-review PASS, no new Critical/Important.
Final review: Ready, 0 Critical / 0 Important. Deferred doc debt: stale README status fixed-point/seed claims; self-emission -ffast qualifier; row (b)/(c) commands live in Task 1 report; task-2-report workspace-only.

