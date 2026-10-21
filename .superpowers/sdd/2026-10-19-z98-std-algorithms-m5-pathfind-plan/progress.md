# SDD ledger — plan: docs/superpowers/plans/2026-10-19-z98-std-algorithms-m5-pathfind-plan.md

Base: 64374880 (M5 amendment committed)
Seed under test: v108, archive f73943f4ce5170e3c776fb985a24cb43, binary/fixed point 21c957730d268f1e7883176fa5413b65
Task 1: complete (commits abbc7ce2 feat + 9f9bcc03 report, review clean 0C/0I/2 Minor) — std_pathfind JPS; full gate 303/303 fixtures + 7/7 crosscheck; 361k differential cases cost-clean; 50/50 random64; 3x deterministic; seed copy lists/count 38 already updated. Perf: plain JPS 0.30x A* obstacle, 0.02x open (diagonal jump cardinal scans); report-only, JPS+ not added.
Task 1b: complete (commits e0f329fe code + 5077cbbb report, review clean 0C/0I/4 Minor) — JPS+; independent 32,768-entry table exact, exhaustive/Dijkstra legality, full gate 304/304 + 7/7, 3x deterministic. Perf build-once: plus 0.127 ms open / 6.06 ms obstacle vs jpsFind 3.37/8.87; A* still faster; report-only. Peak build 33 B/cell (32 persistent + n transient).
Task 2: in progress — pathfind docs (JPS + JPS+), QUICK_REF/README/STD_README truth-ups, seed rotation v108→v109 (38 files).

