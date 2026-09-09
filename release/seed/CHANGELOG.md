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

## 2026-09-09 — seed v6 (HEAD 4bdf52da)

Seed rotation via scripts/seed/archive_seed.sh. Archive layout: top-level dir
`zig1-seed/` with `zig1`, `gen/` (42 `.c` + 43 `.h` incl.
emitted `zig_special_types.h`, 7098142 bytes), `c_exit.c` (top level),
`runtime/`, `lib/`, `SEED_README.txt`.

| field | value |
|---|---|
| date | 2026-09-09 |
| HEAD | `4bdf52da` |
| seed binary md5 | `ea149e05617cda366a279d273902fcb2` |
| self-emission C | 42 `.c` + 43 `.h` (7098142 bytes) |
| fixed point | `ea149e05617cda366a279d273902fcb2` |
| archive md5 | `84d738b4fc8096c8a32fbf69544bbf79` |

Provenance note: the archived binary (md5 ea149e05617cda366a279d273902fcb2) was captured by
scripts/seed/archive_seed.sh at HEAD 4bdf52da; gcc of the archive's self-emission
C reproduces the self-emission fixed point `ea149e05617cda366a279d273902fcb2` — both are the same
compiler state at HEAD 4bdf52da. Rebuild recipes + full canonical flag-set
requirement (`gcc -m32 -std=c89 -O0 -Wall -Wno-long-long -Wno-pointer-sign
-Wno-implicit-function-declaration`; the fixed point reproduces ONLY with
`-Wall` present) are recorded in `zig1-seed/SEED_README.txt`.
## 2026-09-09 — seed v5 (HEAD e62ebd99)

Seed rotation via scripts/seed/archive_seed.sh. Archive layout: top-level dir
`zig1-seed/` with `zig1`, `gen/` (42 `.c` + 43 `.h` incl.
emitted `zig_special_types.h`, 8202959 bytes), `c_exit.c` (top level),
`runtime/`, `lib/`, `SEED_README.txt`.

| field | value |
|---|---|
| date | 2026-09-09 |
| HEAD | `e62ebd99` |
| seed binary md5 | `048824c92d7c270d43d5d4d7db39372e` |
| self-emission C | 42 `.c` + 43 `.h` (8202959 bytes) |
| fixed point | `048824c92d7c270d43d5d4d7db39372e` |
| archive md5 | `6f7c0cf573a2fdd9e1ab20c734de0b38` |

Provenance note: the archived binary (md5 048824c92d7c270d43d5d4d7db39372e) was captured by
scripts/seed/archive_seed.sh at HEAD e62ebd99; gcc of the archive's self-emission
C reproduces the self-emission fixed point `048824c92d7c270d43d5d4d7db39372e` — both are the same
compiler state at HEAD e62ebd99. Rebuild recipes + full canonical flag-set
requirement (`gcc -m32 -std=c89 -O0 -Wall -Wno-long-long -Wno-pointer-sign
-Wno-implicit-function-declaration`; the fixed point reproduces ONLY with
`-Wall` present) are recorded in `zig1-seed/SEED_README.txt`.

**LIROPTPASS emission-tightening re-baseline (operator ruling 2026-09-09):** seed v5 is the
**official post-LIROPTPASS self-hosted fixed point `048824c9`**. The dedicated pre-emission LIR opt
pass (`sf/src/lir_opt_pass.zig`, dead-temp/copy-prop/local const-fold + pure-chain expression
nesting with backend-agnostic pass metadata, T3-T4e landing `8c6a8e9c`..`e62ebd99`) changed the
compiler's own emission (self-emission 42 `.c` + 43 `.h` = 8,202,959 B incl. the new
`lir_opt_pass` module; 41-original-module set 8,334,141→7,974,157 B = −359,984 B/−4.3%); the N-hop
chain at HEAD `e62ebd99` converged seed v4 `f5c2f9d2` → hop1 `ae525bdc` → hop2 `048824c9` → hop3
`048824c9` (hop2==hop3 == this seed's fixed point). Runtime byte-identity held across the full Task-5
battery (24/24 run-identical, corpus 419/419 zero class change, upgraded goldens + net 12/12,
mingw32 `-osw` clean). The 4-MD5 dump gates were re-baselined (runtime-identical) to the values
recorded at this HEAD's docs GATE.
## 2026-09-08 — seed v4 (HEAD 890302c6)

Seed rotation via scripts/seed/archive_seed.sh. Archive layout: top-level dir
`zig1-seed/` with `zig1`, `gen/` (41 `.c` + 42 `.h` incl.
emitted `zig_special_types.h`, 8334141 bytes), `c_exit.c` (top level),
`runtime/`, `lib/`, `SEED_README.txt`.

| field | value |
|---|---|
| date | 2026-09-08 |
| HEAD | `890302c6` |
| seed binary md5 | `f5c2f9d27d613c6582ab3e79d6fec437` |
| self-emission C | 41 `.c` + 42 `.h` (8334141 bytes) |
| fixed point | `f5c2f9d27d613c6582ab3e79d6fec437` |
| archive md5 | `a8b97b3cfa9a781f5c39daf896debb38` |

Provenance note: the archived binary (md5 f5c2f9d27d613c6582ab3e79d6fec437) was captured by
scripts/seed/archive_seed.sh at HEAD 890302c6; gcc of the archive's self-emission
C reproduces the self-emission fixed point `f5c2f9d27d613c6582ab3e79d6fec437` — both are the same
compiler state at HEAD 890302c6. Rebuild recipes + full canonical flag-set
requirement (`gcc -m32 -std=c89 -O0 -Wall -Wno-long-long -Wno-pointer-sign
-Wno-implicit-function-declaration`; the fixed point reproduces ONLY with
`-Wall` present) are recorded in `zig1-seed/SEED_README.txt`.

**zig0-retirement / official-self-hosted milestone annotation (operator ruling 2026-09-08):** seed
v4 is the **official self-hosted / zig0-retirement milestone**. `enum(uN)` (the PACK-B3 plan) is the
first syntax zig0's frozen C++ front end cannot parse — `sf/src` is no longer zig0-compilable, and
the `sf/scripts/build_release.sh` zig0 path is dead for the current `sf/src` (kept in-tree,
historical). From this seed onward the reference compiler is built **from the committed seed**
(`zig1 → zig1_5`, N-hop stabilization: seed `e20bfb70` → hop1 `1e96b989` → hop2 `f5c2f9d2` → hop3
`f5c2f9d2`, hop2==hop3 == this seed's fixed point), never zig0.
## 2026-09-08 — seed v3 (HEAD 9bc2c751)

Seed rotation via scripts/seed/archive_seed.sh. Archive layout: top-level dir
`zig1-seed/` with `zig1`, `gen/` (41 `.c` + 42 `.h` incl.
emitted `zig_special_types.h`, 8291075 bytes), `c_exit.c` (top level),
`runtime/`, `lib/`, `SEED_README.txt`.

| field | value |
|---|---|
| date | 2026-09-08 |
| HEAD | `9bc2c751` |
| seed binary md5 | `e20bfb7072ea10167476d8f94a9d391d` |
| self-emission C | 41 `.c` + 42 `.h` (8291075 bytes) |
| fixed point | `e20bfb7072ea10167476d8f94a9d391d` |
| archive md5 | `31a94d6f5f9ed3dddb279e8c55324a9c` |

Provenance note: the archived binary (md5 e20bfb7072ea10167476d8f94a9d391d) was captured by
scripts/seed/archive_seed.sh at HEAD 9bc2c751; gcc of the archive's self-emission
C reproduces the self-emission fixed point `e20bfb7072ea10167476d8f94a9d391d` — both are the same
compiler state at HEAD 9bc2c751. Rebuild recipes + full canonical flag-set
requirement (`gcc -m32 -std=c89 -O0 -Wall -Wno-long-long -Wno-pointer-sign
-Wno-implicit-function-declaration`; the fixed point reproduces ONLY with
`-Wall` present) are recorded in `zig1-seed/SEED_README.txt`.
## 2026-09-08 — seed v2 (HEAD f1259e65)

Seed rotation via scripts/seed/archive_seed.sh. Archive layout: top-level dir
`zig1-seed/` with `zig1`, `gen/` (41 `.c` + 42 `.h` incl.
emitted `zig_special_types.h`, 8277285 bytes), `c_exit.c` (top level),
`runtime/`, `lib/`, `SEED_README.txt`.

| field | value |
|---|---|
| date | 2026-09-08 |
| HEAD | `f1259e65` |
| seed binary md5 | `7e23d33d77926c71999daf602e3d96b6` |
| self-emission C | 41 `.c` + 42 `.h` (8277285 bytes) |
| fixed point | `7e23d33d77926c71999daf602e3d96b6` |
| archive md5 | `3ba6a4cdbdca20338eaed16f16ef3318` |

Provenance note: the archived binary (md5 7e23d33d77926c71999daf602e3d96b6) was captured by
scripts/seed/archive_seed.sh at HEAD f1259e65; gcc of the archive's self-emission
C reproduces the self-emission fixed point `7e23d33d77926c71999daf602e3d96b6` — both are the same
compiler state at HEAD f1259e65. Rebuild recipes + full canonical flag-set
requirement (`gcc -m32 -std=c89 -O0 -Wall -Wno-long-long -Wno-pointer-sign
-Wno-implicit-function-declaration`; the fixed point reproduces ONLY with
`-Wall` present) are recorded in `zig1-seed/SEED_README.txt`.
## 2026-09-07 — seed v1 (HEAD c7af022a)

Seed rotation via scripts/seed/archive_seed.sh. Archive layout: top-level dir
`zig1-seed/` with `zig1`, `gen/` (41 `.c` + 42 `.h` incl.
emitted `zig_special_types.h`, 8164820 bytes), `c_exit.c` (top level),
`runtime/`, `lib/`, `SEED_README.txt`.

| field | value |
|---|---|
| date | 2026-09-07 |
| HEAD | `c7af022a` |
| seed binary md5 | `fd3e1c0e1787be22e2b2bc09e9916e4c` |
| self-emission C | 41 `.c` + 42 `.h` (8164820 bytes) |
| fixed point | `fd3e1c0e1787be22e2b2bc09e9916e4c` |
| archive md5 | `033a3018c0190b95963885eccd6c7006` |

Provenance note: the archived binary (md5 fd3e1c0e1787be22e2b2bc09e9916e4c) was captured by
scripts/seed/archive_seed.sh at HEAD c7af022a; gcc of the archive's self-emission
C reproduces the self-emission fixed point `fd3e1c0e1787be22e2b2bc09e9916e4c` — both are the same
compiler state at HEAD c7af022a. Rebuild recipes + full canonical flag-set
requirement (`gcc -m32 -std=c89 -O0 -Wall -Wno-long-long -Wno-pointer-sign
-Wno-implicit-function-declaration`; the fixed point reproduces ONLY with
`-Wall` present) are recorded in `zig1-seed/SEED_README.txt`.
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
