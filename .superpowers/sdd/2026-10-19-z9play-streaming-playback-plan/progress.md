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
- T1 stream.zig: complete (commits `ecf2bcdd`, `e312c886`; review APPROVE 0C/0I/4 Minor; 64K buffer, >4MiB test PASS, arena_used=65536).
- T2 ogg_stream.zig: complete (commits `dc11bc88`, `968fcc12`; review APPROVE 0C/0I/3 Minor; 5 fixtures packet-identical, 8 synthetic cases, page-local offsets, tail bounded).
- T3 FLAC streaming: complete (commits `ad3d7313`, `a9dc1ecc`; review APPROVE 0C/0I/4 Minor; oracle max_delta=0, tier_flac 59/0, minimal FLAC frontend switch authorized).
- T4 Vorbis + main modes: complete (commits `4d88f4d2`, `1211759c`; fix round 1 `688b5c9d`, `45a112a9`; review APPROVE after C1 scratch-arena fix + I1 exact `--pcm` pin; tiers green).
- T5 ui.zig streaming TUI: next.
