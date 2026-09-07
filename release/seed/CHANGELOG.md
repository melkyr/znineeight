# Seed Rotation Changelog

Provenance + rotation history for the committed zig1 bootstrap seed
(`release/seed/zig1-seed.tgz`). Rotation tracking is per-seed (dedicated file,
NOT the release-versioned root `CHANGELOG.md`). Newest entry first. The seed
replaces zig0 as the ultimate authority for rebuilding zig1: it can be rebuilt
from source with only `gcc` (see spec
`docs/superpowers/specs/2026-09-07-seed-bootstrap-migration-design.md`).

Each completed plan that moves the self-emission fixed point rotates the seed
(new zig1 binary + new self-emission C), overwriting the archive and appending
a provenance entry here. Prior seeds remain recoverable in git history.

## 2026-09-07 — seed v0 (HEAD 1079d90a)

First capture (SEEDMIG, Phase 0). Archive layout: top-level dir `zig1-seed/`
with `zig1`, `gen/` (41 `.c` + 42 `.h` incl. emitted `zig_special_types.h`),
`c_exit.c` (top level), `runtime/`, `lib/`, `SEED_README.txt`.

| field | value |
|---|---|
| date | 2026-09-07 |
| HEAD | `1079d90a` (branch `zig1_improvements`) |
| seed binary md5 | `3707d33bd1d3779c4a98aab9d5be1841` (zig0-built reference) |
| self-emission C | 41 `.c` + 42 `.h` (8,026,653 bytes) |
| fixed point | `24da89b9d6398ff24f4baecfe2e23f77` |
| archive md5 | `ee7a42a87ff697f3351317c95cf3d582` |
| rotation basis | zig0-built reference; infra migration (zig0-independent rebuild path) |

Provenance note: the archived binary is **zig0-built** (md5 `3707d33b…`, the
reference compiler valid at HEAD), while gcc of the archive's self-emission C
reproduces the **self-emission fixed point** `24da89b9…` — both are the same
compiler state at HEAD `1079d90a`. Rebuild recipes + full canonical flag-set
requirement (`gcc -m32 -std=c89 -O0 -Wall -Wno-long-long -Wno-pointer-sign
-Wno-implicit-function-declaration`; the `24da89b9…` fixed point reproduces
ONLY with `-Wall` present) are recorded in `zig1-seed/SEED_README.txt`.
