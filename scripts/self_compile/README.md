# Self-Compilation Correctness Pipeline Index

Read-only verification that zig1 self-compiles deterministically into `zig1_5`.
No `sf/src` edits anywhere in this pipeline; scripts + reports only.

## Identity

| Artifact | Value |
|----------|-------|
| zig1 md5 | `1bddf8ac5369b0d6c01b4e71c1906057` |
| git HEAD | `ce465ec8761a0c7f61823aefe98a7961c29d1ebc` |
| rebuild needed? | no — `/tmp/fx_subfolder/zig1` existed and self-compile passed at T1 |

## Task Pipeline

- **T1 baseline recon + self-compile smoke** — confirms zig1 self-compiles (rc=0, 40 `.c` in `/tmp/sc`, zero errors/PANIC); records zig1 identity. Artifacts: `scripts/self_compile/README.md` (this file).
- **T2 produce zig1_5 (self-compile)** — builds asan + clean binaries from zig1's C output. Artifacts: `scripts/self_compile/build_zig1_5.sh` → `/tmp/zig1_5/zig1_5_asan` + `/tmp/zig1_5/zig1_5_clean`.
- **T3 determinism — C output (byte → normalized)** — compares zig1 vs zig1_5 C emission across all 22 targets. Artifacts: `scripts/self_compile/determinism_c.sh` → `scripts/self_compile/det_c_report.txt`.
- **T4 runtime behavior match** — compares stdout + exit code for the 19 non-interactive examples. Artifacts: `scripts/self_compile/runtime_match.sh` → `scripts/self_compile/runtime_report.txt`.
- **T5 memory measurement** — 4 runs (zig0→zig1, zig1→zig1_5, zig1→examples, zig1_5→examples) vs 16 MB target. Artifacts: `scripts/self_compile/memory_measure.sh` → `scripts/self_compile/memory_report.txt`.
- **T6 findings report + reconciliation** — consolidated verdict + operator decision point. Artifacts: `docs/self-compilation-correctness-report.md`.

## Constraints

- Never touch/ls `sf/build/out_release/` (WEDGED).
- All compiler runs timeout-gated (`timeout 120`).
- Determinism compares zig1 vs zig1_5 only (never zig0).
- std install per binary: `mkdir -p <exe_dir>/lib && cp sf/src/std.zig sf/src/std_io.zig sf/src/std_arena.zig sf/src/std_net.zig <exe_dir>/lib/`.
