# SDD ledger — plan: docs/superpowers/plans/2026-10-19-z9play-streaming-playback-plan.md

Spec: docs/superpowers/specs/2026-10-19-z9play-streaming-playback-design.md

## Baseline

- HEAD at start: `3c9659dd` (plan/spec precision commit).
- Plan/spec commits: `a8636743`, `3c9659dd`.
- Seed: v102 archive `702f34d87b7e6bf401dd206d2517dbee`, fixed point `b299b4b435e624d0ddbd2edde681cbc3`.
- Defects: D1/D2 FIXED, D3/D4/D5 OPEN.
- Known failing operator artifact: `lin_bin/01. 霜月はるか — ユメノハテニ.ogg` 8,205,755 B; old UI `FILE_ARENA_SIZE=4 MiB` + `readAll` → “cannot open track”.
- Untracked at start: `lin_bin/`, `run.err`.

## Task status

- T0 preflight: complete (commit `e696392c`; review APPROVE 0C/0I/4 Minor; read-only; seed probe >4MiB OK; max committed OGG page 4,222 B, packet 3,832 B; tiers/pins match). Review truth-ups in `16655f0e`.
- T1 stream.zig: next.
