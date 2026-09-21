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

## 2026-09-21 — seed v61 (HEAD fd31f7f3)

Seed rotation via scripts/seed/archive_seed.sh. Archive layout: top-level dir
`zig1-seed/` with `zig1`, `gen/` (45 `.c` + 46 `.h` incl.
emitted `zig_special_types.h`, 9103688 bytes), `c_exit.c` (top level),
`runtime/`, `lib/`, `SEED_README.txt`.

| field | value |
|---|---|
| date | 2026-09-21 |
| HEAD | `fd31f7f3` |
| seed binary md5 | `31f61d870ee93f97bb0e01cc76c629cd` |
| self-emission C | 45 `.c` + 46 `.h` (9103688 bytes) |
| fixed point | `31f61d870ee93f97bb0e01cc76c629cd` |
| archive md5 | `ab1cc2c0520fe8391c88e9685e6602a1` |

Provenance note: the archived binary (md5 31f61d870ee93f97bb0e01cc76c629cd) was captured by
scripts/seed/archive_seed.sh at HEAD fd31f7f3; gcc of the archive's self-emission
C reproduces the self-emission fixed point `31f61d870ee93f97bb0e01cc76c629cd` — both are the same
compiler state at HEAD fd31f7f3. The compiler self-build uses `-ffast` (user
programs default to `-fsafe`), so the recorded fixed point is the `-ffast`
binary. Rebuild recipes + full canonical flag-set requirement (`gcc -m32
-std=c89 -O0 -Wall -Wno-long-long -Wno-pointer-sign
-Wno-implicit-function-declaration`; the fixed point reproduces ONLY with
`-Wall` present) are recorded in `zig1-seed/SEED_README.txt`.

## 2026-09-21 — seed v60 (HEAD 29ea1c1b)

Seed rotation via scripts/seed/archive_seed.sh. Archive layout: top-level dir
`zig1-seed/` with `zig1`, `gen/` (45 `.c` + 46 `.h` incl.
emitted `zig_special_types.h`, 9081218 bytes), `c_exit.c` (top level),
`runtime/`, `lib/`, `SEED_README.txt`.

| field | value |
|---|---|
| date | 2026-09-21 |
| HEAD | `29ea1c1b` |
| seed binary md5 | `603d835a31d3a8c051f75cc608c477c4` |
| self-emission C | 45 `.c` + 46 `.h` (9081218 bytes) |
| fixed point | `603d835a31d3a8c051f75cc608c477c4` |
| archive md5 | `04d3f6784a41a30f27a7e27778d5ff4e` |

Provenance note: the archived binary (md5 603d835a31d3a8c051f75cc608c477c4) was captured by
scripts/seed/archive_seed.sh at HEAD 29ea1c1b; gcc of the archive's self-emission
C reproduces the self-emission fixed point `603d835a31d3a8c051f75cc608c477c4` — both are the same
compiler state at HEAD 29ea1c1b. The compiler self-build uses `-ffast` (user
programs default to `-fsafe`), so the recorded fixed point is the `-ffast`
binary. Rebuild recipes + full canonical flag-set requirement (`gcc -m32
-std=c89 -O0 -Wall -Wno-long-long -Wno-pointer-sign
-Wno-implicit-function-declaration`; the fixed point reproduces ONLY with
`-Wall` present) are recorded in `zig1-seed/SEED_README.txt`.
## 2026-09-21 — seed v59 (HEAD 1903427e)

Seed rotation via scripts/seed/archive_seed.sh. Archive layout: top-level dir
`zig1-seed/` with `zig1`, `gen/` (45 `.c` + 46 `.h` incl.
emitted `zig_special_types.h`, 9079934 bytes), `c_exit.c` (top level),
`runtime/`, `lib/`, `SEED_README.txt`.

| field | value |
|---|---|
| date | 2026-09-21 |
| HEAD | `1903427e` |
| seed binary md5 | `af757cca4c6ca77f2197e1e39d8cd818` |
| self-emission C | 45 `.c` + 46 `.h` (9079934 bytes) |
| fixed point | `af757cca4c6ca77f2197e1e39d8cd818` |
| archive md5 | `8821a2010b4fc149d9c45d969f971de0` |

Provenance note: the archived binary (md5 af757cca4c6ca77f2197e1e39d8cd818) was captured by
scripts/seed/archive_seed.sh at HEAD 1903427e; gcc of the archive's self-emission
C reproduces the self-emission fixed point `af757cca4c6ca77f2197e1e39d8cd818` — both are the same
compiler state at HEAD 1903427e. The compiler self-build uses `-ffast` (user
programs default to `-fsafe`), so the recorded fixed point is the `-ffast`
binary. Rebuild recipes + full canonical flag-set requirement (`gcc -m32
-std=c89 -O0 -Wall -Wno-long-long -Wno-pointer-sign
-Wno-implicit-function-declaration`; the fixed point reproduces ONLY with
`-Wall` present) are recorded in `zig1-seed/SEED_README.txt`.
## 2026-09-21 — seed v58 (HEAD 1c04ec3a)

Seed rotation via scripts/seed/archive_seed.sh. Archive layout: top-level dir
`zig1-seed/` with `zig1`, `gen/` (45 `.c` + 46 `.h` incl.
emitted `zig_special_types.h`, 9044762 bytes), `c_exit.c` (top level),
`runtime/`, `lib/`, `SEED_README.txt`.

| field | value |
|---|---|
| date | 2026-09-21 |
| HEAD | `1c04ec3a` |
| seed binary md5 | `81339077a8d0bbec3e02bd914c3b33d1` |
| self-emission C | 45 `.c` + 46 `.h` (9044762 bytes) |
| fixed point | `81339077a8d0bbec3e02bd914c3b33d1` |
| archive md5 | `d9059d3573654ddc477034d2e986463f` |

Provenance note: the archived binary (md5 81339077a8d0bbec3e02bd914c3b33d1) was captured by
scripts/seed/archive_seed.sh at HEAD 1c04ec3a; gcc of the archive's self-emission
C reproduces the self-emission fixed point `81339077a8d0bbec3e02bd914c3b33d1` — both are the same
compiler state at HEAD 1c04ec3a. The compiler self-build uses `-ffast` (user
programs default to `-fsafe`), so the recorded fixed point is the `-ffast`
binary. Rebuild recipes + full canonical flag-set requirement (`gcc -m32
-std=c89 -O0 -Wall -Wno-long-long -Wno-pointer-sign
-Wno-implicit-function-declaration`; the fixed point reproduces ONLY with
`-Wall` present) are recorded in `zig1-seed/SEED_README.txt`.
## 2026-09-21 — seed v57 (HEAD d8f6ef32)

Seed rotation via scripts/seed/archive_seed.sh. Archive layout: top-level dir
`zig1-seed/` with `zig1`, `gen/` (45 `.c` + 46 `.h` incl.
emitted `zig_special_types.h`, 9043243 bytes), `c_exit.c` (top level),
`runtime/`, `lib/`, `SEED_README.txt`.

| field | value |
|---|---|
| date | 2026-09-21 |
| HEAD | `d8f6ef32` |
| seed binary md5 | `5106cc8709c026c60eea113677a3fa5d` |
| self-emission C | 45 `.c` + 46 `.h` (9043243 bytes) |
| fixed point | `5106cc8709c026c60eea113677a3fa5d` |
| archive md5 | `60c9ac10bd4382b6a25d7ef64daf2191` |

Provenance note: the archived binary (md5 5106cc8709c026c60eea113677a3fa5d) was captured by
scripts/seed/archive_seed.sh at HEAD d8f6ef32; gcc of the archive's self-emission
C reproduces the self-emission fixed point `5106cc8709c026c60eea113677a3fa5d` — both are the same
compiler state at HEAD d8f6ef32. The compiler self-build uses `-ffast` (user
programs default to `-fsafe`), so the recorded fixed point is the `-ffast`
binary. Rebuild recipes + full canonical flag-set requirement (`gcc -m32
-std=c89 -O0 -Wall -Wno-long-long -Wno-pointer-sign
-Wno-implicit-function-declaration`; the fixed point reproduces ONLY with
`-Wall` present) are recorded in `zig1-seed/SEED_README.txt`.
## 2026-09-21 — seed v56 (HEAD d23c6a91)

Seed rotation via scripts/seed/archive_seed.sh. Archive layout: top-level dir
`zig1-seed/` with `zig1`, `gen/` (45 `.c` + 46 `.h` incl.
emitted `zig_special_types.h`, 9033298 bytes), `c_exit.c` (top level),
`runtime/`, `lib/`, `SEED_README.txt`.

| field | value |
|---|---|
| date | 2026-09-21 |
| HEAD | `d23c6a91` |
| seed binary md5 | `13434b4f4d5e5172b5a2422d5b6e043c` |
| self-emission C | 45 `.c` + 46 `.h` (9033298 bytes) |
| fixed point | `13434b4f4d5e5172b5a2422d5b6e043c` |
| archive md5 | `8073b3f3fef42d772cd58d19fd09ef2b` |

Provenance note: the archived binary (md5 13434b4f4d5e5172b5a2422d5b6e043c) was captured by
scripts/seed/archive_seed.sh at HEAD d23c6a91; gcc of the archive's self-emission
C reproduces the self-emission fixed point `13434b4f4d5e5172b5a2422d5b6e043c` — both are the same
compiler state at HEAD d23c6a91. The compiler self-build uses `-ffast` (user
programs default to `-fsafe`), so the recorded fixed point is the `-ffast`
binary. Rebuild recipes + full canonical flag-set requirement (`gcc -m32
-std=c89 -O0 -Wall -Wno-long-long -Wno-pointer-sign
-Wno-implicit-function-declaration`; the fixed point reproduces ONLY with
`-Wall` present) are recorded in `zig1-seed/SEED_README.txt`.
## 2026-09-21 — seed v55 (HEAD 69d43f6f)

Seed rotation via scripts/seed/archive_seed.sh. Archive layout: top-level dir
`zig1-seed/` with `zig1`, `gen/` (45 `.c` + 46 `.h` incl.
emitted `zig_special_types.h`, 9022401 bytes), `c_exit.c` (top level),
`runtime/`, `lib/`, `SEED_README.txt`.

| field | value |
|---|---|
| date | 2026-09-21 |
| HEAD | `69d43f6f` |
| seed binary md5 | `618a011508fdbed44b02dba3dd26624f` |
| self-emission C | 45 `.c` + 46 `.h` (9022401 bytes) |
| fixed point | `618a011508fdbed44b02dba3dd26624f` |
| archive md5 | `e52afcc9d52e763158d5c8e149c287ea` |

Provenance note: the archived binary (md5 618a011508fdbed44b02dba3dd26624f) was captured by
scripts/seed/archive_seed.sh at HEAD 69d43f6f; gcc of the archive's self-emission
C reproduces the self-emission fixed point `618a011508fdbed44b02dba3dd26624f` — both are the same
compiler state at HEAD 69d43f6f. The compiler self-build uses `-ffast` (user
programs default to `-fsafe`), so the recorded fixed point is the `-ffast`
binary. Rebuild recipes + full canonical flag-set requirement (`gcc -m32
-std=c89 -O0 -Wall -Wno-long-long -Wno-pointer-sign
-Wno-implicit-function-declaration`; the fixed point reproduces ONLY with
`-Wall` present) are recorded in `zig1-seed/SEED_README.txt`.
## 2026-09-21 — seed v54 (HEAD d3681f4c)

Seed rotation via scripts/seed/archive_seed.sh. Archive layout: top-level dir
`zig1-seed/` with `zig1`, `gen/` (45 `.c` + 46 `.h` incl.
emitted `zig_special_types.h`, 8972440 bytes), `c_exit.c` (top level),
`runtime/`, `lib/`, `SEED_README.txt`.

| field | value |
|---|---|
| date | 2026-09-21 |
| HEAD | `d3681f4c` |
| seed binary md5 | `cf76c6f13bca6cfce2a4b810af2a67e9` |
| self-emission C | 45 `.c` + 46 `.h` (8972440 bytes) |
| fixed point | `cf76c6f13bca6cfce2a4b810af2a67e9` |
| archive md5 | `fa3437ce2cba0f30dc37338c45524eea` |

Provenance note: the archived binary (md5 cf76c6f13bca6cfce2a4b810af2a67e9) was captured by
scripts/seed/archive_seed.sh at HEAD d3681f4c; gcc of the archive's self-emission
C reproduces the self-emission fixed point `cf76c6f13bca6cfce2a4b810af2a67e9` — both are the same
compiler state at HEAD d3681f4c. The compiler self-build uses `-ffast` (user
programs default to `-fsafe`), so the recorded fixed point is the `-ffast`
binary. Rebuild recipes + full canonical flag-set requirement (`gcc -m32
-std=c89 -O0 -Wall -Wno-long-long -Wno-pointer-sign
-Wno-implicit-function-declaration`; the fixed point reproduces ONLY with
`-Wall` present) are recorded in `zig1-seed/SEED_README.txt`.
## 2026-09-21 — seed v53 (HEAD 4f0a280e)

Seed rotation via scripts/seed/archive_seed.sh. Archive layout: top-level dir
`zig1-seed/` with `zig1`, `gen/` (45 `.c` + 46 `.h` incl.
emitted `zig_special_types.h`, 8958518 bytes), `c_exit.c` (top level),
`runtime/`, `lib/`, `SEED_README.txt`.

| field | value |
|---|---|
| date | 2026-09-21 |
| HEAD | `4f0a280e` |
| seed binary md5 | `6ed66e8d0d0ba862f014baf76be17a86` |
| self-emission C | 45 `.c` + 46 `.h` (8958518 bytes) |
| fixed point | `6ed66e8d0d0ba862f014baf76be17a86` |
| archive md5 | `ba0f5208a832b8357fb8c51be8e22067` |

Provenance note: the archived binary (md5 6ed66e8d0d0ba862f014baf76be17a86) was captured by
scripts/seed/archive_seed.sh at HEAD 4f0a280e; gcc of the archive's self-emission
C reproduces the self-emission fixed point `6ed66e8d0d0ba862f014baf76be17a86` — both are the same
compiler state at HEAD 4f0a280e. The compiler self-build uses `-ffast` (user
programs default to `-fsafe`), so the recorded fixed point is the `-ffast`
binary. Rebuild recipes + full canonical flag-set requirement (`gcc -m32
-std=c89 -O0 -Wall -Wno-long-long -Wno-pointer-sign
-Wno-implicit-function-declaration`; the fixed point reproduces ONLY with
`-Wall` present) are recorded in `zig1-seed/SEED_README.txt`.

## 2026-09-21 — seed v52 (HEAD e70973a4)

Seed rotation via scripts/seed/archive_seed.sh. Archive layout: top-level dir
`zig1-seed/` with `zig1`, `gen/` (45 `.c` + 46 `.h` incl.
emitted `zig_special_types.h`, 8957827 bytes), `c_exit.c` (top level),
`runtime/`, `lib/`, `SEED_README.txt`.

| field | value |
|---|---|
| date | 2026-09-21 |
| HEAD | `e70973a4` |
| seed binary md5 | `0080736e9637b6993e7539f755f351ea` |
| self-emission C | 45 `.c` + 46 `.h` (8957827 bytes) |
| fixed point | `0080736e9637b6993e7539f755f351ea` |
| archive md5 | `b47270f17c7725d02bb0ab405dbe3377` |

Provenance note: the archived binary (md5 0080736e9637b6993e7539f755f351ea) was captured by
scripts/seed/archive_seed.sh at HEAD e70973a4; gcc of the archive's self-emission
C reproduces the self-emission fixed point `0080736e9637b6993e7539f755f351ea` — both are the same
compiler state at HEAD e70973a4. The compiler self-build uses `-ffast` (user
programs default to `-fsafe`), so the recorded fixed point is the `-ffast`
binary. Rebuild recipes + full canonical flag-set requirement (`gcc -m32
-std=c89 -O0 -Wall -Wno-long-long -Wno-pointer-sign
-Wno-implicit-function-declaration`; the fixed point reproduces ONLY with
`-Wall` present) are recorded in `zig1-seed/SEED_README.txt`.
## 2026-09-21 — seed v51 (HEAD 68cb4a65)

Seed rotation via scripts/seed/archive_seed.sh. Archive layout: top-level dir
`zig1-seed/` with `zig1`, `gen/` (45 `.c` + 46 `.h` incl.
emitted `zig_special_types.h`, 8957475 bytes), `c_exit.c` (top level),
`runtime/`, `lib/`, `SEED_README.txt`.

| field | value |
|---|---|
| date | 2026-09-21 |
| HEAD | `68cb4a65` |
| seed binary md5 | `6cbb52440c2e91e33f735e4e09368fd5` |
| self-emission C | 45 `.c` + 46 `.h` (8957475 bytes) |
| fixed point | `6cbb52440c2e91e33f735e4e09368fd5` |
| archive md5 | `55694207eaf1f29a98400eb7364bb5d9` |

Provenance note: the archived binary (md5 6cbb52440c2e91e33f735e4e09368fd5) was captured by
scripts/seed/archive_seed.sh at HEAD 68cb4a65; gcc of the archive's self-emission
C reproduces the self-emission fixed point `6cbb52440c2e91e33f735e4e09368fd5` — both are the same
compiler state at HEAD 68cb4a65. The compiler self-build uses `-ffast` (user
programs default to `-fsafe`), so the recorded fixed point is the `-ffast`
binary. Rebuild recipes + full canonical flag-set requirement (`gcc -m32
-std=c89 -O0 -Wall -Wno-long-long -Wno-pointer-sign
-Wno-implicit-function-declaration`; the fixed point reproduces ONLY with
`-Wall` present) are recorded in `zig1-seed/SEED_README.txt`.
## 2026-09-21 — seed v50 (HEAD af6c7e02)

Seed rotation via scripts/seed/archive_seed.sh. Archive layout: top-level dir
`zig1-seed/` with `zig1`, `gen/` (45 `.c` + 46 `.h` incl.
emitted `zig_special_types.h`, 8946787 bytes), `c_exit.c` (top level),
`runtime/`, `lib/`, `SEED_README.txt`.

| field | value |
|---|---|
| date | 2026-09-21 |
| HEAD | `af6c7e02` |
| seed binary md5 | `5dd7874d7a69e015f63874abc30b3222` |
| self-emission C | 45 `.c` + 46 `.h` (8946787 bytes) |
| fixed point | `5dd7874d7a69e015f63874abc30b3222` |
| archive md5 | `a9f303cac8f3710fa51ea475b51bfec9` |

Provenance note: the archived binary (md5 5dd7874d7a69e015f63874abc30b3222) was captured by
scripts/seed/archive_seed.sh at HEAD af6c7e02; gcc of the archive's self-emission
C reproduces the self-emission fixed point `5dd7874d7a69e015f63874abc30b3222` — both are the same
compiler state at HEAD af6c7e02. The compiler self-build uses `-ffast` (user
programs default to `-fsafe`), so the recorded fixed point is the `-ffast`
binary. Rebuild recipes + full canonical flag-set requirement (`gcc -m32
-std=c89 -O0 -Wall -Wno-long-long -Wno-pointer-sign
-Wno-implicit-function-declaration`; the fixed point reproduces ONLY with
`-Wall` present) are recorded in `zig1-seed/SEED_README.txt`.
## 2026-09-21 — seed v49 (HEAD 608cf4f6)

Seed rotation via scripts/seed/archive_seed.sh. Archive layout: top-level dir
`zig1-seed/` with `zig1`, `gen/` (45 `.c` + 46 `.h` incl.
emitted `zig_special_types.h`, 8850177 bytes), `c_exit.c` (top level),
`runtime/`, `lib/`, `SEED_README.txt`.

| field | value |
|---|---|
| date | 2026-09-21 |
| HEAD | `608cf4f6` |
| seed binary md5 | `9b292edf64686968c69e0b15f7da762d` |
| self-emission C | 45 `.c` + 46 `.h` (8850177 bytes) |
| fixed point | `9b292edf64686968c69e0b15f7da762d` |
| archive md5 | `77cff5d2cb032526e2cad6e0a4b38b1a` |

Provenance note: the archived binary (md5 9b292edf64686968c69e0b15f7da762d) was captured by
scripts/seed/archive_seed.sh at HEAD 608cf4f6; gcc of the archive's self-emission
C reproduces the self-emission fixed point `9b292edf64686968c69e0b15f7da762d` — both are the same
compiler state at HEAD 608cf4f6. The compiler self-build uses `-ffast` (user
programs default to `-fsafe`), so the recorded fixed point is the `-ffast`
binary. Rebuild recipes + full canonical flag-set requirement (`gcc -m32
-std=c89 -O0 -Wall -Wno-long-long -Wno-pointer-sign
-Wno-implicit-function-declaration`; the fixed point reproduces ONLY with
`-Wall` present) are recorded in `zig1-seed/SEED_README.txt`.
## 2026-09-21 — seed v48 (HEAD a657ae62)

Seed rotation via scripts/seed/archive_seed.sh. Archive layout: top-level dir
`zig1-seed/` with `zig1`, `gen/` (45 `.c` + 46 `.h` incl.
emitted `zig_special_types.h`, 8840074 bytes), `c_exit.c` (top level),
`runtime/`, `lib/`, `SEED_README.txt`.

| field | value |
|---|---|
| date | 2026-09-21 |
| HEAD | `a657ae62` (rotation-time; fix commit immediately following) |
| seed binary md5 | `0b717b37c412ce5cd6abd87eeb6a36d8` |
| self-emission C | 45 `.c` + 46 `.h` (8840074 bytes) |
| fixed point | `0b717b37c412ce5cd6abd87eeb6a36d8` |
| archive md5 | `e30fbafb93b1253ad007c536883030b6` |

Provenance note: the archived binary (md5 0b717b37c412ce5cd6abd87eeb6a36d8) was captured by
scripts/seed/archive_seed.sh; the script's rotation-time HEAD was `a657ae62`, the parent of the
Task 11D fix-round-2 commit whose tree the archived compiler was built from. gcc of the archive's self-emission
C reproduces the self-emission fixed point `0b717b37c412ce5cd6abd87eeb6a36d8` — both are the same
compiler state as that fix commit. The compiler self-build uses `-ffast` (user
programs default to `-fsafe`), so the recorded fixed point is the `-ffast`
binary. Rebuild recipes + full canonical flag-set requirement (`gcc -m32
-std=c89 -O0 -Wall -Wno-long-long -Wno-pointer-sign
-Wno-implicit-function-declaration`; the fixed point reproduces ONLY with
`-Wall` present) are recorded in `zig1-seed/SEED_README.txt`.
## 2026-09-21 — seed v47 (HEAD c21f1ff0)

Seed rotation via scripts/seed/archive_seed.sh. Archive layout: top-level dir
`zig1-seed/` with `zig1`, `gen/` (45 `.c` + 46 `.h` incl.
emitted `zig_special_types.h`, 8839028 bytes), `c_exit.c` (top level),
`runtime/`, `lib/`, `SEED_README.txt`.

| field | value |
|---|---|
| date | 2026-09-21 |
| HEAD | `c21f1ff0` (rotation-time; fix commit `a657ae62`) |
| seed binary md5 | `109628afa625baca56c2d4b340a802b0` |
| self-emission C | 45 `.c` + 46 `.h` (8839028 bytes) |
| fixed point | `109628afa625baca56c2d4b340a802b0` |
| archive md5 | `cccc81768445f05b68bea8d3bb780961` |

Provenance note: the archived binary (md5 109628afa625baca56c2d4b340a802b0) was captured by
scripts/seed/archive_seed.sh; the script's rotation-time HEAD was `c21f1ff0`, the parent of the
Task 11D fix-round-1 commit `a657ae62` whose tree the archived compiler was built from. gcc of the
archive's self-emission C reproduces the self-emission fixed point `109628afa625baca56c2d4b340a802b0` — both are the same
compiler state as commit `a657ae62`. The compiler self-build uses `-ffast` (user
programs default to `-fsafe`), so the recorded fixed point is the `-ffast`
binary. Rebuild recipes + full canonical flag-set requirement (`gcc -m32
-std=c89 -O0 -Wall -Wno-long-long -Wno-pointer-sign
-Wno-implicit-function-declaration`; the fixed point reproduces ONLY with
`-Wall` present) are recorded in `zig1-seed/SEED_README.txt`.
## 2026-09-20 — seed v46 (HEAD cc955a69)

Seed rotation via scripts/seed/archive_seed.sh. Archive layout: top-level dir
`zig1-seed/` with `zig1`, `gen/` (45 `.c` + 46 `.h` incl.
emitted `zig_special_types.h`, 8832048 bytes), `c_exit.c` (top level),
`runtime/`, `lib/`, `SEED_README.txt`.

| field | value |
|---|---|
| date | 2026-09-20 |
| HEAD | `cc955a69` |
| seed binary md5 | `ea159fc2f14af88b3d450f3ca70eca17` |
| self-emission C | 45 `.c` + 46 `.h` (8832048 bytes) |
| fixed point | `ea159fc2f14af88b3d450f3ca70eca17` |
| archive md5 | `0db592d0d00e010a6296674e1e2fd9ce` |

Provenance note: the archived binary (md5 ea159fc2f14af88b3d450f3ca70eca17) was captured by
scripts/seed/archive_seed.sh at HEAD cc955a69; gcc of the archive's self-emission
C reproduces the self-emission fixed point `ea159fc2f14af88b3d450f3ca70eca17` — both are the same
compiler state at HEAD cc955a69. The compiler self-build uses `-ffast` (user
programs default to `-fsafe`), so the recorded fixed point is the `-ffast`
binary. Rebuild recipes + full canonical flag-set requirement (`gcc -m32
-std=c89 -O0 -Wall -Wno-long-long -Wno-pointer-sign
-Wno-implicit-function-declaration`; the fixed point reproduces ONLY with
`-Wall` present) are recorded in `zig1-seed/SEED_README.txt`.
## 2026-09-20 — seed v45 (HEAD 031ec902)

Seed rotation via scripts/seed/archive_seed.sh. Archive layout: top-level dir
`zig1-seed/` with `zig1`, `gen/` (45 `.c` + 46 `.h` incl.
emitted `zig_special_types.h`, 8810878 bytes), `c_exit.c` (top level),
`runtime/`, `lib/`, `SEED_README.txt`.

| field | value |
|---|---|
| date | 2026-09-20 |
| HEAD | `031ec902` |
| seed binary md5 | `ff54332e2d4418eb663f225bbad6d9c7` |
| self-emission C | 45 `.c` + 46 `.h` (8810878 bytes) |
| fixed point | `ff54332e2d4418eb663f225bbad6d9c7` |
| archive md5 | `444f0d997867d3ff97d34d45d9720636` |

Provenance note: the archived binary (md5 ff54332e2d4418eb663f225bbad6d9c7) was captured by
scripts/seed/archive_seed.sh at HEAD 031ec902; gcc of the archive's self-emission
C reproduces the self-emission fixed point `ff54332e2d4418eb663f225bbad6d9c7` — both are the same
compiler state at HEAD 031ec902. The compiler self-build uses `-ffast` (user
programs default to `-fsafe`), so the recorded fixed point is the `-ffast`
binary. Rebuild recipes + full canonical flag-set requirement (`gcc -m32
-std=c89 -O0 -Wall -Wno-long-long -Wno-pointer-sign
-Wno-implicit-function-declaration`; the fixed point reproduces ONLY with
`-Wall` present) are recorded in `zig1-seed/SEED_README.txt`.

## 2026-09-20 — seed v44 (HEAD cf717d7c)

Seed rotation via scripts/seed/archive_seed.sh. Archive layout: top-level dir
`zig1-seed/` with `zig1`, `gen/` (45 `.c` + 46 `.h` incl.
emitted `zig_special_types.h`, 8802198 bytes), `c_exit.c` (top level),
`runtime/`, `lib/`, `SEED_README.txt`.

| field | value |
|---|---|
| date | 2026-09-20 |
| HEAD | `cf717d7c` |
| seed binary md5 | `27e61065a8006183d5f8c55043890c7c` |
| self-emission C | 45 `.c` + 46 `.h` (8802198 bytes) |
| fixed point | `27e61065a8006183d5f8c55043890c7c` |
| archive md5 | `d5bcddd4fd513a2ca3fe2c0997dee9ec` |

Provenance note: the archived binary (md5 27e61065a8006183d5f8c55043890c7c) was captured by
scripts/seed/archive_seed.sh at HEAD cf717d7c; gcc of the archive's self-emission
C reproduces the self-emission fixed point `27e61065a8006183d5f8c55043890c7c` — both are the same
compiler state at HEAD cf717d7c. The compiler self-build uses `-ffast` (user
programs default to `-fsafe`), so the recorded fixed point is the `-ffast`
binary. Rebuild recipes + full canonical flag-set requirement (`gcc -m32
-std=c89 -O0 -Wall -Wno-long-long -Wno-pointer-sign
-Wno-implicit-function-declaration`; the fixed point reproduces ONLY with
`-Wall` present) are recorded in `zig1-seed/SEED_README.txt`.

## 2026-09-20 — seed v43 (HEAD 7b6b05ac)

Seed rotation via scripts/seed/archive_seed.sh. Archive layout: top-level dir
`zig1-seed/` with `zig1`, `gen/` (45 `.c` + 46 `.h` incl.
emitted `zig_special_types.h`, 8800765 bytes), `c_exit.c` (top level),
`runtime/`, `lib/`, `SEED_README.txt`.

| field | value |
|---|---|
| date | 2026-09-20 |
| HEAD | `7b6b05ac` |
| seed binary md5 | `1c4f676524f74061d8b459a747f9241d` |
| self-emission C | 45 `.c` + 46 `.h` (8800765 bytes) |
| fixed point | `1c4f676524f74061d8b459a747f9241d` |
| archive md5 | `f3f9e9bbfd10d6f675cf7a10819f0794` |

Provenance note: the archived binary (md5 1c4f676524f74061d8b459a747f9241d) was captured by
scripts/seed/archive_seed.sh at HEAD 7b6b05ac; gcc of the archive's self-emission
C reproduces the self-emission fixed point `1c4f676524f74061d8b459a747f9241d` — both are the same
compiler state at HEAD 7b6b05ac. The compiler self-build uses `-ffast` (user
programs default to `-fsafe`), so the recorded fixed point is the `-ffast`
binary. Rebuild recipes + full canonical flag-set requirement (`gcc -m32
-std=c89 -O0 -Wall -Wno-long-long -Wno-pointer-sign
-Wno-implicit-function-declaration`; the fixed point reproduces ONLY with
`-Wall` present) are recorded in `zig1-seed/SEED_README.txt`.

## 2026-09-20 — seed v42 (HEAD 4d0f5c23)

Seed rotation via scripts/seed/archive_seed.sh. Archive layout: top-level dir
`zig1-seed/` with `zig1`, `gen/` (45 `.c` + 46 `.h` incl.
emitted `zig_special_types.h`, 8783277 bytes), `c_exit.c` (top level),
`runtime/`, `lib/`, `SEED_README.txt`.

| field | value |
|---|---|
| date | 2026-09-20 |
| HEAD | `4d0f5c23` |
| seed binary md5 | `36c04ebf5f6f3f4afcb4baf8c721a6a0` |
| self-emission C | 45 `.c` + 46 `.h` (8783277 bytes) |
| fixed point | `36c04ebf5f6f3f4afcb4baf8c721a6a0` |
| archive md5 | `fe532ad44b659b8c4a34d0f7932fc04f` |

Provenance note: the archived binary (md5 36c04ebf5f6f3f4afcb4baf8c721a6a0) was captured by
scripts/seed/archive_seed.sh at HEAD 4d0f5c23; gcc of the archive's self-emission
C reproduces the self-emission fixed point `36c04ebf5f6f3f4afcb4baf8c721a6a0` — both are the same
compiler state at HEAD 4d0f5c23. The compiler self-build uses `-ffast` (user
programs default to `-fsafe`), so the recorded fixed point is the `-ffast`
binary. Rebuild recipes + full canonical flag-set requirement (`gcc -m32
-std=c89 -O0 -Wall -Wno-long-long -Wno-pointer-sign
-Wno-implicit-function-declaration`; the fixed point reproduces ONLY with
`-Wall` present) are recorded in `zig1-seed/SEED_README.txt`.

## 2026-09-20 — seed v41 (HEAD 1b1371ba; lib/ from working tree at ba9aa6ae)

Seed rotation via scripts/seed/archive_seed.sh. Archive layout: top-level dir
`zig1-seed/` with `zig1`, `gen/` (45 `.c` + 46 `.h` incl.
emitted `zig_special_types.h`, 8781404 bytes), `c_exit.c` (top level),
`runtime/`, `lib/`, `SEED_README.txt`.

| field | value |
|---|---|
| date | 2026-09-20 |
| HEAD | `1b1371ba` (binary/gen); `lib/` captured from working tree at `ba9aa6ae` |
| seed binary md5 | `197602956b55d1cb59848a922a934fe8` |
| self-emission C | 45 `.c` + 46 `.h` (8781404 bytes) |
| fixed point | `197602956b55d1cb59848a922a934fe8` |
| archive md5 | `c9461ae95e8b6ff3c4cd585663fbca8b` |

Provenance note: the archived binary (md5 197602956b55d1cb59848a922a934fe8) was captured by
scripts/seed/archive_seed.sh at HEAD 1b1371ba; gcc of the archive's self-emission
C reproduces the self-emission fixed point `197602956b55d1cb59848a922a934fe8` — both are the same
compiler state at HEAD 1b1371ba. `archive_seed.sh` copies `lib/` from the working tree (not from
committed HEAD), so the archived `lib/` corresponds to `ba9aa6ae` — the `sf/src` revision whose
`std_async.zig` carries `std.async.suspendUntil`. The compiler self-build uses `-ffast` (user
programs default to `-fsafe`), so the recorded fixed point is the `-ffast`
binary. Rebuild recipes + full canonical flag-set requirement (`gcc -m32
-std=c89 -O0 -Wall -Wno-long-long -Wno-pointer-sign
-Wno-implicit-function-declaration`; the fixed point reproduces ONLY with
`-Wall` present) are recorded in `zig1-seed/SEED_README.txt`.

## 2026-09-19 — seed v40 (HEAD e921d040)

Seed rotation via scripts/seed/archive_seed.sh. Archive layout: top-level dir
`zig1-seed/` with `zig1`, `gen/` (45 `.c` + 46 `.h` incl.
emitted `zig_special_types.h`, 8781404 bytes), `c_exit.c` (top level),
`runtime/`, `lib/`, `SEED_README.txt`.

| field | value |
|---|---|
| date | 2026-09-19 |
| HEAD | `e921d040` |
| seed binary md5 | `197602956b55d1cb59848a922a934fe8` |
| self-emission C | 45 `.c` + 46 `.h` (8781404 bytes) |
| fixed point | `197602956b55d1cb59848a922a934fe8` |
| archive md5 | `0e3250ea5bdcff1ccd79f8954ea17f48` |

Provenance note: the archived binary (md5 197602956b55d1cb59848a922a934fe8) was captured by
scripts/seed/archive_seed.sh at HEAD e921d040; gcc of the archive's self-emission
C reproduces the self-emission fixed point `197602956b55d1cb59848a922a934fe8` — both are the same
compiler state at HEAD e921d040. The compiler self-build uses `-ffast` (user
programs default to `-fsafe`), so the recorded fixed point is the `-ffast`
binary. Rebuild recipes + full canonical flag-set requirement (`gcc -m32
-std=c89 -O0 -Wall -Wno-long-long -Wno-pointer-sign
-Wno-implicit-function-declaration`; the fixed point reproduces ONLY with
`-Wall` present) are recorded in `zig1-seed/SEED_README.txt`.
## 2026-09-19 — seed v39 (HEAD 5734a66b)

Seed rotation via scripts/seed/archive_seed.sh. Archive layout: top-level dir
`zig1-seed/` with `zig1`, `gen/` (45 `.c` + 46 `.h` incl.
emitted `zig_special_types.h`, 8781025 bytes), `c_exit.c` (top level),
`runtime/`, `lib/`, `SEED_README.txt`.

| field | value |
|---|---|
| date | 2026-09-19 |
| HEAD | `5734a66b` |
| seed binary md5 | `fc9198f6c1a24c92ec136e741c81c975` |
| self-emission C | 45 `.c` + 46 `.h` (8781025 bytes) |
| fixed point | `fc9198f6c1a24c92ec136e741c81c975` |
| archive md5 | `4e493be2625311fa11c8f421b732c59a` |

Provenance note: the archived binary (md5 fc9198f6c1a24c92ec136e741c81c975) was captured by
scripts/seed/archive_seed.sh at HEAD 5734a66b; gcc of the archive's self-emission
C reproduces the self-emission fixed point `fc9198f6c1a24c92ec136e741c81c975` — both are the same
compiler state at HEAD 5734a66b. The compiler self-build uses `-ffast` (user
programs default to `-fsafe`), so the recorded fixed point is the `-ffast`
binary. Rebuild recipes + full canonical flag-set requirement (`gcc -m32
-std=c89 -O0 -Wall -Wno-long-long -Wno-pointer-sign
-Wno-implicit-function-declaration`; the fixed point reproduces ONLY with
`-Wall` present) are recorded in `zig1-seed/SEED_README.txt`.

## 2026-09-19 — seed v38 (HEAD 64c3ce70)

Seed rotation via scripts/seed/archive_seed.sh. Archive layout: top-level dir
`zig1-seed/` with `zig1`, `gen/` (45 `.c` + 46 `.h` incl.
emitted `zig_special_types.h`, 8781025 bytes), `c_exit.c` (top level),
`runtime/`, `lib/`, `SEED_README.txt`.

| field | value |
|---|---|
| date | 2026-09-19 |
| HEAD | `64c3ce70` |
| seed binary md5 | `fc9198f6c1a24c92ec136e741c81c975` |
| self-emission C | 45 `.c` + 46 `.h` (8781025 bytes) |
| fixed point | `fc9198f6c1a24c92ec136e741c81c975` |
| archive md5 | `372385a68099d19269b099ef6e4a5e27` |

Provenance note: the archived binary (md5 fc9198f6c1a24c92ec136e741c81c975) was captured by
scripts/seed/archive_seed.sh at HEAD 64c3ce70; gcc of the archive's self-emission
C reproduces the self-emission fixed point `fc9198f6c1a24c92ec136e741c81c975` — both are the same
compiler state at HEAD 64c3ce70. The compiler self-build uses `-ffast` (user
programs default to `-fsafe`), so the recorded fixed point is the `-ffast`
binary. Rebuild recipes + full canonical flag-set requirement (`gcc -m32
-std=c89 -O0 -Wall -Wno-long-long -Wno-pointer-sign
-Wno-implicit-function-declaration`; the fixed point reproduces ONLY with
`-Wall` present) are recorded in `zig1-seed/SEED_README.txt`.

## 2026-09-19 — seed v37 (HEAD d896217b)

Seed rotation via scripts/seed/archive_seed.sh. Archive layout: top-level dir
`zig1-seed/` with `zig1`, `gen/` (45 `.c` + 46 `.h` incl.
emitted `zig_special_types.h`, 8772691 bytes), `c_exit.c` (top level),
`runtime/`, `lib/`, `SEED_README.txt`.

| field | value |
|---|---|
| date | 2026-09-19 |
| HEAD | `d896217b` |
| seed binary md5 | `1ffd20c17fe28c88238bf3c7a286bdd5` |
| self-emission C | 45 `.c` + 46 `.h` (8772691 bytes) |
| fixed point | `1ffd20c17fe28c88238bf3c7a286bdd5` |
| archive md5 | `14d8ad3e853cfaea91755d3e11d9cd3e` |

Provenance note: the archived binary (md5 1ffd20c17fe28c88238bf3c7a286bdd5) was captured by
scripts/seed/archive_seed.sh at HEAD d896217b; gcc of the archive's self-emission
C reproduces the self-emission fixed point `1ffd20c17fe28c88238bf3c7a286bdd5` — both are the same
compiler state at HEAD d896217b. The compiler self-build uses `-ffast` (user
programs default to `-fsafe`), so the recorded fixed point is the `-ffast`
binary. Rebuild recipes + full canonical flag-set requirement (`gcc -m32
-std=c89 -O0 -Wall -Wno-long-long -Wno-pointer-sign
-Wno-implicit-function-declaration`; the fixed point reproduces ONLY with
`-Wall` present) are recorded in `zig1-seed/SEED_README.txt`.

## 2026-09-18 — seed v36 (HEAD 3e809080)

Seed rotation via scripts/seed/archive_seed.sh. Archive layout: top-level dir
`zig1-seed/` with `zig1`, `gen/` (45 `.c` + 46 `.h` incl.
emitted `zig_special_types.h`, 8771612 bytes), `c_exit.c` (top level),
`runtime/`, `lib/`, `SEED_README.txt`.

| field | value |
|---|---|
| date | 2026-09-18 |
| HEAD | `3e809080` |
| seed binary md5 | `bcfa85a40279a5c7bc4d8e6fd5f8df91` |
| self-emission C | 45 `.c` + 46 `.h` (8771612 bytes) |
| fixed point | `bcfa85a40279a5c7bc4d8e6fd5f8df91` |
| archive md5 | `a0a2fc8e49fc888385b0927ada602b06` |

Provenance note: the archived binary (md5 bcfa85a40279a5c7bc4d8e6fd5f8df91) was captured by
scripts/seed/archive_seed.sh at HEAD 3e809080; gcc of the archive's self-emission
C reproduces the self-emission fixed point `bcfa85a40279a5c7bc4d8e6fd5f8df91` — both are the same
compiler state at HEAD 3e809080. The compiler self-build uses `-ffast` (user
programs default to `-fsafe`), so the recorded fixed point is the `-ffast`
binary. Rebuild recipes + full canonical flag-set requirement (`gcc -m32
-std=c89 -O0 -Wall -Wno-long-long -Wno-pointer-sign
-Wno-implicit-function-declaration`; the fixed point reproduces ONLY with
`-Wall` present) are recorded in `zig1-seed/SEED_README.txt`.

## 2026-09-18 — seed v35 (HEAD e1f1bf8c)

Seed rotation via scripts/seed/archive_seed.sh. Archive layout: top-level dir
`zig1-seed/` with `zig1`, `gen/` (45 `.c` + 46 `.h` incl.
emitted `zig_special_types.h`, 8764125 bytes), `c_exit.c` (top level),
`runtime/`, `lib/`, `SEED_README.txt`.

| field | value |
|---|---|
| date | 2026-09-18 |
| HEAD | `e1f1bf8c` |
| seed binary md5 | `9265739b7b5e7b1626b8db7ad4255fc5` |
| self-emission C | 45 `.c` + 46 `.h` (8764125 bytes) |
| fixed point | `9265739b7b5e7b1626b8db7ad4255fc5` |
| archive md5 | `981d58539c31cd5b66d97aef4ee87ebe` |

Provenance note: the archived binary (md5 9265739b7b5e7b1626b8db7ad4255fc5) was captured by
scripts/seed/archive_seed.sh at HEAD e1f1bf8c; gcc of the archive's self-emission
C reproduces the self-emission fixed point `9265739b7b5e7b1626b8db7ad4255fc5` — both are the same
compiler state at HEAD e1f1bf8c. The compiler self-build uses `-ffast` (user
programs default to `-fsafe`), so the recorded fixed point is the `-ffast`
binary. Rebuild recipes + full canonical flag-set requirement (`gcc -m32
-std=c89 -O0 -Wall -Wno-long-long -Wno-pointer-sign
-Wno-implicit-function-declaration`; the fixed point reproduces ONLY with
`-Wall` present) are recorded in `zig1-seed/SEED_README.txt`.

## 2026-09-18 — seed v34 (HEAD 2b7acb2d)

Seed rotation via scripts/seed/archive_seed.sh. Archive layout: top-level dir
`zig1-seed/` with `zig1`, `gen/` (45 `.c` + 46 `.h` incl.
emitted `zig_special_types.h`, 8764000 bytes), `c_exit.c` (top level),
`runtime/`, `lib/`, `SEED_README.txt`.

| field | value |
|---|---|
| date | 2026-09-18 |
| HEAD | `2b7acb2d` |
| seed binary md5 | `b0e7042a26e74d7b744a0a49546149b4` |
| self-emission C | 45 `.c` + 46 `.h` (8764000 bytes) |
| fixed point | `b0e7042a26e74d7b744a0a49546149b4` |
| archive md5 | `a4d4de3cc7ff131da3a01865b3622ed7` |

Provenance note: the archived binary (md5 b0e7042a26e74d7b744a0a49546149b4) was captured by
scripts/seed/archive_seed.sh at HEAD 2b7acb2d; gcc of the archive's self-emission
C reproduces the self-emission fixed point `b0e7042a26e74d7b744a0a49546149b4` — both are the same
compiler state at HEAD 2b7acb2d. The compiler self-build uses `-ffast` (user
programs default to `-fsafe`), so the recorded fixed point is the `-ffast`
binary. Rebuild recipes + full canonical flag-set requirement (`gcc -m32
-std=c89 -O0 -Wall -Wno-long-long -Wno-pointer-sign
-Wno-implicit-function-declaration`; the fixed point reproduces ONLY with
`-Wall` present) are recorded in `zig1-seed/SEED_README.txt`.

## 2026-09-18 — seed v33 (HEAD a9b515d9)

Seed rotation via scripts/seed/archive_seed.sh. Archive layout: top-level dir
`zig1-seed/` with `zig1`, `gen/` (45 `.c` + 46 `.h` incl.
emitted `zig_special_types.h`, 8743961 bytes), `c_exit.c` (top level),
`runtime/`, `lib/`, `SEED_README.txt`.

| field | value |
|---|---|
| date | 2026-09-18 |
| HEAD | `a9b515d9` |
| seed binary md5 | `417c435cec303378b224ecdff3f64f26` |
| self-emission C | 45 `.c` + 46 `.h` (8743961 bytes) |
| fixed point | `417c435cec303378b224ecdff3f64f26` |
| archive md5 | `799dbca38d211f6a3d962f3773215adf` |

Provenance note: the archived binary (md5 417c435cec303378b224ecdff3f64f26) was captured by
scripts/seed/archive_seed.sh at HEAD a9b515d9; gcc of the archive's self-emission
C reproduces the self-emission fixed point `417c435cec303378b224ecdff3f64f26` — both are the same
compiler state at HEAD a9b515d9. The compiler self-build uses `-ffast` (user
programs default to `-fsafe`), so the recorded fixed point is the `-ffast`
binary. Rebuild recipes + full canonical flag-set requirement (`gcc -m32
-std=c89 -O0 -Wall -Wno-long-long -Wno-pointer-sign
-Wno-implicit-function-declaration`; the fixed point reproduces ONLY with
`-Wall` present) are recorded in `zig1-seed/SEED_README.txt`.

## 2026-09-18 — seed v32 (HEAD fe784e9c)

Seed rotation via scripts/seed/archive_seed.sh. Archive layout: top-level dir
`zig1-seed/` with `zig1`, `gen/` (45 `.c` + 46 `.h` incl.
emitted `zig_special_types.h`, 8751385 bytes), `c_exit.c` (top level),
`runtime/`, `lib/`, `SEED_README.txt`.

| field | value |
|---|---|
| date | 2026-09-18 |
| HEAD | `fe784e9c` |
| seed binary md5 | `ab7187cc988e39dc5907b95ccc182f9f` |
| self-emission C | 45 `.c` + 46 `.h` (8751385 bytes) |
| fixed point | `ab7187cc988e39dc5907b95ccc182f9f` |
| archive md5 | `2eb158f3f24363968e9bf0f085461de8` |

Provenance note: the archived binary (md5 ab7187cc988e39dc5907b95ccc182f9f) was captured by
scripts/seed/archive_seed.sh at HEAD fe784e9c; gcc of the archive's self-emission
C reproduces the self-emission fixed point `ab7187cc988e39dc5907b95ccc182f9f` — both are the same
compiler state at HEAD fe784e9c. The compiler self-build uses `-ffast` (user
programs default to `-fsafe`), so the recorded fixed point is the `-ffast`
binary. Rebuild recipes + full canonical flag-set requirement (`gcc -m32
-std=c89 -O0 -Wall -Wno-long-long -Wno-pointer-sign
-Wno-implicit-function-declaration`; the fixed point reproduces ONLY with
`-Wall` present) are recorded in `zig1-seed/SEED_README.txt`.

## 2026-09-18 — seed v31 (HEAD 1bd0d0d6)

Seed rotation via scripts/seed/archive_seed.sh. Archive layout: top-level dir
`zig1-seed/` with `zig1`, `gen/` (45 `.c` + 46 `.h` incl.
emitted `zig_special_types.h`, 8742372 bytes), `c_exit.c` (top level),
`runtime/`, `lib/`, `SEED_README.txt`.

| field | value |
|---|---|
| date | 2026-09-18 |
| HEAD | `1bd0d0d6` |
| seed binary md5 | `6d704d2265096513cf1706f5b414bd27` |
| self-emission C | 45 `.c` + 46 `.h` (8742372 bytes) |
| fixed point | `6d704d2265096513cf1706f5b414bd27` |
| archive md5 | `7ae31cec80cc3726dba042d694c11c25` |

Provenance note: the archived binary (md5 6d704d2265096513cf1706f5b414bd27) was captured by
scripts/seed/archive_seed.sh at HEAD 1bd0d0d6; gcc of the archive's self-emission
C reproduces the self-emission fixed point `6d704d2265096513cf1706f5b414bd27` — both are the same
compiler state at HEAD 1bd0d0d6. The compiler self-build uses `-ffast` (user
programs default to `-fsafe`), so the recorded fixed point is the `-ffast`
binary. Rebuild recipes + full canonical flag-set requirement (`gcc -m32
-std=c89 -O0 -Wall -Wno-long-long -Wno-pointer-sign
-Wno-implicit-function-declaration`; the fixed point reproduces ONLY with
`-Wall` present) are recorded in `zig1-seed/SEED_README.txt`.

## 2026-09-18 — seed v30 (HEAD 69066336; archive content 871074e1)

Seed rotation via scripts/seed/archive_seed.sh. Archive layout: top-level dir
`zig1-seed/` with `zig1`, `gen/` (45 `.c` + 46 `.h` incl.
emitted `zig_special_types.h`, 8739997 bytes), `c_exit.c` (top level),
`runtime/`, `lib/`, `SEED_README.txt`.

| field | value |
|---|---|
| date | 2026-09-18 |
| HEAD | `69066336` |
| archive content commit | `871074e1` |
| seed binary md5 | `414cccee639bdb61c7a9f1f2ddddb166` |
| self-emission C | 45 `.c` + 46 `.h` (8739997 bytes) |
| fixed point | `414cccee639bdb61c7a9f1f2ddddb166` |
| archive md5 | `c0a218c5e7a74afb11435abe20c7d990` |

Provenance note: the archived binary (md5 414cccee639bdb61c7a9f1f2ddddb166) was captured by
scripts/seed/archive_seed.sh at HEAD 69066336 (binary state); the archive itself was
committed in 871074e1, whose `lib/` carries the Task 5a-F exact-multiple fix. A checkout of
871074e1 therefore reproduces the archive's `lib/`; a checkout of the binary-state HEAD
69066336 does not. gcc of the archive's self-emission C reproduces the self-emission fixed
point `414cccee639bdb61c7a9f1f2ddddb166` — both are the same compiler state (the fix is
std-only and cannot move the fixed point). The compiler self-build uses `-ffast` (user
programs default to `-fsafe`), so the recorded fixed point is the `-ffast`
binary. Rebuild recipes + full canonical flag-set requirement (`gcc -m32
-std=c89 -O0 -Wall -Wno-long-long -Wno-pointer-sign
-Wno-implicit-function-declaration`; the fixed point reproduces ONLY with
`-Wall` present) are recorded in `zig1-seed/SEED_README.txt`.

## 2026-09-18 — seed v29 (HEAD 7c2b2445)

Seed rotation via scripts/seed/archive_seed.sh. Archive layout: top-level dir
`zig1-seed/` with `zig1`, `gen/` (45 `.c` + 46 `.h` incl.
emitted `zig_special_types.h`, 8739997 bytes), `c_exit.c` (top level),
`runtime/`, `lib/`, `SEED_README.txt`.

| field | value |
|---|---|
| date | 2026-09-18 |
| HEAD | `7c2b2445` |
| seed binary md5 | `414cccee639bdb61c7a9f1f2ddddb166` |
| self-emission C | 45 `.c` + 46 `.h` (8739997 bytes) |
| fixed point | `414cccee639bdb61c7a9f1f2ddddb166` |
| archive md5 | `910a4d673f0fa95f8473c08e143ceb54` |

Provenance note: the archived binary (md5 414cccee639bdb61c7a9f1f2ddddb166) was captured by
scripts/seed/archive_seed.sh at HEAD 7c2b2445; gcc of the archive's self-emission
C reproduces the self-emission fixed point `414cccee639bdb61c7a9f1f2ddddb166` — both are the same
compiler state at HEAD 7c2b2445. The compiler self-build uses `-ffast` (user
programs default to `-fsafe`), so the recorded fixed point is the `-ffast`
binary. Rebuild recipes + full canonical flag-set requirement (`gcc -m32
-std=c89 -O0 -Wall -Wno-long-long -Wno-pointer-sign
-Wno-implicit-function-declaration`; the fixed point reproduces ONLY with
`-Wall` present) are recorded in `zig1-seed/SEED_README.txt`.

## 2026-09-18 — seed v28 (HEAD c235126d)

Seed rotation via scripts/seed/archive_seed.sh. Archive layout: top-level dir
`zig1-seed/` with `zig1`, `gen/` (45 `.c` + 46 `.h` incl.
emitted `zig_special_types.h`, 8733246 bytes), `c_exit.c` (top level),
`runtime/`, `lib/`, `SEED_README.txt`.

| field | value |
|---|---|
| date | 2026-09-18 |
| HEAD | `c235126d` |
| seed binary md5 | `7513a8d59a3c317639a055491769a9c5` |
| self-emission C | 45 `.c` + 46 `.h` (8733246 bytes) |
| fixed point | `7513a8d59a3c317639a055491769a9c5` |
| archive md5 | `e7bebc14f4b600a7742062ac2ab4c38d` |

Provenance note: the archived binary (md5 7513a8d59a3c317639a055491769a9c5) was captured by
scripts/seed/archive_seed.sh at HEAD c235126d; gcc of the archive's self-emission
C reproduces the self-emission fixed point `7513a8d59a3c317639a055491769a9c5` — both are the same
compiler state at HEAD c235126d. The compiler self-build uses `-ffast` (user
programs default to `-fsafe`), so the recorded fixed point is the `-ffast`
binary. Rebuild recipes + full canonical flag-set requirement (`gcc -m32
-std=c89 -O0 -Wall -Wno-long-long -Wno-pointer-sign
-Wno-implicit-function-declaration`; the fixed point reproduces ONLY with
`-Wall` present) are recorded in `zig1-seed/SEED_README.txt`.

## 2026-09-17 — seed v27 (HEAD 0a37ca6e)

Seed rotation via scripts/seed/archive_seed.sh. Archive layout: top-level dir
`zig1-seed/` with `zig1`, `gen/` (45 `.c` + 46 `.h` incl.
emitted `zig_special_types.h`, 8682995 bytes), `c_exit.c` (top level),
`runtime/`, `lib/`, `SEED_README.txt`.

| field | value |
|---|---|
| date | 2026-09-17 |
| HEAD | `0a37ca6e` |
| seed binary md5 | `553a39b42983ce72459698a7aa5817e1` |
| self-emission C | 45 `.c` + 46 `.h` (8682995 bytes) |
| fixed point | `553a39b42983ce72459698a7aa5817e1` |
| archive md5 | `cab32bf6ba4998a2a78de3064a07443e` |

Provenance note: the archived binary (md5 553a39b42983ce72459698a7aa5817e1) was captured by
scripts/seed/archive_seed.sh at HEAD 0a37ca6e; gcc of the archive's self-emission
C reproduces the self-emission fixed point `553a39b42983ce72459698a7aa5817e1` — both are the same
compiler state at HEAD 0a37ca6e. The compiler self-build uses `-ffast` (user
programs default to `-fsafe`), so the recorded fixed point is the `-ffast`
binary. Rebuild recipes + full canonical flag-set requirement (`gcc -m32
-std=c89 -O0 -Wall -Wno-long-long -Wno-pointer-sign
-Wno-implicit-function-declaration`; the fixed point reproduces ONLY with
`-Wall` present) are recorded in `zig1-seed/SEED_README.txt`.

## 2026-09-17 — seed v26 (HEAD e3e58d7b)

Seed rotation via scripts/seed/archive_seed.sh. Archive layout: top-level dir
`zig1-seed/` with `zig1`, `gen/` (45 `.c` + 46 `.h` incl.
emitted `zig_special_types.h`, 8680133 bytes), `c_exit.c` (top level),
`runtime/`, `lib/`, `SEED_README.txt`.

| field | value |
|---|---|
| date | 2026-09-17 |
| HEAD | `e3e58d7b` |
| seed binary md5 | `f03d8485f563990367faec4b7d57b5b1` |
| self-emission C | 45 `.c` + 46 `.h` (8680133 bytes) |
| fixed point | `f03d8485f563990367faec4b7d57b5b1` |
| archive md5 | `fbd6a84da8afe1e5a9e31210b4b28cc6` |

Provenance note: the archived binary (md5 f03d8485f563990367faec4b7d57b5b1) was captured by
scripts/seed/archive_seed.sh at HEAD e3e58d7b; gcc of the archive's self-emission
C reproduces the self-emission fixed point `f03d8485f563990367faec4b7d57b5b1` — both are the same
compiler state at HEAD e3e58d7b. The compiler self-build uses `-ffast` (user
programs default to `-fsafe`), so the recorded fixed point is the `-ffast`
binary. Rebuild recipes + full canonical flag-set requirement (`gcc -m32
-std=c89 -O0 -Wall -Wno-long-long -Wno-pointer-sign
-Wno-implicit-function-declaration`; the fixed point reproduces ONLY with
`-Wall` present) are recorded in `zig1-seed/SEED_README.txt`.

## 2026-09-17 — seed v25 (HEAD dc181cf0)

Seed rotation via scripts/seed/archive_seed.sh. Archive layout: top-level dir
`zig1-seed/` with `zig1`, `gen/` (45 `.c` + 46 `.h` incl.
emitted `zig_special_types.h`, 8679733 bytes), `c_exit.c` (top level),
`runtime/`, `lib/`, `SEED_README.txt`.

| field | value |
|---|---|
| date | 2026-09-17 |
| HEAD | `dc181cf0` |
| seed binary md5 | `ba95dd0a698b2f4b72b99953dc72cad5` |
| self-emission C | 45 `.c` + 46 `.h` (8679733 bytes) |
| fixed point | `ba95dd0a698b2f4b72b99953dc72cad5` |
| archive md5 | `573f0221706e150e034830a51be6aa6c` |

Provenance note: the archived binary (md5 ba95dd0a698b2f4b72b99953dc72cad5) was captured by
scripts/seed/archive_seed.sh at HEAD dc181cf0; gcc of the archive's self-emission
C reproduces the self-emission fixed point `ba95dd0a698b2f4b72b99953dc72cad5` — both are the same
compiler state at HEAD dc181cf0. The compiler self-build uses `-ffast` (user
programs default to `-fsafe`), so the recorded fixed point is the `-ffast`
binary. Rebuild recipes + full canonical flag-set requirement (`gcc -m32
-std=c89 -O0 -Wall -Wno-long-long -Wno-pointer-sign
-Wno-implicit-function-declaration`; the fixed point reproduces ONLY with
`-Wall` present) are recorded in `zig1-seed/SEED_README.txt`.

## 2026-09-17 — seed v24 (HEAD 8d9d33fc)

Seed rotation via scripts/seed/archive_seed.sh. Archive layout: top-level dir
`zig1-seed/` with `zig1`, `gen/` (45 `.c` + 46 `.h` incl.
emitted `zig_special_types.h`, 8668811 bytes), `c_exit.c` (top level),
`runtime/`, `lib/`, `SEED_README.txt`.

| field | value |
|---|---|
| date | 2026-09-17 |
| HEAD | `8d9d33fc` |
| seed binary md5 | `dd43612912662fc06a25a10eb194c665` |
| self-emission C | 45 `.c` + 46 `.h` (8668811 bytes) |
| fixed point | `dd43612912662fc06a25a10eb194c665` |
| archive md5 | `3f00a9724db95a0199917ca9c84de37b` |

Provenance note: the archived binary (md5 dd43612912662fc06a25a10eb194c665) was captured by
scripts/seed/archive_seed.sh at HEAD 8d9d33fc; gcc of the archive's self-emission
C reproduces the self-emission fixed point `dd43612912662fc06a25a10eb194c665` — both are the same
compiler state at HEAD 8d9d33fc. The compiler self-build uses `-ffast` (user
programs default to `-fsafe`), so the recorded fixed point is the `-ffast`
binary. Rebuild recipes + full canonical flag-set requirement (`gcc -m32
-std=c89 -O0 -Wall -Wno-long-long -Wno-pointer-sign
-Wno-implicit-function-declaration`; the fixed point reproduces ONLY with
`-Wall` present) are recorded in `zig1-seed/SEED_README.txt`.

## 2026-09-17 — seed v23 (HEAD f2657957)

Seed rotation via scripts/seed/archive_seed.sh. Archive layout: top-level dir
`zig1-seed/` with `zig1`, `gen/` (45 `.c` + 46 `.h` incl.
emitted `zig_special_types.h`, 8627179 bytes), `c_exit.c` (top level),
`runtime/`, `lib/`, `SEED_README.txt`.

| field | value |
|---|---|
| date | 2026-09-17 |
| HEAD | `f2657957` |
| seed binary md5 | `b981bc80290bfde5ed5383cd0927e124` |
| self-emission C | 45 `.c` + 46 `.h` (8627179 bytes) |
| fixed point | `b981bc80290bfde5ed5383cd0927e124` |
| archive md5 | `deb4f0fbd4853283a1c11c225d714bd8` |

Provenance note: the archived binary (md5 b981bc80290bfde5ed5383cd0927e124) was captured by
scripts/seed/archive_seed.sh at HEAD f2657957; gcc of the archive's self-emission
C reproduces the self-emission fixed point `b981bc80290bfde5ed5383cd0927e124` — both are the same
compiler state at HEAD f2657957. The compiler self-build uses `-ffast` (user
programs default to `-fsafe`), so the recorded fixed point is the `-ffast`
binary. Rebuild recipes + full canonical flag-set requirement (`gcc -m32
-std=c89 -O0 -Wall -Wno-long-long -Wno-pointer-sign
-Wno-implicit-function-declaration`; the fixed point reproduces ONLY with
`-Wall` present) are recorded in `zig1-seed/SEED_README.txt`.

## 2026-09-17 — seed v22 (HEAD 66446667)

Seed rotation via scripts/seed/archive_seed.sh. Archive layout: top-level dir
`zig1-seed/` with `zig1`, `gen/` (45 `.c` + 46 `.h` incl.
emitted `zig_special_types.h`, 8627084 bytes), `c_exit.c` (top level),
`runtime/`, `lib/`, `SEED_README.txt`.

| field | value |
|---|---|
| date | 2026-09-17 |
| HEAD | `66446667` |
| seed binary md5 | `9b3075b105ff544f3541d5a621d00d40` |
| self-emission C | 45 `.c` + 46 `.h` (8627084 bytes) |
| fixed point | `9b3075b105ff544f3541d5a621d00d40` |
| archive md5 | `d98a1ef0e5469aad63ef6a9091fe3dcd` |

Provenance note: the archived binary (md5 9b3075b105ff544f3541d5a621d00d40) was captured by
scripts/seed/archive_seed.sh at HEAD 66446667; gcc of the archive's self-emission
C reproduces the self-emission fixed point `9b3075b105ff544f3541d5a621d00d40` — both are the same
compiler state at HEAD 66446667. The compiler self-build uses `-ffast` (user
programs default to `-fsafe`), so the recorded fixed point is the `-ffast`
binary. Rebuild recipes + full canonical flag-set requirement (`gcc -m32
-std=c89 -O0 -Wall -Wno-long-long -Wno-pointer-sign
-Wno-implicit-function-declaration`; the fixed point reproduces ONLY with
`-Wall` present) are recorded in `zig1-seed/SEED_README.txt`.

## 2026-09-17 — seed v21 (HEAD 17422544)

Seed rotation via scripts/seed/archive_seed.sh. Archive layout: top-level dir
`zig1-seed/` with `zig1`, `gen/` (45 `.c` + 46 `.h` incl.
emitted `zig_special_types.h`, 8598401 bytes), `c_exit.c` (top level),
`runtime/`, `lib/`, `SEED_README.txt`.

| field | value |
|---|---|
| date | 2026-09-17 |
| HEAD | `17422544` |
| seed binary md5 | `18e0de5cf71f4fe0fbf5c560ab24e624` |
| self-emission C | 45 `.c` + 46 `.h` (8598401 bytes) |
| fixed point | `18e0de5cf71f4fe0fbf5c560ab24e624` |
| archive md5 | `0d4bbc0c477e841e8e983f8cf23e6326` |

Provenance note: the archived binary (md5 18e0de5cf71f4fe0fbf5c560ab24e624) was captured by
scripts/seed/archive_seed.sh at HEAD 17422544; gcc of the archive's self-emission
C reproduces the self-emission fixed point `18e0de5cf71f4fe0fbf5c560ab24e624` — both are the same
compiler state at HEAD 17422544. The compiler self-build uses `-ffast` (user
programs default to `-fsafe`), so the recorded fixed point is the `-ffast`
binary. Rebuild recipes + full canonical flag-set requirement (`gcc -m32
-std=c89 -O0 -Wall -Wno-long-long -Wno-pointer-sign
-Wno-implicit-function-declaration`; the fixed point reproduces ONLY with
`-Wall` present) are recorded in `zig1-seed/SEED_README.txt`.

## 2026-09-17 — seed v20 (HEAD 6ef08661)

Seed rotation via scripts/seed/archive_seed.sh. Archive layout: top-level dir
`zig1-seed/` with `zig1`, `gen/` (45 `.c` + 46 `.h` incl.
emitted `zig_special_types.h`, 8598401 bytes), `c_exit.c` (top level),
`runtime/`, `lib/`, `SEED_README.txt`.

| field | value |
|---|---|
| date | 2026-09-17 |
| HEAD | `6ef08661` |
| seed binary md5 | `18e0de5cf71f4fe0fbf5c560ab24e624` |
| self-emission C | 45 `.c` + 46 `.h` (8598401 bytes) |
| fixed point | `18e0de5cf71f4fe0fbf5c560ab24e624` |
| archive md5 | `f2175ae48d8174afad02294ee08bb5ef` |

Provenance note: the archived binary (md5 18e0de5cf71f4fe0fbf5c560ab24e624) was captured by
scripts/seed/archive_seed.sh at HEAD 6ef08661; gcc of the archive's self-emission
C reproduces the self-emission fixed point `18e0de5cf71f4fe0fbf5c560ab24e624` — both are the same
compiler state at HEAD 6ef08661. The compiler self-build uses `-ffast` (user
programs default to `-fsafe`), so the recorded fixed point is the `-ffast`
binary. Rebuild recipes + full canonical flag-set requirement (`gcc -m32
-std=c89 -O0 -Wall -Wno-long-long -Wno-pointer-sign
-Wno-implicit-function-declaration`; the fixed point reproduces ONLY with
`-Wall` present) are recorded in `zig1-seed/SEED_README.txt`.

## 2026-09-15 — seed v19 (HEAD d7ea6667)

Seed rotation via scripts/seed/archive_seed.sh. Archive layout: top-level dir
`zig1-seed/` with `zig1`, `gen/` (45 `.c` + 46 `.h` incl.
emitted `zig_special_types.h`, 8365062 bytes), `c_exit.c` (top level),
`runtime/`, `lib/`, `SEED_README.txt`.

| field | value |
|---|---|
| date | 2026-09-15 |
| HEAD | `d7ea6667` |
| seed binary md5 | `027377296b2e38402ff8470f5c429eb8` |
| self-emission C | 45 `.c` + 46 `.h` (8365062 bytes) |
| fixed point | `027377296b2e38402ff8470f5c429eb8` |
| archive md5 | `23a16154e83736cf6b636685396a124a` |

Provenance note: the archived binary (md5 027377296b2e38402ff8470f5c429eb8) was captured by
scripts/seed/archive_seed.sh at HEAD d7ea6667; gcc of the archive's self-emission
C reproduces the self-emission fixed point `027377296b2e38402ff8470f5c429eb8` — both are the same
compiler state at HEAD d7ea6667. The compiler self-build uses `-ffast` (user
programs default to `-fsafe`), so the recorded fixed point is the `-ffast`
binary. Rebuild recipes + full canonical flag-set requirement (`gcc -m32
-std=c89 -O0 -Wall -Wno-long-long -Wno-pointer-sign
-Wno-implicit-function-declaration`; the fixed point reproduces ONLY with
`-Wall` present) are recorded in `zig1-seed/SEED_README.txt`.

## 2026-09-15 — seed v18 (HEAD d2629f9c)

Seed rotation via scripts/seed/archive_seed.sh. Archive layout: top-level dir
`zig1-seed/` with `zig1`, `gen/` (45 `.c` + 46 `.h` incl.
emitted `zig_special_types.h`, 8355820 bytes), `c_exit.c` (top level),
`runtime/`, `lib/`, `SEED_README.txt`.

| field | value |
|---|---|
| date | 2026-09-15 |
| HEAD | `d2629f9c` |
| seed binary md5 | `7b515420f749604c1765c2b1edd0d654` |
| self-emission C | 45 `.c` + 46 `.h` (8355820 bytes) |
| fixed point | `7b515420f749604c1765c2b1edd0d654` |
| archive md5 | `a9ded441846f54f1d02373d3f4da9142` |

Provenance note: the archived binary (md5 7b515420f749604c1765c2b1edd0d654) was captured by
scripts/seed/archive_seed.sh at HEAD d2629f9c; gcc of the archive's self-emission
C reproduces the self-emission fixed point `7b515420f749604c1765c2b1edd0d654` — both are the same
compiler state at HEAD d2629f9c. The compiler self-build uses `-ffast` (user
programs default to `-fsafe`), so the recorded fixed point is the `-ffast`
binary. Rebuild recipes + full canonical flag-set requirement (`gcc -m32
-std=c89 -O0 -Wall -Wno-long-long -Wno-pointer-sign
-Wno-implicit-function-declaration`; the fixed point reproduces ONLY with
`-Wall` present) are recorded in `zig1-seed/SEED_README.txt`.

## 2026-09-15 — seed v17 (HEAD 5daab707)

Seed rotation via scripts/seed/archive_seed.sh. Archive layout: top-level dir
`zig1-seed/` with `zig1`, `gen/` (45 `.c` + 46 `.h` incl.
emitted `zig_special_types.h`, 8355500 bytes), `c_exit.c` (top level),
`runtime/`, `lib/`, `SEED_README.txt`.

| field | value |
|---|---|
| date | 2026-09-15 |
| HEAD | `5daab707` |
| seed binary md5 | `f5ee84800dd32d7c440bb383c10edb55` |
| self-emission C | 45 `.c` + 46 `.h` (8355500 bytes) |
| fixed point | `f5ee84800dd32d7c440bb383c10edb55` |
| archive md5 | `0f04224c55a948f47bc72ec47e0374fb` |

Provenance note: the archived binary (md5 f5ee84800dd32d7c440bb383c10edb55) was captured by
scripts/seed/archive_seed.sh at HEAD 5daab707; gcc of the archive's self-emission
C reproduces the self-emission fixed point `f5ee84800dd32d7c440bb383c10edb55` — both are the same
compiler state at HEAD 5daab707. The compiler self-build uses `-ffast` (user
programs default to `-fsafe`), so the recorded fixed point is the `-ffast`
binary. Rebuild recipes + full canonical flag-set requirement (`gcc -m32
-std=c89 -O0 -Wall -Wno-long-long -Wno-pointer-sign
-Wno-implicit-function-declaration`; the fixed point reproduces ONLY with
`-Wall` present) are recorded in `zig1-seed/SEED_README.txt`.

**9-file std lib install:** this archive's `lib/` carries all 9 std `.zig` (the
8 existing + `std_async.zig`), self-consistent with `build_from_seed.sh`/`archive_seed.sh`.

## 2026-09-15 — seed v16 (HEAD 06c3e195)

Seed rotation via scripts/seed/archive_seed.sh. Archive layout: top-level dir
`zig1-seed/` with `zig1`, `gen/` (45 `.c` + 46 `.h` incl.
emitted `zig_special_types.h`, 8355500 bytes), `c_exit.c` (top level),
`runtime/`, `lib/`, `SEED_README.txt`.

| field | value |
|---|---|
| date | 2026-09-15 |
| HEAD | `06c3e195` |
| seed binary md5 | `f5ee84800dd32d7c440bb383c10edb55` |
| self-emission C | 45 `.c` + 46 `.h` (8355500 bytes) |
| fixed point | `f5ee84800dd32d7c440bb383c10edb55` |
| archive md5 | `e04b4063c554c90a51c34f6736fc1346` |

Provenance note: the archived binary (md5 f5ee84800dd32d7c440bb383c10edb55) was captured by
scripts/seed/archive_seed.sh at HEAD 06c3e195; gcc of the archive's self-emission
C reproduces the self-emission fixed point `f5ee84800dd32d7c440bb383c10edb55` — both are the same
compiler state at HEAD 06c3e195. The compiler self-build uses `-ffast` (user
programs default to `-fsafe`), so the recorded fixed point is the `-ffast`
binary. Rebuild recipes + full canonical flag-set requirement (`gcc -m32
-std=c89 -O0 -Wall -Wno-long-long -Wno-pointer-sign
-Wno-implicit-function-declaration`; the fixed point reproduces ONLY with
`-Wall` present) are recorded in `zig1-seed/SEED_README.txt`.

## 2026-09-15 — seed v15 (HEAD 9013af94)

Seed rotation via scripts/seed/archive_seed.sh. Archive layout: top-level dir
`zig1-seed/` with `zig1`, `gen/` (45 `.c` + 46 `.h` incl.
emitted `zig_special_types.h`, 8337928 bytes), `c_exit.c` (top level),
`runtime/`, `lib/`, `SEED_README.txt`.

| field | value |
|---|---|
| date | 2026-09-15 |
| HEAD | `9013af94` |
| seed binary md5 | `eda943dc1f77a48eae039e39ea4bfe04` |
| self-emission C | 45 `.c` + 46 `.h` (8337928 bytes) |
| fixed point | `eda943dc1f77a48eae039e39ea4bfe04` |
| archive md5 | `cd09877cbc373ad5c8801b93faccf188` |

Provenance note: the archived binary (md5 eda943dc1f77a48eae039e39ea4bfe04) was captured by
scripts/seed/archive_seed.sh at HEAD 9013af94; gcc of the archive's self-emission
C reproduces the self-emission fixed point `eda943dc1f77a48eae039e39ea4bfe04` — both are the same
compiler state at HEAD 9013af94. The compiler self-build uses `-ffast` (user
programs default to `-fsafe`), so the recorded fixed point is the `-ffast`
binary. Rebuild recipes + full canonical flag-set requirement (`gcc -m32
-std=c89 -O0 -Wall -Wno-long-long -Wno-pointer-sign
-Wno-implicit-function-declaration`; the fixed point reproduces ONLY with
`-Wall` present) are recorded in `zig1-seed/SEED_README.txt`.

## 2026-09-14 — seed v14 (HEAD a1c4658c)

Seed rotation via scripts/seed/archive_seed.sh. Archive layout: top-level dir
`zig1-seed/` with `zig1`, `gen/` (42 `.c` + 43 `.h` incl.
emitted `zig_special_types.h`, 7843430 bytes), `c_exit.c` (top level),
`runtime/`, `lib/`, `SEED_README.txt`.

| field | value |
|---|---|
| date | 2026-09-14 |
| HEAD | `a1c4658c` |
| seed binary md5 | `de7137e04d62435c74e7b15281cb4540` |
| self-emission C | 42 `.c` + 43 `.h` (7843430 bytes) |
| fixed point | `de7137e04d62435c74e7b15281cb4540` |
| archive md5 | `9e6c9faad0536191f28eb60c210a0a25` |

Provenance note: the archived binary (md5 de7137e04d62435c74e7b15281cb4540) was captured by
scripts/seed/archive_seed.sh at HEAD a1c4658c; gcc of the archive's self-emission
C reproduces the self-emission fixed point `de7137e04d62435c74e7b15281cb4540` — both are the same
compiler state at HEAD a1c4658c. The compiler self-build uses `-ffast` (user
programs default to `-fsafe`), so the recorded fixed point is the `-ffast`
binary. Rebuild recipes + full canonical flag-set requirement (`gcc -m32
-std=c89 -O0 -Wall -Wno-long-long -Wno-pointer-sign
-Wno-implicit-function-declaration`; the fixed point reproduces ONLY with
`-Wall` present) are recorded in `zig1-seed/SEED_README.txt`.

## 2026-09-14 — seed v13 (HEAD 060be000)

Seed rotation via scripts/seed/archive_seed.sh. Archive layout: top-level dir
`zig1-seed/` with `zig1`, `gen/` (42 `.c` + 43 `.h` incl.
emitted `zig_special_types.h`, 7843430 bytes), `c_exit.c` (top level),
`runtime/`, `lib/`, `SEED_README.txt`.

| field | value |
|---|---|
| date | 2026-09-14 |
| HEAD | `060be000` |
| seed binary md5 | `de7137e04d62435c74e7b15281cb4540` |
| self-emission C | 42 `.c` + 43 `.h` (7843430 bytes) |
| fixed point | `de7137e04d62435c74e7b15281cb4540` |
| archive md5 | `45c6699ff02c534408b8896b284f8b15` |

Provenance note: the archived binary (md5 de7137e04d62435c74e7b15281cb4540) was captured by
scripts/seed/archive_seed.sh at HEAD 060be000; gcc of the archive's self-emission
C reproduces the self-emission fixed point `de7137e04d62435c74e7b15281cb4540` — both are the same
compiler state at HEAD 060be000. The compiler self-build uses `-ffast` (user
programs default to `-fsafe`), so the recorded fixed point is the `-ffast`
binary. Rebuild recipes + full canonical flag-set requirement (`gcc -m32
-std=c89 -O0 -Wall -Wno-long-long -Wno-pointer-sign
-Wno-implicit-function-declaration`; the fixed point reproduces ONLY with
`-Wall` present) are recorded in `zig1-seed/SEED_README.txt`.

## 2026-09-14 — seed v12 (HEAD 921e4f76)

Seed rotation via scripts/seed/archive_seed.sh. Archive layout: top-level dir
`zig1-seed/` with `zig1`, `gen/` (42 `.c` + 43 `.h` incl.
emitted `zig_special_types.h`, 7842184 bytes), `c_exit.c` (top level),
`runtime/`, `lib/`, `SEED_README.txt`.

| field | value |
|---|---|
| date | 2026-09-14 |
| HEAD | `921e4f76` |
| seed binary md5 | `b2eda4a50806962db5e0f90625a7da73` |
| self-emission C | 42 `.c` + 43 `.h` (7842184 bytes) |
| fixed point | `b2eda4a50806962db5e0f90625a7da73` |
| archive md5 | `b6de9b30646e2d5f6cfa2537121329c0` |

Provenance note: the archived binary (md5 b2eda4a50806962db5e0f90625a7da73) was captured by
scripts/seed/archive_seed.sh at HEAD 921e4f76; gcc of the archive's self-emission
C reproduces the self-emission fixed point `b2eda4a50806962db5e0f90625a7da73` — both are the same
compiler state at HEAD 921e4f76. The compiler self-build uses `-ffast` (user
programs default to `-fsafe`), so the recorded fixed point is the `-ffast`
binary. Rebuild recipes + full canonical flag-set requirement (`gcc -m32
-std=c89 -O0 -Wall -Wno-long-long -Wno-pointer-sign
-Wno-implicit-function-declaration`; the fixed point reproduces ONLY with
`-Wall` present) are recorded in `zig1-seed/SEED_README.txt`.

## 2026-09-14 — seed v11 (HEAD 8c48e5d5)

Seed rotation via scripts/seed/archive_seed.sh. Archive layout: top-level dir
`zig1-seed/` with `zig1`, `gen/` (42 `.c` + 43 `.h` incl.
emitted `zig_special_types.h`, 7842052 bytes), `c_exit.c` (top level),
`runtime/`, `lib/`, `SEED_README.txt`.

| field | value |
|---|---|
| date | 2026-09-14 |
| HEAD | `8c48e5d5` |
| seed binary md5 | `cd2259dde73d3a8bc22b25280459edc2` |
| self-emission C | 42 `.c` + 43 `.h` (7842052 bytes) |
| fixed point | `cd2259dde73d3a8bc22b25280459edc2` |
| archive md5 | `62d8bd40cefd5d604b1c66a80ac0749d` |

Provenance note: the archived binary (md5 cd2259dde73d3a8bc22b25280459edc2) was captured by
scripts/seed/archive_seed.sh at HEAD 8c48e5d5; gcc of the archive's self-emission
C reproduces the self-emission fixed point `cd2259dde73d3a8bc22b25280459edc2` — both are the same
compiler state at HEAD 8c48e5d5. The compiler self-build uses `-ffast` (user
programs default to `-fsafe`), so the recorded fixed point is the `-ffast`
binary. Rebuild recipes + full canonical flag-set requirement (`gcc -m32
-std=c89 -O0 -Wall -Wno-long-long -Wno-pointer-sign
-Wno-implicit-function-declaration`; the fixed point reproduces ONLY with
`-Wall` present) are recorded in `zig1-seed/SEED_README.txt`.

## 2026-09-13 — seed v10 (HEAD ab2589e6)

Seed rotation via scripts/seed/archive_seed.sh. Archive layout: top-level dir
`zig1-seed/` with `zig1`, `gen/` (42 `.c` + 43 `.h` incl.
emitted `zig_special_types.h`, 7796270 bytes), `c_exit.c` (top level),
`runtime/`, `lib/`, `SEED_README.txt`.

| field | value |
|---|---|
| date | 2026-09-13 |
| HEAD | `ab2589e6` |
| seed binary md5 | `1467d932a876402f40a56316dfcad0e5` |
| self-emission C | 42 `.c` + 43 `.h` (7796270 bytes) |
| fixed point | `1467d932a876402f40a56316dfcad0e5` |
| archive md5 | `ca18fc9f9af55d58147fcb7ff7a662b6` |

Provenance note: the archived binary (md5 1467d932a876402f40a56316dfcad0e5) was captured by
scripts/seed/archive_seed.sh at HEAD ab2589e6; gcc of the archive's self-emission
C reproduces the self-emission fixed point `1467d932a876402f40a56316dfcad0e5` — both are the same
compiler state at HEAD ab2589e6. The compiler self-build uses `-ffast` (user
programs default to `-fsafe`), so the recorded fixed point is the `-ffast`
binary. Rebuild recipes + full canonical flag-set requirement (`gcc -m32
-std=c89 -O0 -Wall -Wno-long-long -Wno-pointer-sign
-Wno-implicit-function-declaration`; the fixed point reproduces ONLY with
`-Wall` present) are recorded in `zig1-seed/SEED_README.txt`.

## 2026-09-10 — seed v9 (HEAD c599b00e)

Seed rotation via scripts/seed/archive_seed.sh. Archive layout: top-level dir
`zig1-seed/` with `zig1`, `gen/` (42 `.c` + 43 `.h` incl.
emitted `zig_special_types.h`, 7462585 bytes), `c_exit.c` (top level),
`runtime/`, `lib/`, `SEED_README.txt`.

| field | value |
|---|---|
| date | 2026-09-10 |
| HEAD | `c599b00e` |
| seed binary md5 | `4da59bb11270e3c85638bcbb120afc2d` |
| self-emission C | 42 `.c` + 43 `.h` (7462585 bytes) |
| fixed point | `4da59bb11270e3c85638bcbb120afc2d` |
| archive md5 | `7c1421f6312b59c4c449dcf336e32694` |

Provenance note: the archived binary (md5 4da59bb11270e3c85638bcbb120afc2d) was captured by
scripts/seed/archive_seed.sh at HEAD c599b00e; gcc of the archive's self-emission
C reproduces the self-emission fixed point `4da59bb11270e3c85638bcbb120afc2d` — both are the same
compiler state at HEAD c599b00e. Rebuild recipes + full canonical flag-set
requirement (`gcc -m32 -std=c89 -O0 -Wall -Wno-long-long -Wno-pointer-sign
-Wno-implicit-function-declaration`; the fixed point reproduces ONLY with
`-Wall` present) are recorded in `zig1-seed/SEED_README.txt`.

## 2026-09-10 — seed v8 (HEAD 2d364daa)

Seed rotation via scripts/seed/archive_seed.sh. Archive layout: top-level dir
`zig1-seed/` with `zig1`, `gen/` (42 `.c` + 43 `.h` incl.
emitted `zig_special_types.h`, 7460853 bytes), `c_exit.c` (top level),
`runtime/`, `lib/`, `SEED_README.txt`.

| field | value |
|---|---|
| date | 2026-09-10 |
| HEAD | `2d364daa` |
| seed binary md5 | `31973114d5ac93102d7acbd548756363` |
| self-emission C | 42 `.c` + 43 `.h` (7460853 bytes) |
| fixed point | `31973114d5ac93102d7acbd548756363` |
| archive md5 | `242a41f27044c7b9e377424702ebbf74` |

Provenance note: the archived binary (md5 31973114d5ac93102d7acbd548756363) was captured by
scripts/seed/archive_seed.sh at HEAD 2d364daa; gcc of the archive's self-emission
C reproduces the self-emission fixed point `31973114d5ac93102d7acbd548756363` — both are the same
compiler state at HEAD 2d364daa. Rebuild recipes + full canonical flag-set
requirement (`gcc -m32 -std=c89 -O0 -Wall -Wno-long-long -Wno-pointer-sign
-Wno-implicit-function-declaration`; the fixed point reproduces ONLY with
`-Wall` present) are recorded in `zig1-seed/SEED_README.txt`.
**8-file std lib install:** this archive's `lib/` carries all 8 std `.zig`
(`std.zig`, `std_io.zig`, `std_arena.zig`, `std_net.zig`, `std_str.zig`,
`std_mem.zig`, `std_math.zig`, `std_debug.zig`) — self-consistent with
`build_from_seed.sh`.

**EMITEMIT self-emission layout (v8):** `gen/` is the 42-module `.c` + 43 `.h`
emission only; the compiler now emits its runtime/platform support itself
(`zig_compat.h`, `zig_runtime.h`, `net_prelude.h`, `zig_runtime.c`, `zig_pal.c`,
`c_exit.c`) into the output dir, so `archive_seed.sh` excludes those six from
`gen/` — the three support `.c` are staged from `runtime/` + top-level
`c_exit.c` for the archive's self-contained fixed-point rebuild (without the
exclusion they double-link against the runtime trio). Fixed point
`31973114d5ac93102d7acbd548756363`; N-hop from seed v7 `5ea2132f` → hop1
`365c22b7` → hop2 `31973114` → hop3 `31973114` (hop2==hop3). `runtime/` remains
the canonical 5-file set (`net_prelude.h` deliberately not shipped).

## 2026-09-10 — seed v7 (HEAD 49feb878)

Seed rotation via scripts/seed/archive_seed.sh. Archive layout: top-level dir
`zig1-seed/` with `zig1`, `gen/` (42 `.c` + 43 `.h` incl.
emitted `zig_special_types.h`, 7098705 bytes), `c_exit.c` (top level),
`runtime/`, `lib/`, `SEED_README.txt`.

| field | value |
|---|---|
| date | 2026-09-10 |
| HEAD | `49feb878` |
| seed binary md5 | `5ea2132f1ac6662e74b9550c83ea1d82` |
| self-emission C | 42 `.c` + 43 `.h` (7098705 bytes) |
| fixed point | `5ea2132f1ac6662e74b9550c83ea1d82` |
| archive md5 | `954e4c3bd0bbb5ed3f3d4778fc612288` |

Provenance note: the archived binary (md5 5ea2132f1ac6662e74b9550c83ea1d82) was captured by
scripts/seed/archive_seed.sh at HEAD 49feb878; gcc of the archive's self-emission
C reproduces the self-emission fixed point `5ea2132f1ac6662e74b9550c83ea1d82` — both are the same
compiler state at HEAD 49feb878. Rebuild recipes + full canonical flag-set
requirement (`gcc -m32 -std=c89 -O0 -Wall -Wno-long-long -Wno-pointer-sign
-Wno-implicit-function-declaration`; the fixed point reproduces ONLY with
`-Wall` present) are recorded in `zig1-seed/SEED_README.txt`.

**8-file std lib install:** this archive's `lib/` carries all 8 std `.zig`
(`std.zig`, `std_io.zig`, `std_arena.zig`, `std_net.zig`, `std_str.zig`,
`std_mem.zig`, `std_math.zig`, `std_debug.zig`) — `scripts/seed/archive_seed.sh`
extended to match `build_from_seed.sh` (was 4 files), so the archived seed is
self-consistent with the STDLIB plan's canonical lib set.

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
