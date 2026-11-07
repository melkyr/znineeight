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





## 2026-11-07 — seed v144 (HEAD 952b0bb3)

Seed rotation via scripts/seed/archive_seed.sh. Archive layout: top-level dir
`zig1-seed/` with `zig1`, `gen/` (48 `.c` + 49 `.h` incl.
emitted `zig_special_types.h`, 12503400 bytes), `c_exit.c` (top level),
`runtime/`, `lib/`, `SEED_README.txt`.

Phase 3.3 scope: adds the HTTP/2 client stack to the std payload —
`std_tls_io.zig` (nonblocking `TlsIo` socket driver over `std_net`; the
`TlsIoError` name union is the full `TlsError`∪`NetError` set, 31 names),
`std_hpack.zig` (full HPACK decode with canonical Huffman and a ring dynamic
table; literal-only encode), and `std_http2.zig` (frames/settings,
connection/streams/flow control, TLS+ALPN and h2c prior-knowledge adapters,
and the body API). `std_tls` gains ALPN (`alpn_h2`, `tlsAlpnSelected`) and the
opt-in `prefer_chacha20` suite/group ordering; the HTTP/2 path sets it, the
default `false` keeps existing wire fixtures byte-identical. The caller owns an
event loop that selects read **and** write readiness with a bounded timeout and
a stall watchdog and drives the non-suspending `http2Pump`; request coroutines
suspend in `http2Wait`. Streams are leased until `http2Release`; buffered
bodies copy into the caller-owned `out.body` capacity and are capped at 1 MiB
(larger bodies use `ResponseSink`). No server push, no priority scheduling, no
HTTP/2 Upgrade. Local h2 tests use an ephemeral Node 18+ server, print `SKIP`
when Node is absent, and pin argless usage goldens; z9git remains HTTP/1.1.
Win9x evidence is cross-build/emission only (no h2 hardware claim).

| field | value |
|---|---|
| date | 2026-11-07 |
| HEAD | `952b0bb3` |
| seed binary md5 | `cd8d283b917749009961f4445043666b` |
| self-emission C | 48 `.c` + 49 `.h` (12503400 bytes) |
| fixed point | `cd8d283b917749009961f4445043666b` |
| lib manifest | `lib/manifest.md5` (59 std files; md5 `e89c93ee9e7eda25d080eb392dea5d91`) |
| archive md5 | `140bd00dca94a7140e4b5469bf2495a8` |

### Win9x companion seed

| field | value |
|---|---|
| zip | `release/seed/zig1_seed_w9.zip` |
| zip md5 | `e4c21d2c34ffa1766ede224a50048072` |
| win/ C | 52 `.c` + 51 `.h` (full `zig1 -osw` compiler dump; MSVC/OWC no-CRT scripts, aliases, and `build_target.sh` removed; MinGW fallback pair shipped) |
| compiler build scripts | `build_target_crt.bat`, `build_owc_crt.bat` (static CRT; no msvcrt.dll; single EXE) |
| compiler source | `-fsafe`-clean (12 intentional wraps + 3 real safe-mode defects fixed) |
| no-CRT zig1 | deferred to asm_x86; emitted programs still default to no-CRT |
| status | Windows-hosted `std_async.zig:259` field-resolution failure root-caused to a C89 update-stream fseek elision in `spill_store.zig` and fixed; CRT build app-ready |
| lib | 59 std `.zig` + `manifest.md5` |
| HEAD/date | `952b0bb3` / 2026-11-07 |

Provenance note: the archived binary (md5 cd8d283b917749009961f4445043666b) was captured by
scripts/seed/archive_seed.sh from the sf/src tree at packaging base HEAD
952b0bb3; gcc of the archive's self-emission C reproduces the fixed point
`cd8d283b917749009961f4445043666b` — the binary and the C are the same compiler state. If sf/src
carried uncommitted changes at capture time, the packaging base HEAD alone
does not identify that source; the exact source commit is named in that
rotation's seed commit. The compiler self-build uses `-ffast` (user programs
default to `-fsafe`), so the recorded fixed point is the `-ffast` binary.
Rebuild recipes + full canonical flag-set requirement (`gcc -m32
-std=c89 -O0 -Wall -Wno-long-long -Wno-pointer-sign
-Wno-implicit-function-declaration`; the fixed point reproduces ONLY with
`-Wall` present) are recorded in `zig1-seed/SEED_README.txt`.

## 2026-11-07 — seed v143 (HEAD a9c6d323)

Seed rotation via scripts/seed/archive_seed.sh. Archive layout: top-level dir
`zig1-seed/` with `zig1`, `gen/` (48 `.c` + 49 `.h` incl.
emitted `zig_special_types.h`, 12503400 bytes), `c_exit.c` (top level),
`runtime/`, `lib/`, `SEED_README.txt`.

| field | value |
|---|---|
| date | 2026-11-07 |
| HEAD | `a9c6d323` |
| seed binary md5 | `cd8d283b917749009961f4445043666b` |
| self-emission C | 48 `.c` + 49 `.h` (12503400 bytes) |
| fixed point | `cd8d283b917749009961f4445043666b` |
| lib manifest | `lib/manifest.md5` (56 std files; md5 `ec2170933d878c2dda786ba742001be3`) |
| archive md5 | `0f8c0548e7ebf99d04f38e9cf2f169ef` |
| markers | `4245 lines / 49192 B` (`--markers --dump-c89` on `mud_server`; canonical v142 archive compiler+lib baseline `4231 lines / 49045 B`; delta **+14 lines / +147 B**) |
| rotation cause | authorized `std_gpa` medium-decommit-failure fix (std-only; fixed point unchanged from v142) |

Marker cause: the `std_gpa` fix adds `PAGE_POISONED`/`NO_SKIP`,
`unlinkMediumChunk`, the `findFit` skip argument and the retry/poison logic;
because `--dump-c89` includes the `std_gpa` module C, the 8 emission pins and
the `mud_server` marker stream move while the compiler fixed point stays
`cd8d283b…`. The v142 marker record `4232/49084` does not reproduce against the
v142 archive's own compiler+lib (canonical `4231/49045`); that is a pre-existing
record erratum, not a v143 change.

### Win9x companion seed

| field | value |
|---|---|
| zip | `release/seed/zig1_seed_w9.zip` |
| zip md5 | `c553c45e6d44ae0a7f31efb2f068b6c7` |
| win/ C | 52 `.c` + 51 `.h` (full `zig1 -osw` compiler dump; MSVC/OWC no-CRT scripts, aliases, and `build_target.sh` removed; MinGW fallback pair shipped) |
| compiler build scripts | `build_target_crt.bat`, `build_owc_crt.bat` (static CRT; no msvcrt.dll; single EXE) |
| compiler source | `-fsafe`-clean (12 intentional wraps + 3 real safe-mode defects fixed) |
| no-CRT zig1 | deferred to asm_x86; emitted programs still default to no-CRT |
| status | Windows-hosted `std_async.zig:259` field-resolution failure root-caused to a C89 update-stream fseek elision in `spill_store.zig` and fixed; CRT build app-ready |
| lib | 56 std `.zig` + `manifest.md5` |
| HEAD/date | `a9c6d323` / 2026-11-07 |

Provenance note: the archived binary (md5 cd8d283b917749009961f4445043666b) was captured by
scripts/seed/archive_seed.sh from the sf/src tree at packaging base HEAD
a9c6d323; gcc of the archive's self-emission C reproduces the fixed point
`cd8d283b917749009961f4445043666b` — the binary and the C are the same compiler state. If sf/src
carried uncommitted changes at capture time, the packaging base HEAD alone
does not identify that source; the exact source commit is named in that
rotation's seed commit. The compiler self-build uses `-ffast` (user programs
default to `-fsafe`), so the recorded fixed point is the `-ffast` binary.
Rebuild recipes + full canonical flag-set requirement (`gcc -m32
-std=c89 -O0 -Wall -Wno-long-long -Wno-pointer-sign
-Wno-implicit-function-declaration`; the fixed point reproduces ONLY with
`-Wall` present) are recorded in `zig1-seed/SEED_README.txt`.

## 2026-11-07 — seed v142 (HEAD 1518e08c)

Seed rotation via scripts/seed/archive_seed.sh. Archive layout: top-level dir
`zig1-seed/` with `zig1`, `gen/` (48 `.c` + 49 `.h` incl.
emitted `zig_special_types.h`, 12503400 bytes), `c_exit.c` (top level),
`runtime/`, `lib/`, `SEED_README.txt`.

Phase 3.1 scope: adds the general-purpose allocator stack to the std payload —
`std_page.zig`/`std_page_pal.zig` (portable page reservation/commit; optional
`madvise` in `modern` mode; Win32 `pageRelease` passes size 0), `std_gpa.zig`
(TLSF small + page-run medium + large with profiles; default `target64` = 64 KiB
medium cap / 2 MiB chunks / 64 MB target; `align` a power of two in `[8, 4096]`;
`safe_checks` explicit, not implied by `-fsafe`; deterministic `shuffle`), and
`std_pool.zig` (fixed-block pool); `sf/src/std.zig` barrel-exports
`page`/`gpa`/`pool`. Compiler-source changes: conditional
`std_page_prelude.h` emission, `ERR_2006_USE_AFTER_FREE = 3079`, and GPA
analyzer ownership recognition (bare + qualified calls). Limits: TLS is
design-only; `.encrypted` deferred; no compiler allocator migration; no security
or cycle-target claim; Win9x evidence is cross-build/Wine only.

Measured battery (one-time fold-era re-baseline after the barrel exports):
goldens 5/5 byte-identical; frozen-1124 md5 `518eca1a…` 0 movers; live corpus
1265 = 1078 OK / 63 GREEN / 124 FAIL (only the 9 new fixture dirs added); the
8 pins re-recorded (mud `aa438dbe…`/`f2352123…`, gol `443216d2…`/`a7755eb3…`,
lisp `7ba21bae…`/`9ff2b6b2…`, json `a5c0bdda…`/`744853f6…`); markers
`--markers --dump-c89` on `mud_server` 4232 lines / 49084 B (cause: the barrel
interns the new page/gpa/pool declarations — INT +479, DC +138, FE +39, IRP
+12, X +11, RaD12 ordering +114 — plus arena-growth lines and 3 new
`warning[3037]`; 3 INT lines are Task 7's analyzer interning of the gpa call
names); stdlib 365/0 + crosscheck 10/10. The fixed point moved from
`cf68f192…` to `cd8d283b…` by the Tasks 1/7 compiler-source changes only (the
std payload alone does not move it).

| field | value |
|---|---|
| date | 2026-11-07 |
| HEAD | `1518e08c` |
| seed binary md5 | `cd8d283b917749009961f4445043666b` |
| self-emission C | 48 `.c` + 49 `.h` (12503400 bytes) |
| fixed point | `cd8d283b917749009961f4445043666b` |
| lib manifest | `lib/manifest.md5` (56 std files; md5 `a356e5b2a082340e464adf64dc356cd0`) |
| archive md5 | `1bd6201b039b10f0be50d518878dfecb` |

### Win9x companion seed

| field | value |
|---|---|
| zip | `release/seed/zig1_seed_w9.zip` |
| zip md5 | `8f6b813d1141336978b5b30c18cb783b` |
| win/ C | 52 `.c` + 51 `.h` (full `zig1 -osw` compiler dump; MSVC/OWC no-CRT scripts, aliases, and `build_target.sh` removed; MinGW fallback pair shipped) |
| compiler build scripts | `build_target_crt.bat`, `build_owc_crt.bat` (static CRT; no msvcrt.dll; single EXE) |
| compiler source | `-fsafe`-clean (12 intentional wraps + 3 real safe-mode defects fixed) |
| no-CRT zig1 | deferred to asm_x86; emitted programs still default to no-CRT |
| status | Windows-hosted `std_async.zig:259` field-resolution failure root-caused to a C89 update-stream fseek elision in `spill_store.zig` and fixed; CRT build app-ready |
| lib | 56 std `.zig` + `manifest.md5` |
| HEAD/date | `1518e08c` / 2026-11-07 |

Provenance note: the archived binary (md5 cd8d283b917749009961f4445043666b) was captured by
scripts/seed/archive_seed.sh from the sf/src tree at packaging base HEAD
1518e08c; gcc of the archive's self-emission C reproduces the fixed point
`cd8d283b917749009961f4445043666b` — the binary and the C are the same compiler state. If sf/src
carried uncommitted changes at capture time, the packaging base HEAD alone
does not identify that source; the exact source commit is named in that
rotation's seed commit. The compiler self-build uses `-ffast` (user programs
default to `-fsafe`), so the recorded fixed point is the `-ffast` binary.
Rebuild recipes + full canonical flag-set requirement (`gcc -m32
-std=c89 -O0 -Wall -Wno-long-long -Wno-pointer-sign
-Wno-implicit-function-declaration`; the fixed point reproduces ONLY with
`-Wall` present) are recorded in `zig1-seed/SEED_README.txt`.

## 2026-11-06 — seed v141 (HEAD 7dbd5e32)

Seed rotation via scripts/seed/archive_seed.sh. Archive layout: top-level dir
`zig1-seed/` with `zig1`, `gen/` (48 `.c` + 49 `.h` incl.
emitted `zig_special_types.h`, 12473249 bytes), `c_exit.c` (top level),
`runtime/`, `lib/`, `SEED_README.txt`.

Provenance: the archive was built from the `std_http` EOF-flush source
committed at `7dbd5e32`; the earlier `1f3baae3` packaging-base label was stale.

| field | value |
|---|---|
| date | 2026-11-06 |
| HEAD | `7dbd5e32` |
| seed binary md5 | `cf68f192900e7f6618c11e1712b74b3a` |
| self-emission C | 48 `.c` + 49 `.h` (12473249 bytes) |
| fixed point | `cf68f192900e7f6618c11e1712b74b3a` |
| lib manifest | `lib/manifest.md5` (52 std files; md5 `4c979389dceb2d12442e557aaeabf44d`) |
| archive md5 | `3e99af1b8117b982c26b074a1ccd35f7` |

### Win9x companion seed

| field | value |
|---|---|
| zip | `release/seed/zig1_seed_w9.zip` |
| zip md5 | `c45c26f72b6a81b153a9238550456b37` |
| win/ C | 52 `.c` + 51 `.h` (full `zig1 -osw` compiler dump; MSVC/OWC no-CRT scripts, aliases, and `build_target.sh` removed; MinGW fallback pair shipped) |
| compiler build scripts | `build_target_crt.bat`, `build_owc_crt.bat` (static CRT; no msvcrt.dll; single EXE) |
| compiler source | `-fsafe`-clean (12 intentional wraps + 3 real safe-mode defects fixed) |
| no-CRT zig1 | deferred to asm_x86; emitted programs still default to no-CRT |
| status | Windows-hosted `std_async.zig:259` field-resolution failure root-caused to a C89 update-stream fseek elision in `spill_store.zig` and fixed; CRT build app-ready |
| lib | 52 std `.zig` + `manifest.md5` |
| HEAD/date | `7dbd5e32` / 2026-11-06 |

Provenance note: the archived binary (md5 cf68f192900e7f6618c11e1712b74b3a) was captured by
scripts/seed/archive_seed.sh from the sf/src tree at packaging base HEAD
7dbd5e32; gcc of the archive's self-emission C reproduces the fixed point
`cf68f192900e7f6618c11e1712b74b3a` — the binary and the C are the same compiler state. If sf/src
carried uncommitted changes at capture time, the packaging base HEAD alone
does not identify that source; the exact source commit is named in that
rotation's seed commit. The compiler self-build uses `-ffast` (user programs
default to `-fsafe`), so the recorded fixed point is the `-ffast` binary.
Rebuild recipes + full canonical flag-set requirement (`gcc -m32
-std=c89 -O0 -Wall -Wno-long-long -Wno-pointer-sign
-Wno-implicit-function-declaration`; the fixed point reproduces ONLY with
`-Wall` present) are recorded in `zig1-seed/SEED_README.txt`.

## 2026-11-05 — seed v140 (HEAD ae694a0b)

Seed rotation via scripts/seed/archive_seed.sh. Archive layout: top-level dir
`zig1-seed/` with `zig1`, `gen/` (48 `.c` + 49 `.h` incl.
emitted `zig_special_types.h`, 12473249 bytes), `c_exit.c` (top level),
`runtime/`, `lib/`, `SEED_README.txt`.

| field | value |
|---|---|
| date | 2026-11-05 |
| HEAD | `ae694a0b` |
| seed binary md5 | `cf68f192900e7f6618c11e1712b74b3a` |
| self-emission C | 48 `.c` + 49 `.h` (12473249 bytes) |
| fixed point | `cf68f192900e7f6618c11e1712b74b3a` |
| lib manifest | `lib/manifest.md5` (52 std files; md5 `039f205f6f7ac4c881d33a0a5860d4e9`) |
| archive md5 | `534d36e8e516fe710245464743314a66` |

### Win9x companion seed

| field | value |
|---|---|
| zip | `release/seed/zig1_seed_w9.zip` |
| zip md5 | `278fc54adb9f0b8805278e031aad5e0a` |
| win/ C | 52 `.c` + 51 `.h` (full `zig1 -osw` compiler dump; MSVC/OWC no-CRT scripts, aliases, and `build_target.sh` removed; MinGW fallback pair shipped) |
| compiler build scripts | `build_target_crt.bat`, `build_owc_crt.bat` (static CRT; no msvcrt.dll; single EXE) |
| compiler source | `-fsafe`-clean (12 intentional wraps + 3 real safe-mode defects fixed) |
| no-CRT zig1 | deferred to asm_x86; emitted programs still default to no-CRT |
| status | Windows-hosted `std_async.zig:259` field-resolution failure root-caused to a C89 update-stream fseek elision in `spill_store.zig` and fixed; CRT build app-ready |
| lib | 52 std `.zig` + `manifest.md5` |
| HEAD/date | `ae694a0b` / 2026-11-05 |

Provenance note: the archived binary (md5 cf68f192900e7f6618c11e1712b74b3a) was captured by
scripts/seed/archive_seed.sh from the sf/src tree at packaging base HEAD
ae694a0b; gcc of the archive's self-emission C reproduces the fixed point
`cf68f192900e7f6618c11e1712b74b3a` — the binary and the C are the same compiler state. If sf/src
carried uncommitted changes at capture time, the packaging base HEAD alone
does not identify that source; the exact source commit is named in that
rotation's seed commit. The compiler self-build uses `-ffast` (user programs
default to `-fsafe`), so the recorded fixed point is the `-ffast` binary.
Rebuild recipes + full canonical flag-set requirement (`gcc -m32
-std=c89 -O0 -Wall -Wno-long-long -Wno-pointer-sign
-Wno-implicit-function-declaration`; the fixed point reproduces ONLY with
`-Wall` present) are recorded in `zig1-seed/SEED_README.txt`.

## 2026-11-05 — seed v139 (HEAD 6e49471d)

Seed rotation via scripts/seed/archive_seed.sh. Archive layout: top-level dir
`zig1-seed/` with `zig1`, `gen/` (48 `.c` + 49 `.h` incl.
emitted `zig_special_types.h`, 12473249 bytes), `c_exit.c` (top level),
`runtime/`, `lib/`, `SEED_README.txt`.

| field | value |
|---|---|
| date | 2026-11-05 |
| HEAD | `6e49471d` |
| seed binary md5 | `cf68f192900e7f6618c11e1712b74b3a` |
| self-emission C | 48 `.c` + 49 `.h` (12473249 bytes) |
| fixed point | `cf68f192900e7f6618c11e1712b74b3a` |
| lib manifest | `lib/manifest.md5` (52 std files; md5 `ad9abde15b01dd57d9a442b5cbe06685`) |
| archive md5 | `c05bf7d54e9f2a3bb14eabd5e8d22295` |

### Win9x companion seed

| field | value |
|---|---|
| zip | `release/seed/zig1_seed_w9.zip` |
| zip md5 | `7acfa50f5bf4bd749f473bdb0776aad7` |
| win/ C | 52 `.c` + 51 `.h` (full `zig1 -osw` compiler dump; MSVC/OWC no-CRT scripts, aliases, and `build_target.sh` removed; MinGW fallback pair shipped) |
| compiler build scripts | `build_target_crt.bat`, `build_owc_crt.bat` (static CRT; no msvcrt.dll; single EXE) |
| compiler source | `-fsafe`-clean (12 intentional wraps + 3 real safe-mode defects fixed) |
| no-CRT zig1 | deferred to asm_x86; emitted programs still default to no-CRT |
| status | Windows-hosted `std_async.zig:259` field-resolution failure root-caused to a C89 update-stream fseek elision in `spill_store.zig` and fixed; CRT build app-ready |
| lib | 52 std `.zig` + `manifest.md5` |
| HEAD/date | `6e49471d` / 2026-11-05 |

Provenance note: the archived binary (md5 cf68f192900e7f6618c11e1712b74b3a) was captured by
scripts/seed/archive_seed.sh from the sf/src tree at packaging base HEAD
6e49471d; gcc of the archive's self-emission C reproduces the fixed point
`cf68f192900e7f6618c11e1712b74b3a` — the binary and the C are the same compiler state. If sf/src
carried uncommitted changes at capture time, the packaging base HEAD alone
does not identify that source; the exact source commit is named in that
rotation's seed commit. The compiler self-build uses `-ffast` (user programs
default to `-fsafe`), so the recorded fixed point is the `-ffast` binary.
Rebuild recipes + full canonical flag-set requirement (`gcc -m32
-std=c89 -O0 -Wall -Wno-long-long -Wno-pointer-sign
-Wno-implicit-function-declaration`; the fixed point reproduces ONLY with
`-Wall` present) are recorded in `zig1-seed/SEED_README.txt`.

## 2026-11-05 — seed v138 (HEAD d08d07ab)

Seed rotation via scripts/seed/archive_seed.sh. Archive layout: top-level dir
`zig1-seed/` with `zig1`, `gen/` (48 `.c` + 49 `.h` incl.
emitted `zig_special_types.h`, 12473249 bytes), `c_exit.c` (top level),
`runtime/`, `lib/`, `SEED_README.txt`.

| field | value |
|---|---|
| date | 2026-11-05 |
| HEAD | `d08d07ab` |
| seed binary md5 | `cf68f192900e7f6618c11e1712b74b3a` |
| self-emission C | 48 `.c` + 49 `.h` (12473249 bytes) |
| fixed point | `cf68f192900e7f6618c11e1712b74b3a` |
| lib manifest | `lib/manifest.md5` (52 std files; md5 `df2a11962272dfa1cf92c6929e13d937`) |
| archive md5 | `9aef8a6a00bafd3f8f08db96c5ff889b` |

### Win9x companion seed

| field | value |
|---|---|
| zip | `release/seed/zig1_seed_w9.zip` |
| zip md5 | `067fb8fbb05834b5a4207f32bc17125b` |
| win/ C | 52 `.c` + 51 `.h` (full `zig1 -osw` compiler dump; MSVC/OWC no-CRT scripts, aliases, and `build_target.sh` removed; MinGW fallback pair shipped) |
| compiler build scripts | `build_target_crt.bat`, `build_owc_crt.bat` (static CRT; no msvcrt.dll; single EXE) |
| compiler source | `-fsafe`-clean (12 intentional wraps + 3 real safe-mode defects fixed) |
| no-CRT zig1 | deferred to asm_x86; emitted programs still default to no-CRT |
| status | Windows-hosted `std_async.zig:259` field-resolution failure root-caused to a C89 update-stream fseek elision in `spill_store.zig` and fixed; CRT build app-ready |
| lib | 52 std `.zig` + `manifest.md5` |
| HEAD/date | `d08d07ab` / 2026-11-05 |

Provenance note: the archived binary (md5 cf68f192900e7f6618c11e1712b74b3a) was captured by
scripts/seed/archive_seed.sh from the sf/src tree at packaging base HEAD
d08d07ab; gcc of the archive's self-emission C reproduces the fixed point
`cf68f192900e7f6618c11e1712b74b3a` — the binary and the C are the same compiler state. If sf/src
carried uncommitted changes at capture time, the packaging base HEAD alone
does not identify that source; the exact source commit is named in that
rotation's seed commit. The compiler self-build uses `-ffast` (user programs
default to `-fsafe`), so the recorded fixed point is the `-ffast` binary.
Rebuild recipes + full canonical flag-set requirement (`gcc -m32
-std=c89 -O0 -Wall -Wno-long-long -Wno-pointer-sign
-Wno-implicit-function-declaration`; the fixed point reproduces ONLY with
`-Wall` present) are recorded in `zig1-seed/SEED_README.txt`.

## 2026-11-05 — seed v137 (HEAD c4bb4fa2)

Seed rotation via scripts/seed/archive_seed.sh. Archive layout: top-level dir
`zig1-seed/` with `zig1`, `gen/` (48 `.c` + 49 `.h` incl.
emitted `zig_special_types.h`, 12473249 bytes), `c_exit.c` (top level),
`runtime/`, `lib/`, `SEED_README.txt`.

Task 5 fix round 1 adds `std_zstd.zstdFrameContentSize(src: []const u8) ?u64`:
the public exact-content-size reader (header parse, skippable/multi-frame
aware; returns the summed declared size or null) shared by the decoder's
up-front size check and the `z9zstddecomp` CLI (which no longer carries its own
frame/block walker). `zstdDecompress`/`zstdDecompressDict` behavior is
unchanged. This rotation's battery is deliberately **std_zstd-only**: the seven
`repro/mi_matrix/stdlib_zstd_*` fixtures are **7 PASS / 0 FAIL** and the
crosscheck is **10 PASS / 0 FAIL** (the full compiler/std battery is not
re-run here). No compiler source changed, so the fixed point is unchanged and
`lib/` remains **52** std `.zig`.

| field | value |
|---|---|
| date | 2026-11-05 |
| HEAD | `c4bb4fa2` |
| seed binary md5 | `cf68f192900e7f6618c11e1712b74b3a` |
| self-emission C | 48 `.c` + 49 `.h` (12473249 bytes) |
| fixed point | `cf68f192900e7f6618c11e1712b74b3a` |
| lib manifest | `lib/manifest.md5` (52 std files; md5 `de5e037d08e4e45b0dc522dea976ecb5`) |
| archive md5 | `1ba4a6904f2d241aad9a92fbae8c9609` |

### Win9x companion seed

| field | value |
|---|---|
| zip | `release/seed/zig1_seed_w9.zip` |
| zip md5 | `0754180d161823e30681347f3c9a925c` |
| win/ C | 52 `.c` + 51 `.h` (full `zig1 -osw` compiler dump; MSVC/OWC no-CRT scripts, aliases, and `build_target.sh` removed; MinGW fallback pair shipped) |
| compiler build scripts | `build_target_crt.bat`, `build_owc_crt.bat` (static CRT; no msvcrt.dll; single EXE) |
| compiler source | `-fsafe`-clean (12 intentional wraps + 3 real safe-mode defects fixed) |
| no-CRT zig1 | deferred to asm_x86; emitted programs still default to no-CRT |
| status | Windows-hosted `std_async.zig:259` field-resolution failure root-caused to a C89 update-stream fseek elision in `spill_store.zig` and fixed; CRT build app-ready |
| lib | 52 std `.zig` + `manifest.md5` |
| HEAD/date | `c4bb4fa2` / 2026-11-05 |

Provenance note: the archived binary (md5 cf68f192900e7f6618c11e1712b74b3a) was captured by
scripts/seed/archive_seed.sh from the sf/src tree at packaging base HEAD
c4bb4fa2; gcc of the archive's self-emission C reproduces the fixed point
`cf68f192900e7f6618c11e1712b74b3a` — the binary and the C are the same compiler state. If sf/src
carried uncommitted changes at capture time, the packaging base HEAD alone
does not identify that source; the exact source commit is named in that
rotation's seed commit. The compiler self-build uses `-ffast` (user programs
default to `-fsafe`), so the recorded fixed point is the `-ffast` binary.
Rebuild recipes + full canonical flag-set requirement (`gcc -m32
-std=c89 -O0 -Wall -Wno-long-long -Wno-pointer-sign
-Wno-implicit-function-declaration`; the fixed point reproduces ONLY with
`-Wall` present) are recorded in `zig1-seed/SEED_README.txt`.

## 2026-11-04 — seed v136 (HEAD 315939a2)

Seed rotation via scripts/seed/archive_seed.sh. Archive layout: top-level dir
`zig1-seed/` with `zig1`, `gen/` (48 `.c` + 49 `.h` incl.
emitted `zig_special_types.h`, 12473249 bytes), `c_exit.c` (top level),
`runtime/`, `lib/`, `SEED_README.txt`.

Milestone-1 closeout for Phase 3 (missing libraries): `std_zstd` now supports
RFC 8878 dictionaries via `zstdDecompressDict` (full RFC 8878;
`zstdDecompress` itself is unchanged and still rejects dict frames), the new
`std_deflate` module provides an inflater (`inflateRaw` / `inflateZlib`, both
with the mandatory `used` out-param), and `std_http` gains POST plus a
streaming response sink (`httpPostOver`, `httpPostStreamOver`, `ResponseSink`,
and the `post` convenience call). No compiler source changed, so the fixed
point is unchanged. Full std battery at rotation: **356 PASS / 0 FAIL** over
356 fixtures plus crosscheck **10 PASS / 0 FAIL** over 10 modules; `lib/`
holds **52** std `.zig` (adds `std_deflate.zig`).

| field | value |
|---|---|
| date | 2026-11-04 |
| HEAD | `315939a2` |
| seed binary md5 | `cf68f192900e7f6618c11e1712b74b3a` |
| self-emission C | 48 `.c` + 49 `.h` (12473249 bytes) |
| fixed point | `cf68f192900e7f6618c11e1712b74b3a` |
| lib manifest | `lib/manifest.md5` (52 std files; md5 `1906480f9b15dcd4e152cf8c247f2e61`) |
| archive md5 | `d0f1d191689ad996bedcade688de1f2b` |

### Win9x companion seed

| field | value |
|---|---|
| zip | `release/seed/zig1_seed_w9.zip` |
| zip md5 | `8fc02b8123ab04fac77ab8932ac60beb` |
| win/ C | 52 `.c` + 51 `.h` (full `zig1 -osw` compiler dump; MSVC/OWC no-CRT scripts, aliases, and `build_target.sh` removed; MinGW fallback pair shipped) |
| compiler build scripts | `build_target_crt.bat`, `build_owc_crt.bat` (static CRT; no msvcrt.dll; single EXE) |
| compiler source | `-fsafe`-clean (12 intentional wraps + 3 real safe-mode defects fixed) |
| no-CRT zig1 | deferred to asm_x86; emitted programs still default to no-CRT |
| status | Windows-hosted `std_async.zig:259` field-resolution failure root-caused to a C89 update-stream fseek elision in `spill_store.zig` and fixed; CRT build app-ready |
| lib | 52 std `.zig` + `manifest.md5` |
| HEAD/date | `315939a2` / 2026-11-04 |

Provenance note: the archived binary (md5 cf68f192900e7f6618c11e1712b74b3a) was captured by
scripts/seed/archive_seed.sh from the sf/src tree at packaging base HEAD
315939a2; gcc of the archive's self-emission C reproduces the fixed point
`cf68f192900e7f6618c11e1712b74b3a` — the binary and the C are the same compiler state. If sf/src
carried uncommitted changes at capture time, the packaging base HEAD alone
does not identify that source; the exact source commit is named in that
rotation's seed commit. The compiler self-build uses `-ffast` (user programs
default to `-fsafe`), so the recorded fixed point is the `-ffast` binary.
Rebuild recipes + full canonical flag-set requirement (`gcc -m32
-std=c89 -O0 -Wall -Wno-long-long -Wno-pointer-sign
-Wno-implicit-function-declaration`; the fixed point reproduces ONLY with
`-Wall` present) are recorded in `zig1-seed/SEED_README.txt`.

## 2026-11-04 — seed v135 (HEAD 5f901b4f)

Seed rotation via scripts/seed/archive_seed.sh. Archive layout: top-level dir
`zig1-seed/` with `zig1`, `gen/` (48 `.c` + 49 `.h` incl.
emitted `zig_special_types.h`, 12473249 bytes), `c_exit.c` (top level),
`runtime/`, `lib/`, `SEED_README.txt`.

| field | value |
|---|---|
| date | 2026-11-04 |
| HEAD | `5f901b4f` |
| seed binary md5 | `cf68f192900e7f6618c11e1712b74b3a` |
| self-emission C | 48 `.c` + 49 `.h` (12473249 bytes) |
| fixed point | `cf68f192900e7f6618c11e1712b74b3a` |
| lib manifest | `lib/manifest.md5` (51 std files; md5 `62008632c1f057c42b04bf5883f6da5d`) |
| archive md5 | `c01a8261aa9b9d84f2d414724011b3db` |

### Win9x companion seed

| field | value |
|---|---|
| zip | `release/seed/zig1_seed_w9.zip` |
| zip md5 | `49242d99702f0521ac5d06a29c2d96c3` |
| win/ C | 52 `.c` + 51 `.h` (full `zig1 -osw` compiler dump; MSVC/OWC no-CRT scripts, aliases, and `build_target.sh` removed; MinGW fallback pair shipped) |
| compiler build scripts | `build_target_crt.bat`, `build_owc_crt.bat` (static CRT; no msvcrt.dll; single EXE) |
| compiler source | `-fsafe`-clean (12 intentional wraps + 3 real safe-mode defects fixed) |
| no-CRT zig1 | deferred to asm_x86; emitted programs still default to no-CRT |
| status | Windows-hosted `std_async.zig:259` field-resolution failure root-caused to a C89 update-stream fseek elision in `spill_store.zig` and fixed; CRT build app-ready |
| lib | 51 std `.zig` + `manifest.md5` |
| HEAD/date | `5f901b4f` / 2026-11-04 |

Provenance note: the archived binary (md5 cf68f192900e7f6618c11e1712b74b3a) was captured by
scripts/seed/archive_seed.sh from the sf/src tree at packaging base HEAD
5f901b4f; gcc of the archive's self-emission C reproduces the fixed point
`cf68f192900e7f6618c11e1712b74b3a` — the binary and the C are the same compiler state. If sf/src
carried uncommitted changes at capture time, the packaging base HEAD alone
does not identify that source; the exact source commit is named in that
rotation's seed commit. The compiler self-build uses `-ffast` (user programs
default to `-fsafe`), so the recorded fixed point is the `-ffast` binary.
Rebuild recipes + full canonical flag-set requirement (`gcc -m32
-std=c89 -O0 -Wall -Wno-long-long -Wno-pointer-sign
-Wno-implicit-function-declaration`; the fixed point reproduces ONLY with
`-Wall` present) are recorded in `zig1-seed/SEED_README.txt`.

### Battery at rotation (v135)

- **Corpus:** live 1240 dirs = 1053 OK / 63 GREEN / 124 FAIL / 0 ICE /
  0 CRASH; class md5 `d9011c94cdbae01aa1765ca1047656a4`. The +28 dirs vs v134
  are the additive switch/enum/paren/bool repros (5 + 8 + 10 + 5); removing
  them reproduces the v134 live class file exactly (1212 = 1032 OK / 59 GREEN /
  121 FAIL, md5 `f61943c5459b6dd27d342d5600b6dd0d`), so there are **0
  existing-dir movers**.
- **Frozen-1124:** 1124 lines, md5 `518eca1a9b5d3e1cc5a48abce214abd8`,
  950 OK / 58 GREEN / 116 FAIL, **0 movers**.
- **Goldens 5/5 byte-identical; 8 dump pins 8/8 unchanged; markers 3397 lines /
  39012 B (unchanged); examples 26/26; stdlib 342/0 + crosscheck 10/10;
  `check_emit_support` 8/8; all compiler gates green** (including the extended
  `gate_switch_width.sh`, `gate_lower_depth.sh` cases 16-29, and
  `gate_warn_clean.sh` scope (c)).
- **Known (not gated):** the compiler's own self-emission produces 18
  `-Werror` diagnostics in 8 TUs under gcc `-O2`/`-O3` (array-bounds /
  stringop-overflow behind existing `pal_trap()` guards, and optional-payload
  `maybe-uninitialized`); identical on the archived v134 compiler, i.e.
  pre-existing and behavior-neutral. The wave's own emitted C (hello, lisp,
  runtime, and all 16 new repros) is clean at `-O2`/`-O3`. Deferred; the
  shipped MSVC/OWC scripts carry no `/WX`/`-Werror`.

## 2026-11-04 — seed v134 (HEAD 38a18deb)

Seed rotation via scripts/seed/archive_seed.sh. Archive layout: top-level dir
`zig1-seed/` with `zig1`, `gen/` (48 `.c` + 49 `.h` incl.
emitted `zig_special_types.h`, 12473249 bytes), `c_exit.c` (top level),
`runtime/`, `lib/`, `SEED_README.txt`.

Task 8b adds the `std_http` large-repo helpers: `httpGetHeadersOver` (buffered
GET with caller headers, including `Range` for static servers),
`httpGetStreamOver` (GET body streamed to a `ResponseSink`),
`RequestSource` + `httpPostStreamBodyOver` (a POST request body streamed from a
caller source with a declared `Content-Length` and the same streamed response
path). The existing GET/POST signatures and behavior are unchanged, no
compiler source changed, so the fixed point is unchanged and `lib/` remains
**52** std `.zig` (`std_http.zig` updated, no new module). The targeted
`stdlib_http_*` fixtures are **8 PASS / 0 FAIL** and the crosscheck is
**10 PASS / 0 FAIL** (the full compiler/std battery is not re-run here).


| field | value |
|---|---|
| date | 2026-11-04 |
| HEAD | `38a18deb` |
| seed binary md5 | `8dff7650e83df66d96388b3d21c489ea` |
| self-emission C | 48 `.c` + 49 `.h` (12457821 bytes) |
| fixed point | `8dff7650e83df66d96388b3d21c489ea` |
| lib manifest | `lib/manifest.md5` (51 std files; md5 `62008632c1f057c42b04bf5883f6da5d`) |
| archive md5 | `c978404ed9662fd7adc0c804aae8ae1d` |

### Win9x companion seed

| field | value |
|---|---|
| zip | `release/seed/zig1_seed_w9.zip` |
| zip md5 | `3203c96fcc21d5fe2b5b931e4cb103c7` |
| win/ C | 52 `.c` + 51 `.h` (full `zig1 -osw` compiler dump; MSVC/OWC no-CRT scripts, aliases, and `build_target.sh` removed; MinGW fallback pair shipped) |
| compiler build scripts | `build_target_crt.bat`, `build_owc_crt.bat` (static CRT; no msvcrt.dll; single EXE) |
| compiler source | `-fsafe`-clean (12 intentional wraps + 3 real safe-mode defects fixed) |
| no-CRT zig1 | deferred to asm_x86; emitted programs still default to no-CRT |
| status | Windows-hosted `std_async.zig:259` field-resolution failure root-caused to a C89 update-stream fseek elision in `spill_store.zig` and fixed; CRT build app-ready |
| lib | 51 std `.zig` + `manifest.md5` |
| HEAD/date | `38a18deb` / 2026-11-04 |

Provenance note: the archived binary (md5 8dff7650e83df66d96388b3d21c489ea) was captured by
scripts/seed/archive_seed.sh from the sf/src tree at packaging base HEAD
38a18deb; gcc of the archive's self-emission C reproduces the fixed point
`8dff7650e83df66d96388b3d21c489ea` — the binary and the C are the same compiler state. If sf/src
carried uncommitted changes at capture time, the packaging base HEAD alone
does not identify that source; the exact source commit is named in that
rotation's seed commit. The compiler self-build uses `-ffast` (user programs
default to `-fsafe`), so the recorded fixed point is the `-ffast` binary.
Rebuild recipes + full canonical flag-set requirement (`gcc -m32
-std=c89 -O0 -Wall -Wno-long-long -Wno-pointer-sign
-Wno-implicit-function-declaration`; the fixed point reproduces ONLY with
`-Wall` present) are recorded in `zig1-seed/SEED_README.txt`.

### Changes in this rotation (switch emission fixes)

- **64-bit `switch` lowering:** a `switch` whose condition is a 64-bit
  integer now lowers to a portable `if` / `else if` / `else` chain instead of
  a C `switch` on a 64-bit controlling expression (OpenWatcom rejects the
  latter). 32-bit conditions keep the existing C `switch` emission
  byte-identically; the exact 64-bit case literals use the `Z98_U64_C` /
  `Z98_I64_C` forms (including `0xFFFFFFFFFFFFFFFF`).
- **Negative integer case items:** negative literals, module-level named
  `const` items and negative range endpoints now resolve and match on signed
  integer conditions (32-bit signed labels; signed forms in the 64-bit chain).
  A negative case item on an unsigned condition is a clean level-0
  `error[3062]` rejection (rc 2, 0 `.c`). Function-local `const` case items
  remain the documented limitation.
- **Signed enum backings / negative discriminants:** `enum(iN)` declarations
  with negative discriminants are accepted (including `i32`/`i64` minima and
  module-const `const X: E = .A` shorthand) with signed case labels; an
  unsigned backing with a negative discriminant rejects with the same
  `error[3062]` family. Local/inline enum validation was widened to match.
  No new std file, so `lib/` stays at 51 std `.zig` and the manifest pin is
  unchanged.

### Battery at rotation (v134)

- **Corpus:** live 1212 dirs = 1032 OK / 59 GREEN / 121 FAIL / 0 ICE /
  0 CRASH; class md5 `f61943c5459b6dd27d342d5600b6dd0d`. The +16 dirs vs v133
  are the additive `switch_*` / `local_enum_*` repros (12 OK, 1 GREEN,
  3 clean `error[3062]` rejects counted FAIL by the canonical classifier);
  removing them reproduces the v133 live class file exactly (1196 = 1020 OK /
  58 GREEN / 118 FAIL, md5 `dd67bcdfb00162cc000205060925b6d7`), so there are
  **0 existing-dir movers**.
- **Frozen-1124:** 1124 lines, md5 `518eca1a9b5d3e1cc5a48abce214abd8`,
  950 OK / 58 GREEN / 116 FAIL, **0 movers**.
- **Goldens 5/5 byte-identical:** gol `fcbf7e7cead5082f0a8caadd5a8f0ff9`,
  lisp basic `b3d9f8974da24ddbf9d389f3d7d97322`, lisp canonical
  `96654b3910a54d8bb7ec3ddfc0f26c6a`, json `8bda3d5a1ec07d14a301bc343df32bf8`,
  mud server/client `66c8f0abb926cca7baf9a0d1692ab318` /
  `93147d0f0bbd983a9d844fea8b7a6fa7`.
- **8 dump pins unchanged:** 8/8 byte-identical.
- **Markers:** 3397 lines / 39012 B (unchanged).
- **Examples:** 26/26 build and 26/26 run with the expected rc set.
- **stdlib:** 342 PASS / 0 FAIL; crosscheck 10 PASS / 0 FAIL.
- **`check_emit_support.sh`:** 8/8 support files byte-identical.
- **Closure:** rebuild from this archive closes at hop1 == hop2 ==
  `8dff7650e83df66d96388b3d21c489ea`.

## 2026-11-03 — seed v133 (HEAD 0b35199f)

Seed rotation via scripts/seed/archive_seed.sh. Archive layout: top-level dir
`zig1-seed/` with `zig1`, `gen/` (48 `.c` + 49 `.h` incl.
emitted `zig_special_types.h`, 12361596 bytes), `c_exit.c` (top level),
`runtime/`, `lib/`, `SEED_README.txt`.

| field | value |
|---|---|
| date | 2026-11-03 |
| HEAD | `0b35199f` |
| seed binary md5 | `108fed5c1d143d0d905fdb3e2fd120e9` |
| self-emission C | 48 `.c` + 49 `.h` (12361596 bytes) |
| fixed point | `108fed5c1d143d0d905fdb3e2fd120e9` |
| lib manifest | `lib/manifest.md5` (51 std files; md5 `62008632c1f057c42b04bf5883f6da5d`) |
| archive md5 | `f833c5ee355681927aedf5881450221d` |

### Win9x companion seed

| field | value |
|---|---|
| zip | `release/seed/zig1_seed_w9.zip` |
| zip md5 | `2b516af68400ec886fc1ee8a5dbc961d` |
| win/ C | 52 `.c` + 51 `.h` (full `zig1 -osw` compiler dump; MSVC/OWC no-CRT scripts, aliases, and `build_target.sh` removed; MinGW fallback pair shipped) |
| compiler build scripts | `build_target_crt.bat`, `build_owc_crt.bat` (static CRT; no msvcrt.dll; single EXE) |
| compiler source | `-fsafe`-clean (12 intentional wraps + 3 real safe-mode defects fixed) |
| no-CRT zig1 | deferred to asm_x86; emitted programs still default to no-CRT |
| status | Windows-hosted `std_async.zig:259` field-resolution failure root-caused to a C89 update-stream fseek elision in `spill_store.zig` and fixed; CRT build app-ready |
| lib | 51 std `.zig` + `manifest.md5` |
| HEAD/date | `0b35199f` / 2026-11-03 |

### Changes in this rotation (z9play/z9torr optimization)

- **`std_fft`:** new standalone `sf/src/std_fft.zig` (iterative split-radix
  complex FFT, imported directly as `@import("std_fft.zig")` and deliberately
  not re-exported from `std.zig`) is now shipped in `lib/`; the
  `stdlib_fft_basic` / `stdlib_fft_inverse` / `stdlib_fft_radix` fixtures raise
  the std gate to 342. No compiler or barrel change.
- **z9play:** FFT-based IMDCT using `std_fft` plus cached window/slope tables;
  the 2-LSB / RMS golden is unchanged and the release recipe uses `-ffast`.
- **z9torr:** O(1) piece/block accounting counters replace the per-block scans;
  downloaded bytes are unchanged and the release recipe uses `-ffast`.
- **CLI docs:** the z9play and z9torr `-h` text documents exit codes, the
  log/save paths and the WAV sink. No new flags.
- `lib/` changed only by adding `std_fft.zig`, so the manifest pin moved to
  `62008632c1f057c42b04bf5883f6da5d`; the compiler fixed point stayed at
  `108fed5c1d143d0d905fdb3e2fd120e9` (the barrel is untouched).

### Battery at rotation (v133)

- **Corpus:** live 1196 dirs = 1020 OK / 58 GREEN / 118 FAIL / 0 ICE / 0 CRASH;
  class md5 `dd67bcdfb00162cc000205060925b6d7` (v132 live was 1193 = 1017 OK /
  58 GREEN / 118 FAIL; the +3 OK are the new `std_fft` fixtures).
- **Frozen-1124:** 1124 lines, md5 `518eca1a9b5d3e1cc5a48abce214abd8`,
  950 OK / 58 GREEN / 116 FAIL, 0 movers.
- **Goldens 5/5 byte-identical:** gol `fcbf7e7cead5082f0a8caadd5a8f0ff9`,
  lisp basic `b3d9f8974da24ddbf9d389f3d7d97322`, lisp canonical
  `96654b3910a54d8bb7ec3ddfc0f26c6a`, json `8bda3d5a1ec07d14a301bc343df32bf8`,
  mud server/client `66c8f0abb926cca7baf9a0d1692ab318` /
  `93147d0f0bbd983a9d844fea8b7a6fa7`.
- **8 dump pins unchanged:** 8/8 byte-identical (no compiler/barrel change).
- **Markers:** 3397 lines / 39012 B (unchanged).
- **Examples:** 26/26 build and 26/26 run with the expected rc set
  (`z9play`/`z9torr` usage text grew in the CLI-docs change; rc remains 1).
- **stdlib:** 342 PASS / 0 FAIL; crosscheck 10 PASS / 0 FAIL.
- **`check_emit_support.sh`:** 8/8 support files byte-identical.
- **Closure:** rebuild from this archive closes at hop1 == hop2 ==
  `108fed5c1d143d0d905fdb3e2fd120e9`.

Provenance note: the archived binary (md5 108fed5c1d143d0d905fdb3e2fd120e9) was captured by
scripts/seed/archive_seed.sh from the sf/src tree at packaging base HEAD
0b35199f; gcc of the archive's self-emission C reproduces the fixed point
`108fed5c1d143d0d905fdb3e2fd120e9` — the binary and the C are the same compiler state. If sf/src
carried uncommitted changes at capture time, the packaging base HEAD alone
does not identify that source; the exact source commit is named in that
rotation's seed commit. The compiler self-build uses `-ffast` (user programs
default to `-fsafe`), so the recorded fixed point is the `-ffast` binary.
Rebuild recipes + full canonical flag-set requirement (`gcc -m32
-std=c89 -O0 -Wall -Wno-long-long -Wno-pointer-sign
-Wno-implicit-function-declaration`; the fixed point reproduces ONLY with
`-Wall` present) are recorded in `zig1-seed/SEED_README.txt`.

## 2026-11-03 — seed v132 (HEAD 8f2269c3)

Seed rotation via scripts/seed/archive_seed.sh. Archive layout: top-level dir
`zig1-seed/` with `zig1`, `gen/` (48 `.c` + 49 `.h` incl.
emitted `zig_special_types.h`, 12361596 bytes), `c_exit.c` (top level),
`runtime/`, `lib/`, `SEED_README.txt`.

| field | value |
|---|---|
| date | 2026-11-03 |
| HEAD | `8f2269c3` |
| seed binary md5 | `108fed5c1d143d0d905fdb3e2fd120e9` |
| self-emission C | 48 `.c` + 49 `.h` (12361596 bytes) |
| fixed point | `108fed5c1d143d0d905fdb3e2fd120e9` |
| lib manifest | `lib/manifest.md5` (50 std files; md5 `a7ada3edfa99ba091a5ef1096550b908`) |
| archive md5 | `9244ae831cb41ee9b71b1187a9f23820` |

### Win9x companion seed

| field | value |
|---|---|
| zip | `release/seed/zig1_seed_w9.zip` |
| zip md5 | `2cfd893244ff3a7fbc317bb4221babdf` |
| win/ C | 52 `.c` + 51 `.h` (full `zig1 -osw` compiler dump; MSVC/OWC no-CRT scripts, aliases, and `build_target.sh` removed; MinGW fallback pair shipped) |
| compiler build scripts | `build_target_crt.bat`, `build_owc_crt.bat` (static CRT; no msvcrt.dll; single EXE) |
| compiler source | `-fsafe`-clean (12 intentional wraps + 3 real safe-mode defects fixed) |
| no-CRT zig1 | deferred to asm_x86; emitted programs still default to no-CRT |
| status | Windows-hosted `std_async.zig:259` field-resolution failure root-caused to a C89 update-stream fseek elision in `spill_store.zig` and fixed; CRT build app-ready |
| lib | 50 std `.zig` + `manifest.md5` |
| HEAD/date | `8f2269c3` / 2026-11-03 |

### Changes in this rotation (0.21.1 Win9x hotfix)

- **MinGW emitted links:** partial/chunk links use `-nostdlib`; the no-CRT
  final link adds `-lwinmm` (the CRT branch and `build_target.sh` already did).
- **no-CRT runtime shims:** `strlen`/`memcpy`/`memset`/`strncmp` use volatile
  pointers so `-O2` cannot rewrite the loops into self-calls; gated by a static
  self-call check plus a Wine `-O2` smoke.
- **GUI (`std_gfx_pal`):** the C `WndProc` shim is removed (register
  `DefWindowProcA`; poll `GetClientRect`/`IsWindow`); DirectDraw is loaded
  dynamically with `LoadLibraryA("ddraw.dll")`/`GetProcAddress` (no static
  `DDRAW.DLL` import; GDI fallback kept); MSVC/MinGW GUI link lines add
  `user32`/`gdi32`.
- **z9play:** live console output via direct `fflush(NULL)` (no-CRT `fflush`
  shim added); `--wav` prints start + periodic progress lines.
- **Docs:** every `examples/z98/*/README.md` now carries Linux + Windows zig1
  build recipes.
- `lib/` payload changed only through `std_gfx_pal.zig`, so the manifest pin
  moved to `a7ada3edfa99ba091a5ef1096550b908`; compiler fixed point moved from
  v131 `cc15a6f3…` to `108fed5c…`. No language or CLI change.

Provenance note: the archived binary (md5 108fed5c1d143d0d905fdb3e2fd120e9) was captured by
scripts/seed/archive_seed.sh from the sf/src tree at packaging base HEAD
8f2269c3; gcc of the archive's self-emission C reproduces the fixed point
`108fed5c1d143d0d905fdb3e2fd120e9` — the binary and the C are the same compiler state. If sf/src
carried uncommitted changes at capture time, the packaging base HEAD alone
does not identify that source; the exact source commit is named in that
rotation's seed commit. The compiler self-build uses `-ffast` (user programs
default to `-fsafe`), so the recorded fixed point is the `-ffast` binary.
Rebuild recipes + full canonical flag-set requirement (`gcc -m32
-std=c89 -O0 -Wall -Wno-long-long -Wno-pointer-sign
-Wno-implicit-function-declaration`; the fixed point reproduces ONLY with
`-Wall` present) are recorded in `zig1-seed/SEED_README.txt`.

## 2026-11-02 — seed v131 (HEAD b1da327a)

Seed rotation via scripts/seed/archive_seed.sh. Archive layout: top-level dir
`zig1-seed/` with `zig1`, `gen/` (48 `.c` + 49 `.h` incl.
emitted `zig_special_types.h`, 12355182 bytes), `c_exit.c` (top level),
`runtime/`, `lib/`, `SEED_README.txt`.

| field | value |
|---|---|
| date | 2026-11-02 |
| HEAD | `b1da327a` |
| seed binary md5 | `cc15a6f3fd0e6e28b8e2fe116665ff86` |
| self-emission C | 48 `.c` + 49 `.h` (12355182 bytes) |
| fixed point | `cc15a6f3fd0e6e28b8e2fe116665ff86` |
| lib manifest | `lib/manifest.md5` (50 std files; md5 `8b78593a7dabb86f9f01cd9e7994ab9f`) |
| archive md5 | `54980ef2c404954fd7613d4f5f7907b2` |

### Win9x companion seed

| field | value |
|---|---|
| zip | `release/seed/zig1_seed_w9.zip` |
| zip md5 | `ae8d3a041b85b5b9842e4e3feb043a2a` |
| win/ C | 52 `.c` + 51 `.h` (full `zig1 -osw` compiler dump; MSVC/OWC no-CRT scripts, aliases, and `build_target.sh` removed; MinGW fallback pair shipped) |
| compiler build scripts | `build_target_crt.bat`, `build_owc_crt.bat` (static CRT; no msvcrt.dll; single EXE) |
| compiler source | `-fsafe`-clean (12 intentional wraps + 3 real safe-mode defects fixed) |
| no-CRT zig1 | deferred to asm_x86; emitted programs still default to no-CRT |
| status | Windows-hosted `std_async.zig:259` field-resolution failure root-caused to a C89 update-stream fseek elision in `spill_store.zig` and fixed; CRT build app-ready |
| lib | 50 std `.zig` + `manifest.md5` |
| HEAD/date | `b1da327a` / 2026-11-02 |

Provenance note: the archived binary (md5 cc15a6f3fd0e6e28b8e2fe116665ff86) was captured by
scripts/seed/archive_seed.sh from the sf/src tree at packaging base HEAD
b1da327a; gcc of the archive's self-emission C reproduces the fixed point
`cc15a6f3fd0e6e28b8e2fe116665ff86` — the binary and the C are the same compiler state. If sf/src
carried uncommitted changes at capture time, the packaging base HEAD alone
does not identify that source; the exact source commit is named in that
rotation's seed commit. The compiler self-build uses `-ffast` (user programs
default to `-fsafe`), so the recorded fixed point is the `-ffast` binary.
Rebuild recipes + full canonical flag-set requirement (`gcc -m32
-std=c89 -O0 -Wall -Wno-long-long -Wno-pointer-sign
-Wno-implicit-function-declaration`; the fixed point reproduces ONLY with
`-Wall` present) are recorded in `zig1-seed/SEED_README.txt`.

## 2026-11-02 — seed v130 (HEAD 2f0b9d29)

Seed rotation via scripts/seed/archive_seed.sh. Archive layout: top-level dir
`zig1-seed/` with `zig1`, `gen/` (48 `.c` + 49 `.h` incl.
emitted `zig_special_types.h`, 12351612 bytes), `c_exit.c` (top level),
`runtime/`, `lib/`, `SEED_README.txt`.

| field | value |
|---|---|
| date | 2026-11-02 |
| capture HEAD | `2f0b9d29` |
| compiler source commit | `efdb269b` (folded-arm flag fix; gate in `2f0b9d29`) |
| seed binary md5 | `a452e713f869f6d7f8c4894c2acb67e5` |
| self-emission C | 48 `.c` + 49 `.h` (12351612 bytes) |
| fixed point | `a452e713f869f6d7f8c4894c2acb67e5` |
| lib manifest | `lib/manifest.md5` (50 std files; md5 `8b78593a7dabb86f9f01cd9e7994ab9f`) |
| archive md5 | `c9198e2f0dd7ac4e05d19442aa53ec05` |

### Win9x companion seed

| field | value |
|---|---|
| zip | `release/seed/zig1_seed_w9.zip` |
| zip md5 | `baf39d8ba30042d39beff0e1a80ede16` |
| win/ C | 52 `.c` + 51 `.h` (full `zig1 -osw` compiler dump; MSVC/OWC no-CRT scripts, aliases, and `build_target.sh` removed; MinGW fallback pair shipped) |
| compiler build scripts | `build_target_crt.bat`, `build_owc_crt.bat` (static CRT; no msvcrt.dll; single EXE) |
| compiler source | `-fsafe`-clean (12 intentional wraps + 3 real safe-mode defects fixed) |
| no-CRT zig1 | deferred to asm_x86; emitted programs still default to no-CRT |
| status | Windows-hosted `std_async.zig:259` field-resolution failure root-caused to a C89 update-stream fseek elision in `spill_store.zig` and fixed; CRT build app-ready |
| lib | 50 std `.zig` + `manifest.md5` |
| HEAD/date | `2f0b9d29` / 2026-11-02 |

Provenance note: the archived binary (md5 a452e713f869f6d7f8c4894c2acb67e5) was captured by
scripts/seed/archive_seed.sh at packaging base HEAD 2f0b9d29. The compiler
source that produced the binary and the self-emission C is commit efdb269b
(folded-arm DCE flag fix in block/labeled sequences; the regression gate is
commit 2f0b9d29). gcc of the archive's self-emission C reproduces the fixed
point `a452e713f869f6d7f8c4894c2acb67e5` — the binary and the C are the same compiler state.
The compiler self-build uses `-ffast` (user programs
default to `-fsafe`), so the recorded fixed point is the `-ffast` binary.
Rebuild recipes + full canonical flag-set requirement (`gcc -m32
-std=c89 -O0 -Wall -Wno-long-long -Wno-pointer-sign
-Wno-implicit-function-declaration`; the fixed point reproduces ONLY with
`-Wall` present) are recorded in `zig1-seed/SEED_README.txt`.

## 2026-10-29 — seed v129 (HEAD 1e7b303a)

Seed rotation via scripts/seed/archive_seed.sh. Archive layout: top-level dir
`zig1-seed/` with `zig1`, `gen/` (48 `.c` + 49 `.h` incl.
emitted `zig_special_types.h`, 12281379 bytes), `c_exit.c` (top level),
`runtime/`, `lib/`, `SEED_README.txt`.

| field | value |
|---|---|
| date | 2026-10-29 |
| HEAD | `1e7b303a` |
| seed binary md5 | `c1bb4c0e7cbb3d9f4a808491f1a5772d` |
| self-emission C | 48 `.c` + 49 `.h` (12281379 bytes) |
| fixed point | `c1bb4c0e7cbb3d9f4a808491f1a5772d` |
| lib manifest | `lib/manifest.md5` (50 std files; md5 `8b78593a7dabb86f9f01cd9e7994ab9f`) |
| archive md5 | `af4a480f16e833a26f29210fec9a30b5` |

### Win9x companion seed

| field | value |
|---|---|
| zip | `release/seed/zig1_seed_w9.zip` |
| zip md5 | `f6aa60cb05e7533b9f24afa1040ad0d3` |
| win/ C | 52 `.c` + 51 `.h` (full `zig1 -osw` compiler dump; MSVC/OWC no-CRT scripts, aliases, and `build_target.sh` removed; MinGW fallback pair shipped) |
| compiler build scripts | `build_target_crt.bat`, `build_owc_crt.bat` (static CRT; no msvcrt.dll; single EXE) |
| compiler source | `-fsafe`-clean (12 intentional wraps + 3 real safe-mode defects fixed) |
| no-CRT zig1 | deferred to asm_x86; emitted programs still default to no-CRT |
| status | Windows-hosted `std_async.zig:259` field-resolution failure root-caused to a C89 update-stream fseek elision in `spill_store.zig` and fixed; CRT build app-ready |
| lib | 50 std `.zig` + `manifest.md5` |
| HEAD/date | `1e7b303a` / 2026-10-29 |

### Battery at rotation (v129)

- **Corpus:** 1193 dirs = 1017 OK / 58 GREEN / 118 FAIL / 0 ICE / 0 CRASH;
  class md5 `5167393439ffb80049ba5d3d87a2773f` (unchanged).
- **Frozen-1124:** 1124 lines, md5 `518eca1a9b5d3e1cc5a48abce214abd8`,
  diff vs anchor empty (0 movers).
- **Goldens 5/5 byte-identical:** gol `fcbf7e7cead5082f0a8caadd5a8f0ff9`,
  lisp basic `b3d9f8974da24ddbf9d389f3d7d97322`, lisp canonical
  `96654b3910a54d8bb7ec3ddfc0f26c6a`, json `8bda3d5a1ec07d14a301bc343df32bf8`,
  mud server/client `66c8f0abb926cca7baf9a0d1692ab318` /
  `93147d0f0bbd983a9d844fea8b7a6fa7`.
- **8 dump pins unchanged:** mud `c52b9bb9…`/`beea8281…`, gol
  `078c7c6c…`/`d9eb5b2f…`, lisp `4d08641e…`/`8a1905f2…`, json
  `c03d635c…`/`f43bb7b8…`.
- **Markers:** 3397 lines / 39012 B (v128 was 3304 / 37896).
- **Examples:** 26/26 build and 26/26 run with the expected rc set.
- **stdlib:** 339 PASS / 0 FAIL; crosscheck 10 PASS / 0 FAIL.
- **Gates:** `gate_win_compat` (reserved scan + 8 bat lints + reserved-export
  probe + MinGW cross compile 52 TUs), `gate_warn_clean`,
  `gate_builtin_names`, `gate_lower_depth` (8 pins), `gate_reserved_names`,
  `gate_crlf`, `check_emit_support` 8/8 — all GREEN.
- **Closure:** rebuild from this archive closes at hop1 == hop2 ==
  `c1bb4c0e7cbb3d9f4a808491f1a5772d`.

Provenance note: the archived binary (md5 c1bb4c0e7cbb3d9f4a808491f1a5772d) was captured by
scripts/seed/archive_seed.sh at HEAD 1e7b303a; gcc of the archive's self-emission
C reproduces the self-emission fixed point `c1bb4c0e7cbb3d9f4a808491f1a5772d` — both are the same
compiler state at HEAD 1e7b303a. The compiler self-build uses `-ffast` (user
programs default to `-fsafe`), so the recorded fixed point is the `-ffast`
binary. Rebuild recipes + full canonical flag-set requirement (`gcc -m32
-std=c89 -O0 -Wall -Wno-long-long -Wno-pointer-sign
-Wno-implicit-function-declaration`; the fixed point reproduces ONLY with
`-Wall` present) are recorded in `zig1-seed/SEED_README.txt`.
## 2026-10-29 — seed v128 (HEAD a2e1db55)

Seed rotation via scripts/seed/archive_seed.sh. Archive layout: top-level dir
`zig1-seed/` with `zig1`, `gen/` (48 `.c` + 49 `.h` incl.
emitted `zig_special_types.h`, 12235048 bytes), `c_exit.c` (top level),
`runtime/`, `lib/`, `SEED_README.txt`.

| field | value |
|---|---|
| date | 2026-10-29 |
| HEAD | `a2e1db55` |
| seed binary md5 | `18b4b10c8e014b486b648392d55ccdbe` |
| self-emission C | 48 `.c` + 49 `.h` (12235048 bytes) |
| fixed point | `18b4b10c8e014b486b648392d55ccdbe` |
| lib manifest | `lib/manifest.md5` (50 std files; md5 `8b78593a7dabb86f9f01cd9e7994ab9f`) |
| archive md5 | `5093ca9eaacd03bdb29c07777749cc16` |

### Phase 2.5 milestone (v128)

- **Iterative-lowering leftovers (T1/T2, 2026-10-27/28).** Removed the
  unreachable `lowerStmtLeaf*` tail chains; added the
  `scripts/compiler/gate_builtin_names.sh` name-table gate; added the
  fixed-arity delivery-scan guard. Raised the semantic-analyzer depth guard to
  the measured ceiling (`SEMA_GUARD_MAX = 130`) with its own limit-family
  diagnostic `error[3077]` (`ERR_9001_ICE`/`error[3043]` stays for genuine
  ICEs); applied the deferred M4 fixes (Win32 cmdline quoting, PE-to-COFF
  fallback, FILE aux long names, `.zig1_dbg.tmp` cleanup, pipefail-safe
  `gate_debug_map` grep).
- **Mutable `for` capture (T3/T4, 2026-10-28).** `for (xs) |*item|` /
  `|*item, index|` / `|*_|` bind a pointer into the iterable storage; the
  capture is `*const T` for const element types and the binding stays
  immutable while `item.*` / `item.field` write through it. Added the
  sema-only `--check` mode. Range iterables, non-variable array values, and
  iterables with no resolvable element type reject with `error[3078]`.
- **`std.fold` (T5, 2026-10-29).** Added `foldU32` / `foldI32` / `foldUsize`
  and re-exported `std.fold` from the `std.zig` barrel (lib payload is now 50
  files = `std.zig` + 49 `std_*.zig`).
- **Win9x toolchain conformance (T7/Task 9, 2026-10-28).** Fixed D11
  (declarations before statements in emitted functions), emitted Windows text
  as CRLF, dropped the generated-script `/za` `/we` `/Za` `/WX` flags, added
  the `build_mingw_crt.bat` / `build_mingw_nocrt.bat` fallback pair, made
  emission warning-clean at the origin (`gate_warn_clean.sh`, sole suppression
  `-Wno-long-long`, gcc-gate-only), and made `sf/src/emit_support.zig` the
  single hand-edited source for the runtime support files.
- **GUI 16-color GDI fallback (T8, 2026-10-29).** `std_gfx` falls back from
  DirectDraw to a GDI back-buffer path on 16-color / unusable-DDraw machines
  and reports open failures visibly (`gfxShowError`); `gfx_demo` smoke
  failures stay on stderr with the existing exit code.
- **Battery at rotation:** corpus 1193 dirs = 1017 OK / 58 GREEN / 118 FAIL /
  0 ICE / 0 CRASH; frozen-1124 0 movers (`518eca1a…`); goldens 5/5 byte-exact;
  8 dump pins re-recorded once; markers 3304 lines / 37896 B; examples 26/26;
  stdlib 339/0 + crosscheck 10/10; all seven gates and the five tier suites
  green (dbg 38/38 twice, dbg_core 26/26, gfx 24/24 normal + forced, edit
  38/38, edit_gui 64/64 normal + forced).

### Win9x companion seed

| field | value |
|---|---|
| zip | `release/seed/zig1_seed_w9.zip` |
| zip md5 | `eb96956e3281711c452d78c05a8587da` |
| win/ C | 52 `.c` + 51 `.h` (full `zig1 -osw` compiler dump; MSVC/OWC no-CRT scripts, aliases, and `build_target.sh` removed; MinGW fallback pair shipped) |
| compiler build scripts | `build_target_crt.bat`, `build_owc_crt.bat` (static CRT; no msvcrt.dll; single EXE) plus the MinGW fallback pair `build_mingw_crt.bat` / `build_mingw_nocrt.bat` |
| compiler source | `-fsafe`-clean (12 intentional wraps + 3 real safe-mode defects fixed) |
| no-CRT zig1 | deferred to asm_x86; emitted programs still default to no-CRT |
| status | Windows-hosted `std_async.zig:259` field-resolution failure root-caused to a C89 update-stream fseek elision in `spill_store.zig` and fixed; CRT build app-ready |
| lib | 50 std `.zig` + `manifest.md5` |
| HEAD/date | `a2e1db55` / 2026-10-29 |

Provenance note: the archived binary (md5 18b4b10c8e014b486b648392d55ccdbe) was captured by
scripts/seed/archive_seed.sh at HEAD a2e1db55; gcc of the archive's self-emission
C reproduces the self-emission fixed point `18b4b10c8e014b486b648392d55ccdbe` — both are the same
compiler state at HEAD a2e1db55. The compiler self-build uses `-ffast` (user
programs default to `-fsafe`), so the recorded fixed point is the `-ffast`
binary. Rebuild recipes + full canonical flag-set requirement (`gcc -m32
-std=c89 -O0 -Wall -Wno-long-long -Wno-pointer-sign
-Wno-implicit-function-declaration`; the fixed point reproduces ONLY with
`-Wall` present) are recorded in `zig1-seed/SEED_README.txt`.
## 2026-10-28 — seed v127 (HEAD 1b20dc71)

Seed rotation via scripts/seed/archive_seed.sh. Archive layout: top-level dir
`zig1-seed/` with `zig1`, `gen/` (48 `.c` + 49 `.h` incl.
emitted `zig_special_types.h`, 11913427 bytes), `c_exit.c` (top level),
`runtime/`, `lib/`, `SEED_README.txt`.

| field | value |
|---|---|
| date | 2026-10-28 |
| HEAD | `1b20dc71` |
| seed binary md5 | `2fc64ffedb3ba5f4e8adf35896729e54` |
| self-emission C | 48 `.c` + 49 `.h` (11913427 bytes) |
| fixed point | `2fc64ffedb3ba5f4e8adf35896729e54` |
| lib manifest | `lib/manifest.md5` (49 std files; md5 `fc9646bfcfecb14fd3872833bf13d43a`) |
| archive md5 | `70a6173979fe74db8d00b0e1212153d7` |

Note: v127 refreshes the std payload with the P4-M4 theme system + the black
color-atlas fix; P4 adds no compiler source change.

### Win9x companion seed

| field | value |
|---|---|
| zip | `release/seed/zig1_seed_w9.zip` |
| zip md5 | `adc2c2bd424783118a8b05b6336c1f0e` |
| win/ C | 52 `.c` + 51 `.h` (full `zig1 -osw` compiler dump; no-CRT scripts, aliases, and `build_target.sh` removed) |
| compiler build scripts | `build_target_crt.bat`, `build_owc_crt.bat` (static CRT; no msvcrt.dll; single EXE) |
| compiler source | `-fsafe`-clean (12 intentional wraps + 3 real safe-mode defects fixed) |
| no-CRT zig1 | deferred to asm_x86; emitted programs still default to no-CRT |
| status | Windows-hosted `std_async.zig:259` field-resolution failure root-caused to a C89 update-stream fseek elision in `spill_store.zig` and fixed; CRT build app-ready |
| lib | 49 std `.zig` + `manifest.md5` |
| HEAD/date | `1b20dc71` / 2026-10-28 |

Provenance note: the archived binary (md5 2fc64ffedb3ba5f4e8adf35896729e54) was captured by
scripts/seed/archive_seed.sh at HEAD 1b20dc71; gcc of the archive's self-emission
C reproduces the self-emission fixed point `2fc64ffedb3ba5f4e8adf35896729e54` — both are the same
compiler state at HEAD 1b20dc71. The compiler self-build uses `-ffast` (user
programs default to `-fsafe`), so the recorded fixed point is the `-ffast`
binary. Rebuild recipes + full canonical flag-set requirement (`gcc -m32
-std=c89 -O0 -Wall -Wno-long-long -Wno-pointer-sign
-Wno-implicit-function-declaration`; the fixed point reproduces ONLY with
`-Wall` present) are recorded in `zig1-seed/SEED_README.txt`.
## 2026-10-28 — seed v126 (HEAD 3d88a58e)

Seed rotation via scripts/seed/archive_seed.sh. Archive layout: top-level dir
`zig1-seed/` with `zig1`, `gen/` (48 `.c` + 49 `.h` incl.
emitted `zig_special_types.h`, 11913427 bytes), `c_exit.c` (top level),
`runtime/`, `lib/`, `SEED_README.txt`.

| field | value |
|---|---|
| date | 2026-10-28 |
| HEAD | `3d88a58e` |
| seed binary md5 | `2fc64ffedb3ba5f4e8adf35896729e54` |
| self-emission C | 48 `.c` + 49 `.h` (11913427 bytes) |
| fixed point | `2fc64ffedb3ba5f4e8adf35896729e54` |
| lib manifest | `lib/manifest.md5` (49 std files; md5 `459b8e2baf656c0281dae4a0588d0930`) |
| archive md5 | `00ff9b75d697a110e662ebf75bb65cea` |

Std payload: v126 refreshes the std payload with the Phase 2 P4-M4 theme system
(`std_gfx.Theme` + `gfxSetTheme`/`gfxGetTheme`; `std_gfx_pal` white/solarized/
dark 16-color tables with atlas+brush rebuild). P4 adds **no compiler source
change**, so the fixed point stays `2fc64ffe…`.

### Win9x companion seed

| field | value |
|---|---|
| zip | `release/seed/zig1_seed_w9.zip` |
| zip md5 | `0a1df690718917033a2b8c5884f12c3b` |
| win/ C | 52 `.c` + 51 `.h` (full `zig1 -osw` compiler dump; no-CRT scripts, aliases, and `build_target.sh` removed) |
| compiler build scripts | `build_target_crt.bat`, `build_owc_crt.bat` (static CRT; no msvcrt.dll; single EXE) |
| compiler source | `-fsafe`-clean (12 intentional wraps + 3 real safe-mode defects fixed) |
| no-CRT zig1 | deferred to asm_x86; emitted programs still default to no-CRT |
| status | Windows-hosted `std_async.zig:259` field-resolution failure root-caused to a C89 update-stream fseek elision in `spill_store.zig` and fixed; CRT build app-ready |
| lib | 49 std `.zig` + `manifest.md5` |
| HEAD/date | `3d88a58e` / 2026-10-28 |

Provenance note: the archived binary (md5 2fc64ffedb3ba5f4e8adf35896729e54) was captured by
scripts/seed/archive_seed.sh at HEAD 3d88a58e; gcc of the archive's self-emission
C reproduces the self-emission fixed point `2fc64ffedb3ba5f4e8adf35896729e54` — both are the same
compiler state at HEAD 3d88a58e. The compiler self-build uses `-ffast` (user
programs default to `-fsafe`), so the recorded fixed point is the `-ffast`
binary. Rebuild recipes + full canonical flag-set requirement (`gcc -m32
-std=c89 -O0 -Wall -Wno-long-long -Wno-pointer-sign
-Wno-implicit-function-declaration`; the fixed point reproduces ONLY with
`-Wall` present) are recorded in `zig1-seed/SEED_README.txt`.
## 2026-10-28 — seed v125 (HEAD 0683763d)

Seed rotation via scripts/seed/archive_seed.sh. Archive layout: top-level dir
`zig1-seed/` with `zig1`, `gen/` (48 `.c` + 49 `.h` incl.
emitted `zig_special_types.h`, 11913427 bytes), `c_exit.c` (top level),
`runtime/`, `lib/`, `SEED_README.txt`.

| field | value |
|---|---|
| date | 2026-10-28 |
| HEAD | `0683763d` |
| seed binary md5 | `2fc64ffedb3ba5f4e8adf35896729e54` |
| self-emission C | 48 `.c` + 49 `.h` (11913427 bytes) |
| fixed point | `2fc64ffedb3ba5f4e8adf35896729e54` |
| lib manifest | `lib/manifest.md5` (49 std files; md5 `29fe6bd51fa1a14839f476023a07562e`) |
| archive md5 | `804e71f416841bf5070eacae3919b785` |

Std payload: v125 refreshes the std payload with the P4 final-review fixes
(C1/C2/I3-I10); P4 adds **no compiler source change**, so the fixed point stays
v124's `2fc64ffe…`.

### Win9x companion seed

| field | value |
|---|---|
| zip | `release/seed/zig1_seed_w9.zip` |
| zip md5 | `e2fd1bdf0864959c133b3adf94ff94ac` |
| win/ C | 52 `.c` + 51 `.h` (full `zig1 -osw` compiler dump; no-CRT scripts, aliases, and `build_target.sh` removed) |
| compiler build scripts | `build_target_crt.bat`, `build_owc_crt.bat` (static CRT; no msvcrt.dll; single EXE) |
| compiler source | `-fsafe`-clean (12 intentional wraps + 3 real safe-mode defects fixed) |
| no-CRT zig1 | deferred to asm_x86; emitted programs still default to no-CRT |
| status | Windows-hosted `std_async.zig:259` field-resolution failure root-caused to a C89 update-stream fseek elision in `spill_store.zig` and fixed; CRT build app-ready |
| lib | 49 std `.zig` + `manifest.md5` |
| HEAD/date | `0683763d` / 2026-10-28 |

Provenance note: the archived binary (md5 2fc64ffedb3ba5f4e8adf35896729e54) was captured by
scripts/seed/archive_seed.sh at HEAD 0683763d; gcc of the archive's self-emission
C reproduces the self-emission fixed point `2fc64ffedb3ba5f4e8adf35896729e54` — both are the same
compiler state at HEAD 0683763d. The compiler self-build uses `-ffast` (user
programs default to `-fsafe`), so the recorded fixed point is the `-ffast`
binary. Rebuild recipes + full canonical flag-set requirement (`gcc -m32
-std=c89 -O0 -Wall -Wno-long-long -Wno-pointer-sign
-Wno-implicit-function-declaration`; the fixed point reproduces ONLY with
`-Wall` present) are recorded in `zig1-seed/SEED_README.txt`.
## 2026-10-27 — seed v124 (HEAD 3c0c5f45)

Seed rotation via scripts/seed/archive_seed.sh. Archive layout: top-level dir
`zig1-seed/` with `zig1`, `gen/` (48 `.c` + 49 `.h` incl.
emitted `zig_special_types.h`, 11913427 bytes), `c_exit.c` (top level),
`runtime/`, `lib/`, `SEED_README.txt`.

| field | value |
|---|---|
| date | 2026-10-27 |
| HEAD | `3c0c5f45` |
| seed binary md5 | `2fc64ffedb3ba5f4e8adf35896729e54` |
| self-emission C | 48 `.c` + 49 `.h` (11913427 bytes) |
| fixed point | `2fc64ffedb3ba5f4e8adf35896729e54` |
| lib manifest | `lib/manifest.md5` (49 std files; md5 `51f628e55aad45388efe23c14205fdb3`) |
| archive md5 | `205ce0860b438765ed90f6268686852e` |

Std payload: **+`std_gfx.zig` + `std_gfx_pal.zig`** (Phase 2 P4 M1–M3, minimal
windowed DirectDraw7 GUI layer), growing `lib/` from 47 to **49**. P4 adds **no
compiler source change**; the fixed point moved from v123's `a567926c…` to
`2fc64ffe…` because the pre-P4 leaf-tail cleanup `60e3a916` (`sf/src/lower.zig`)
postdates v123. `build_from_seed.sh` on this archive reproduces
`2fc64ffe…` (hop1 == hop2). The no-CRT compiler build remains deferred to
asm_x86; emitted programs still default to no-CRT.

### Win9x companion seed

| field | value |
|---|---|
| zip | `release/seed/zig1_seed_w9.zip` |
| zip md5 | `32d5d9945b89f653c78c4da8de65f648` |
| win/ C | 52 `.c` + 51 `.h` (full `zig1 -osw` compiler dump; no-CRT scripts, aliases, and `build_target.sh` removed) |
| compiler build scripts | `build_target_crt.bat`, `build_owc_crt.bat` (static CRT; no msvcrt.dll; single EXE) |
| compiler source | `-fsafe`-clean (12 intentional wraps + 3 real safe-mode defects fixed) |
| no-CRT zig1 | deferred to asm_x86; emitted programs still default to no-CRT |
| status | Windows-hosted `std_async.zig:259` field-resolution failure root-caused to a C89 update-stream fseek elision in `spill_store.zig` and fixed; CRT build app-ready |
| lib | 49 std `.zig` + `manifest.md5` |
| HEAD/date | `3c0c5f45` / 2026-10-27 |

Provenance note: the archived binary (md5 2fc64ffedb3ba5f4e8adf35896729e54) was captured by
scripts/seed/archive_seed.sh at HEAD 3c0c5f45; gcc of the archive's self-emission
C reproduces the self-emission fixed point `2fc64ffedb3ba5f4e8adf35896729e54` — both are the same
compiler state at HEAD 3c0c5f45. The compiler self-build uses `-ffast` (user
programs default to `-fsafe`), so the recorded fixed point is the `-ffast`
binary. Rebuild recipes + full canonical flag-set requirement (`gcc -m32
-std=c89 -O0 -Wall -Wno-long-long -Wno-pointer-sign
-Wno-implicit-function-declaration`; the fixed point reproduces ONLY with
`-Wall` present) are recorded in `zig1-seed/SEED_README.txt`.
## 2026-10-27 — seed v123 (HEAD 8dcda630)

Seed rotation via scripts/seed/archive_seed.sh. Archive layout: top-level dir
`zig1-seed/` with `zig1`, `gen/` (48 `.c` + 49 `.h` incl.
emitted `zig_special_types.h`, 12118809 bytes), `c_exit.c` (top level),
`runtime/`, `lib/`, `SEED_README.txt`.

| field | value |
|---|---|
| date | 2026-10-27 |
| HEAD | `8dcda630` |
| seed binary md5 | `a567926c223492787786dd460563f32a` |
| self-emission C | 48 `.c` + 49 `.h` (12118809 bytes) |
| fixed point | `a567926c223492787786dd460563f32a` |
| lib manifest | `lib/manifest.md5` (47 std files; md5 `7ef5c6b66a2975b51847515fe91fff41`) |
| archive md5 | `3e0094f480a29a73fdcb200670b7c8d2` |

### Win9x companion seed

| field | value |
|---|---|
| zip | `release/seed/zig1_seed_w9.zip` |
| zip md5 | `f2968cd6ac20438bc49665d2860cf999` |
| win/ C | 52 `.c` + 51 `.h` (full `zig1 -osw` compiler dump; no-CRT scripts, aliases, and `build_target.sh` removed) |
| compiler build scripts | `build_target_crt.bat`, `build_owc_crt.bat` (static CRT; no msvcrt.dll; single EXE) |
| compiler source | `-fsafe`-clean (12 intentional wraps + 3 real safe-mode defects fixed) |
| no-CRT zig1 | deferred to asm_x86; emitted programs still default to no-CRT |
| status | Windows-hosted `std_async.zig:259` field-resolution failure root-caused to a C89 update-stream fseek elision in `spill_store.zig` and fixed; CRT build app-ready |
| lib | 47 std `.zig` + `manifest.md5` |
| HEAD/date | `8dcda630` / 2026-10-27 |

Provenance note: the archived binary (md5 a567926c223492787786dd460563f32a) was captured by
scripts/seed/archive_seed.sh at HEAD 8dcda630; gcc of the archive's self-emission
C reproduces the self-emission fixed point `a567926c223492787786dd460563f32a` — both are the same
compiler state at HEAD 8dcda630. The compiler self-build uses `-ffast` (user
programs default to `-fsafe`), so the recorded fixed point is the `-ffast`
binary. Rebuild recipes + full canonical flag-set requirement (`gcc -m32
-std=c89 -O0 -Wall -Wno-long-long -Wno-pointer-sign
-Wno-implicit-function-declaration`; the fixed point reproduces ONLY with
`-Wall` present) are recorded in `zig1-seed/SEED_README.txt`.
## 2026-10-26 — seed v122 (HEAD 4805a742)

Seed rotation via scripts/seed/archive_seed.sh. Archive layout: top-level dir
`zig1-seed/` with `zig1`, `gen/` (48 `.c` + 49 `.h` incl.
emitted `zig_special_types.h`, 10846315 bytes), `c_exit.c` (top level),
`runtime/`, `lib/`, `SEED_README.txt`.

| field | value |
|---|---|
| date | 2026-10-26 |
| HEAD | `4805a742` |
| seed binary md5 | `a806a3573c618496ddf956f1c746f316` |
| self-emission C | 48 `.c` + 49 `.h` (10846315 bytes) |
| fixed point | `a806a3573c618496ddf956f1c746f316` |
| lib manifest | `lib/manifest.md5` (47 std files; md5 `7ef5c6b66a2975b51847515fe91fff41`) |
| archive md5 | `0ce54732efd607d387bbfb5a7b870127` |

### Win9x companion seed

| field | value |
|---|---|
| zip | `release/seed/zig1_seed_w9.zip` |
| zip md5 | `8945a582e85fe46531d3ecbd1176e8d1` |
| win/ C | 52 `.c` + 51 `.h` (full `zig1 -osw` compiler dump; no-CRT scripts, aliases, and `build_target.sh` removed) |
| compiler build scripts | `build_target_crt.bat`, `build_owc_crt.bat` (static CRT; no msvcrt.dll; single EXE) |
| compiler source | `-fsafe`-clean (12 intentional wraps + 3 real safe-mode defects fixed) |
| no-CRT zig1 | deferred to asm_x86; emitted programs still default to no-CRT |
| status | Windows-hosted `std_async.zig:259` field-resolution failure root-caused to a C89 update-stream fseek elision in `spill_store.zig` and fixed; CRT build app-ready |
| lib | 47 std `.zig` + `manifest.md5` |
| HEAD/date | `4805a742` / 2026-10-26 |

Provenance note: the archived binary (md5 a806a3573c618496ddf956f1c746f316) was captured by
scripts/seed/archive_seed.sh at HEAD 4805a742; gcc of the archive's self-emission
C reproduces the self-emission fixed point `a806a3573c618496ddf956f1c746f316` — both are the same
compiler state at HEAD 4805a742. The compiler self-build uses `-ffast` (user
programs default to `-fsafe`), so the recorded fixed point is the `-ffast`
binary. Rebuild recipes + full canonical flag-set requirement (`gcc -m32
-std=c89 -O0 -Wall -Wno-long-long -Wno-pointer-sign
-Wno-implicit-function-declaration`; the fixed point reproduces ONLY with
`-Wall` present) are recorded in `zig1-seed/SEED_README.txt`.
## 2026-10-25 — seed v121 (HEAD 076403ea)

Seed rotation via scripts/seed/archive_seed.sh. Archive layout: top-level dir
`zig1-seed/` with `zig1`, `gen/` (48 `.c` + 49 `.h` incl.
emitted `zig_special_types.h`, 10845563 bytes), `c_exit.c` (top level),
`runtime/`, `lib/`, `SEED_README.txt`.

| field | value |
|---|---|
| date | 2026-10-25 |
| HEAD | `076403ea` |
| seed binary md5 | `dcfc9e70e475a8a08c0487dafd2e6b45` |
| self-emission C | 48 `.c` + 49 `.h` (10845563 bytes) |
| fixed point | `dcfc9e70e475a8a08c0487dafd2e6b45` |
| lib manifest | `lib/manifest.md5` (47 std files; md5 `7ef5c6b66a2975b51847515fe91fff41`) |
| archive md5 | `0d000eb5cf2c83754cbe5aac38cb1740` |

### Win9x companion seed

| field | value |
|---|---|
| zip | `release/seed/zig1_seed_w9.zip` |
| zip md5 | `1f65ea9ccc57bf31d21af190497274ea` |
| win/ C | 52 `.c` + 51 `.h` (full `zig1 -osw` compiler dump; no-CRT scripts, aliases, and `build_target.sh` removed) |
| compiler build scripts | `build_target_crt.bat`, `build_owc_crt.bat` (static CRT; no msvcrt.dll; single EXE) |
| compiler source | `-fsafe`-clean (12 intentional wraps + 3 real safe-mode defects fixed) |
| no-CRT zig1 | deferred to asm_x86; emitted programs still default to no-CRT |
| status | Windows-hosted `std_async.zig:259` field-resolution failure remains under investigation; not app-ready |
| lib | 47 std `.zig` + `manifest.md5` |
| HEAD/date | `076403ea` / 2026-10-25 |

Provenance note: the archived binary (md5 dcfc9e70e475a8a08c0487dafd2e6b45) was captured by
scripts/seed/archive_seed.sh at HEAD 076403ea; gcc of the archive's self-emission
C reproduces the self-emission fixed point `dcfc9e70e475a8a08c0487dafd2e6b45` — both are the same
compiler state at HEAD 076403ea. The compiler self-build uses `-ffast` (user
programs default to `-fsafe`), so the recorded fixed point is the `-ffast`
binary. Rebuild recipes + full canonical flag-set requirement (`gcc -m32
-std=c89 -O0 -Wall -Wno-long-long -Wno-pointer-sign
-Wno-implicit-function-declaration`; the fixed point reproduces ONLY with
`-Wall` present) are recorded in `zig1-seed/SEED_README.txt`.
## 2026-10-24 — seed v120 (HEAD 5981b560)

Seed rotation via scripts/seed/archive_seed.sh. Archive layout: top-level dir
`zig1-seed/` with `zig1`, `gen/` (48 `.c` + 49 `.h` incl.
emitted `zig_special_types.h`, 10844907 bytes), `c_exit.c` (top level),
`runtime/`, `lib/`, `SEED_README.txt`.

| field | value |
|---|---|
| date | 2026-10-24 |
| HEAD | `5981b560` |
| seed binary md5 | `11de43a053bdde3be3ddc61caac31df6` |
| self-emission C | 48 `.c` + 49 `.h` (10844907 bytes) |
| fixed point | `11de43a053bdde3be3ddc61caac31df6` |
| lib manifest | `lib/manifest.md5` (47 std files; md5 `7ef5c6b66a2975b51847515fe91fff41`) |
| archive md5 | `18c21ebfc18f3014f0ccab2f10f38688` |

Provenance note: the archived binary (md5 11de43a053bdde3be3ddc61caac31df6) was captured by
scripts/seed/archive_seed.sh at HEAD 5981b560; gcc of the archive's self-emission
C reproduces the self-emission fixed point `11de43a053bdde3be3ddc61caac31df6` — both are the same
compiler state at HEAD 5981b560. The compiler self-build uses `-ffast` (user
programs default to `-fsafe`), so the recorded fixed point is the `-ffast`
binary. Rebuild recipes + full canonical flag-set requirement (`gcc -m32
-std=c89 -O0 -Wall -Wno-long-long -Wno-pointer-sign
-Wno-implicit-function-declaration`; the fixed point reproduces ONLY with
`-Wall` present) are recorded in `zig1-seed/SEED_README.txt`.
## 2026-10-23 — seed v119 (HEAD 69070dc4)

Seed rotation via scripts/seed/archive_seed.sh. Archive layout: top-level dir
`zig1-seed/` with `zig1`, `gen/` (47 `.c` + 48 `.h` incl.
emitted `zig_special_types.h`, 10691275 bytes), `c_exit.c` (top level),
`runtime/`, `lib/`, `SEED_README.txt`.

| field | value |
|---|---|
| date | 2026-10-23 |
| HEAD | `69070dc4` |
| seed binary md5 | `45158dcede81125a39a2c2c58478e21e` |
| self-emission C | 47 `.c` + 48 `.h` (10691275 bytes) |
| fixed point | `45158dcede81125a39a2c2c58478e21e` |
| lib manifest | `lib/manifest.md5` (47 std files; md5 `e731a3d2a7aef913f5bbcfd8670e5a2e`) |
| archive md5 | `e7ac8cd2ed7e790a4b9225a82acaf4a5` |

Provenance note: the archived binary (md5 45158dcede81125a39a2c2c58478e21e) was captured by
scripts/seed/archive_seed.sh at HEAD 69070dc4; gcc of the archive's self-emission
C reproduces the self-emission fixed point `45158dcede81125a39a2c2c58478e21e` — both are the same
compiler state at HEAD 69070dc4. The compiler self-build uses `-ffast` (user
programs default to `-fsafe`), so the recorded fixed point is the `-ffast`
binary. Rebuild recipes + full canonical flag-set requirement (`gcc -m32
-std=c89 -O0 -Wall -Wno-long-long -Wno-pointer-sign
-Wno-implicit-function-declaration`; the fixed point reproduces ONLY with
`-Wall` present) are recorded in `zig1-seed/SEED_README.txt`.
## 2026-10-23 — seed v118 (HEAD 651f83a0)

Seed rotation via scripts/seed/archive_seed.sh. Archive layout: top-level dir
`zig1-seed/` with `zig1`, `gen/` (47 `.c` + 48 `.h` incl.
emitted `zig_special_types.h`, 10691275 bytes), `c_exit.c` (top level),
`runtime/`, `lib/`, `SEED_README.txt`.

| field | value |
|---|---|
| date | 2026-10-23 |
| HEAD | `651f83a0` |
| seed binary md5 | `45158dcede81125a39a2c2c58478e21e` |
| self-emission C | 47 `.c` + 48 `.h` (10691275 bytes) |
| fixed point | `45158dcede81125a39a2c2c58478e21e` |
| lib manifest | `lib/manifest.md5` (46 std files; md5 `15c7bc2daeba84f892ef376df7cf4a7d`) |
| archive md5 | `9716ea682cf7eb9147b5e642ce48fc93` |

Provenance note: the archived binary (md5 45158dcede81125a39a2c2c58478e21e) was captured by
scripts/seed/archive_seed.sh at HEAD 651f83a0; gcc of the archive's self-emission
C reproduces the self-emission fixed point `45158dcede81125a39a2c2c58478e21e` — both are the same
compiler state at HEAD 651f83a0. The compiler self-build uses `-ffast` (user
programs default to `-fsafe`), so the recorded fixed point is the `-ffast`
binary. Rebuild recipes + full canonical flag-set requirement (`gcc -m32
-std=c89 -O0 -Wall -Wno-long-long -Wno-pointer-sign
-Wno-implicit-function-declaration`; the fixed point reproduces ONLY with
`-Wall` present) are recorded in `zig1-seed/SEED_README.txt`.
## 2026-10-22 — seed v117 (HEAD a16dd0d6)

Seed rotation via scripts/seed/archive_seed.sh. Archive layout: top-level dir
`zig1-seed/` with `zig1`, `gen/` (47 `.c` + 48 `.h` incl.
emitted `zig_special_types.h`, 10691275 bytes), `c_exit.c` (top level),
`runtime/`, `lib/`, `SEED_README.txt`.

| field | value |
|---|---|
| date | 2026-10-22 |
| HEAD | `a16dd0d6` |
| seed binary md5 | `45158dcede81125a39a2c2c58478e21e` |
| self-emission C | 47 `.c` + 48 `.h` (10691275 bytes) |
| fixed point | `45158dcede81125a39a2c2c58478e21e` |
| lib manifest | `lib/manifest.md5` (45 std files; md5 `ef02702556fe1ae8c21e68d8f2bff141`) |
| archive md5 | `111e0474c702a582516f60c2e570a3c0` |

Provenance note: the archived binary (md5 45158dcede81125a39a2c2c58478e21e) was captured by
scripts/seed/archive_seed.sh at HEAD a16dd0d6; gcc of the archive's self-emission
C reproduces the self-emission fixed point `45158dcede81125a39a2c2c58478e21e` — both are the same
compiler state at HEAD a16dd0d6. The compiler self-build uses `-ffast` (user
programs default to `-fsafe`), so the recorded fixed point is the `-ffast`
binary. Rebuild recipes + full canonical flag-set requirement (`gcc -m32
-std=c89 -O0 -Wall -Wno-long-long -Wno-pointer-sign
-Wno-implicit-function-declaration`; the fixed point reproduces ONLY with
`-Wall` present) are recorded in `zig1-seed/SEED_README.txt`.
## 2026-10-22 — seed v116 (HEAD 17bbcfa1)

Seed rotation via scripts/seed/archive_seed.sh. Archive layout: top-level dir
`zig1-seed/` with `zig1`, `gen/` (47 `.c` + 48 `.h` incl.
emitted `zig_special_types.h`, 10691275 bytes), `c_exit.c` (top level),
`runtime/`, `lib/`, `SEED_README.txt`.

| field | value |
|---|---|
| date | 2026-10-22 |
| HEAD | `17bbcfa1` |
| seed binary md5 | `45158dcede81125a39a2c2c58478e21e` |
| self-emission C | 47 `.c` + 48 `.h` (10691275 bytes) |
| fixed point | `45158dcede81125a39a2c2c58478e21e` |
| lib manifest | `lib/manifest.md5` (45 std files; md5 `0c022fe049c808828704b702e6a2b2e7`) |
| archive md5 | `ca0c46dcd671d50fd4f22497f5bc525a` |

Provenance note: the archived binary (md5 45158dcede81125a39a2c2c58478e21e) was captured by
scripts/seed/archive_seed.sh at HEAD 17bbcfa1; gcc of the archive's self-emission
C reproduces the self-emission fixed point `45158dcede81125a39a2c2c58478e21e` — both are the same
compiler state at HEAD 17bbcfa1. The compiler self-build uses `-ffast` (user
programs default to `-fsafe`), so the recorded fixed point is the `-ffast`
binary. Rebuild recipes + full canonical flag-set requirement (`gcc -m32
-std=c89 -O0 -Wall -Wno-long-long -Wno-pointer-sign
-Wno-implicit-function-declaration`; the fixed point reproduces ONLY with
`-Wall` present) are recorded in `zig1-seed/SEED_README.txt`.
## 2026-10-22 — seed v115 (HEAD 741658d2)

Seed rotation via scripts/seed/archive_seed.sh. Archive layout: top-level dir
`zig1-seed/` with `zig1`, `gen/` (47 `.c` + 48 `.h` incl.
emitted `zig_special_types.h`, 10691275 bytes), `c_exit.c` (top level),
`runtime/`, `lib/`, `SEED_README.txt`.

| field | value |
|---|---|
| date | 2026-10-22 |
| HEAD | `741658d2` |
| seed binary md5 | `45158dcede81125a39a2c2c58478e21e` |
| self-emission C | 47 `.c` + 48 `.h` (10691275 bytes) |
| fixed point | `45158dcede81125a39a2c2c58478e21e` |
| lib manifest | `lib/manifest.md5` (44 std files; md5 `576cffb600863a648f518748edad81c6`) |
| archive md5 | `484ae9797545591e113f002e595a26d2` |

Provenance note: the archived binary (md5 45158dcede81125a39a2c2c58478e21e) was captured by
scripts/seed/archive_seed.sh at HEAD 741658d2; gcc of the archive's self-emission
C reproduces the self-emission fixed point `45158dcede81125a39a2c2c58478e21e` — both are the same
compiler state at HEAD 741658d2. The compiler self-build uses `-ffast` (user
programs default to `-fsafe`), so the recorded fixed point is the `-ffast`
binary. Rebuild recipes + full canonical flag-set requirement (`gcc -m32
-std=c89 -O0 -Wall -Wno-long-long -Wno-pointer-sign
-Wno-implicit-function-declaration`; the fixed point reproduces ONLY with
`-Wall` present) are recorded in `zig1-seed/SEED_README.txt`.
## 2026-10-22 — seed v114 (HEAD 27722aea)

Seed rotation via scripts/seed/archive_seed.sh. Archive layout: top-level dir
`zig1-seed/` with `zig1`, `gen/` (47 `.c` + 48 `.h` incl.
emitted `zig_special_types.h`, 10691275 bytes), `c_exit.c` (top level),
`runtime/`, `lib/`, `SEED_README.txt`.

| field | value |
|---|---|
| date | 2026-10-22 |
| HEAD | `27722aea` |
| seed binary md5 | `45158dcede81125a39a2c2c58478e21e` |
| self-emission C | 47 `.c` + 48 `.h` (10691275 bytes) |
| fixed point | `45158dcede81125a39a2c2c58478e21e` |
| lib manifest | `lib/manifest.md5` (42 std files; md5 `35c97d7f19e39aae52e082e7fc3c2fc3`) |
| archive md5 | `d65fbb411296eaae68f5abcbdf91efbd` |

Provenance note: the archived binary (md5 45158dcede81125a39a2c2c58478e21e) was captured by
scripts/seed/archive_seed.sh at HEAD 27722aea; gcc of the archive's self-emission
C reproduces the self-emission fixed point `45158dcede81125a39a2c2c58478e21e` — both are the same
compiler state at HEAD 27722aea. The compiler self-build uses `-ffast` (user
programs default to `-fsafe`), so the recorded fixed point is the `-ffast`
binary. Rebuild recipes + full canonical flag-set requirement (`gcc -m32
-std=c89 -O0 -Wall -Wno-long-long -Wno-pointer-sign
-Wno-implicit-function-declaration`; the fixed point reproduces ONLY with
`-Wall` present) are recorded in `zig1-seed/SEED_README.txt`.
## 2026-10-22 — seed v113 (HEAD fe5b3c03)

Seed rotation via scripts/seed/archive_seed.sh. Archive layout: top-level dir
`zig1-seed/` with `zig1`, `gen/` (47 `.c` + 48 `.h` incl.
emitted `zig_special_types.h`, 10691275 bytes), `c_exit.c` (top level),
`runtime/`, `lib/`, `SEED_README.txt`.

| field | value |
|---|---|
| date | 2026-10-22 |
| HEAD | `fe5b3c03` |
| seed binary md5 | `45158dcede81125a39a2c2c58478e21e` |
| self-emission C | 47 `.c` + 48 `.h` (10691275 bytes) |
| fixed point | `45158dcede81125a39a2c2c58478e21e` |
| lib manifest | `lib/manifest.md5` (42 std files; md5 `b4c3059de37b3f5de2948ebc019e18a9`) |
| archive md5 | `92d39942ed3d08a6543d29d5fafc5a95` |

Provenance note: the archived binary (md5 45158dcede81125a39a2c2c58478e21e) was captured by
scripts/seed/archive_seed.sh at HEAD fe5b3c03; gcc of the archive's self-emission
C reproduces the self-emission fixed point `45158dcede81125a39a2c2c58478e21e` — both are the same
compiler state at HEAD fe5b3c03. The compiler self-build uses `-ffast` (user
programs default to `-fsafe`), so the recorded fixed point is the `-ffast`
binary. Rebuild recipes + full canonical flag-set requirement (`gcc -m32
-std=c89 -O0 -Wall -Wno-long-long -Wno-pointer-sign
-Wno-implicit-function-declaration`; the fixed point reproduces ONLY with
`-Wall` present) are recorded in `zig1-seed/SEED_README.txt`.
## 2026-10-22 — seed v112 (HEAD efce3dc7)

Seed rotation via scripts/seed/archive_seed.sh. Archive layout: top-level dir
`zig1-seed/` with `zig1`, `gen/` (47 `.c` + 48 `.h` incl.
emitted `zig_special_types.h`, 10691275 bytes), `c_exit.c` (top level),
`runtime/`, `lib/`, `SEED_README.txt`.

| field | value |
|---|---|
| date | 2026-10-22 |
| HEAD | `efce3dc7` |
| seed binary md5 | `45158dcede81125a39a2c2c58478e21e` |
| self-emission C | 47 `.c` + 48 `.h` (10691275 bytes) |
| fixed point | `45158dcede81125a39a2c2c58478e21e` |
| lib manifest | `lib/manifest.md5` (40 std files; md5 `88f2f6db2f30f7850a1aa3c3f5f8dce7`) |
| archive md5 | `578993ec772dcf2e715f705da9e451aa` |

Provenance note: the archived binary (md5 45158dcede81125a39a2c2c58478e21e) was captured by
scripts/seed/archive_seed.sh at HEAD efce3dc7; gcc of the archive's self-emission
C reproduces the self-emission fixed point `45158dcede81125a39a2c2c58478e21e` — both are the same
compiler state at HEAD efce3dc7. The compiler self-build uses `-ffast` (user
programs default to `-fsafe`), so the recorded fixed point is the `-ffast`
binary. Rebuild recipes + full canonical flag-set requirement (`gcc -m32
-std=c89 -O0 -Wall -Wno-long-long -Wno-pointer-sign
-Wno-implicit-function-declaration`; the fixed point reproduces ONLY with
`-Wall` present) are recorded in `zig1-seed/SEED_README.txt`.
## 2026-10-21 — seed v111 (HEAD b2035261)

Seed rotation via scripts/seed/archive_seed.sh. Archive layout: top-level dir
`zig1-seed/` with `zig1`, `gen/` (46 `.c` + 47 `.h` incl.
emitted `zig_special_types.h`, 10307965 bytes), `c_exit.c` (top level),
`runtime/`, `lib/`, `SEED_README.txt`.

| field | value |
|---|---|
| date | 2026-10-21 |
| HEAD | `b2035261` |
| seed binary md5 | `21c957730d268f1e7883176fa5413b65` |
| self-emission C | 46 `.c` + 47 `.h` (10307965 bytes) |
| fixed point | `21c957730d268f1e7883176fa5413b65` |
| lib manifest | `lib/manifest.md5` (40 std files; md5 `788f5642c1fdb13ee532673c5d24ed7e`) |
| archive md5 | `5dc851a1a96c0776ef36e8e5b29774b7` |

Provenance note: the archived binary (md5 21c957730d268f1e7883176fa5413b65) was captured by
scripts/seed/archive_seed.sh at HEAD b2035261; gcc of the archive's self-emission
C reproduces the self-emission fixed point `21c957730d268f1e7883176fa5413b65` — both are the same
compiler state at HEAD b2035261. The compiler self-build uses `-ffast` (user
programs default to `-fsafe`), so the recorded fixed point is the `-ffast`
binary. Rebuild recipes + full canonical flag-set requirement (`gcc -m32
-std=c89 -O0 -Wall -Wno-long-long -Wno-pointer-sign
-Wno-implicit-function-declaration`; the fixed point reproduces ONLY with
`-Wall` present) are recorded in `zig1-seed/SEED_README.txt`.
## 2026-10-21 — seed v110 (HEAD dc99f30c)

Seed rotation via scripts/seed/archive_seed.sh. Archive layout: top-level dir
`zig1-seed/` with `zig1`, `gen/` (46 `.c` + 47 `.h` incl.
emitted `zig_special_types.h`, 10307965 bytes), `c_exit.c` (top level),
`runtime/`, `lib/`, `SEED_README.txt`.

| field | value |
|---|---|
| date | 2026-10-21 |
| HEAD | `dc99f30c` |
| seed binary md5 | `21c957730d268f1e7883176fa5413b65` |
| self-emission C | 46 `.c` + 47 `.h` (10307965 bytes) |
| fixed point | `21c957730d268f1e7883176fa5413b65` |
| lib manifest | `lib/manifest.md5` (39 std files; md5 `b51e02d50e85e915aeef6ac18a64da86`) |
| archive md5 | `f9e7221c603fa85ef117c45e7c0edb6b` |

Provenance note: the archived binary (md5 21c957730d268f1e7883176fa5413b65) was captured by
scripts/seed/archive_seed.sh at HEAD dc99f30c; gcc of the archive's self-emission
C reproduces the self-emission fixed point `21c957730d268f1e7883176fa5413b65` — both are the same
compiler state at HEAD dc99f30c. The compiler self-build uses `-ffast` (user
programs default to `-fsafe`), so the recorded fixed point is the `-ffast`
binary. Rebuild recipes + full canonical flag-set requirement (`gcc -m32
-std=c89 -O0 -Wall -Wno-long-long -Wno-pointer-sign
-Wno-implicit-function-declaration`; the fixed point reproduces ONLY with
`-Wall` present) are recorded in `zig1-seed/SEED_README.txt`.
## 2026-10-21 — seed v109 (HEAD b3fec6ed)

Seed rotation via scripts/seed/archive_seed.sh. Archive layout: top-level dir
`zig1-seed/` with `zig1`, `gen/` (46 `.c` + 47 `.h` incl.
emitted `zig_special_types.h`, 10307965 bytes), `c_exit.c` (top level),
`runtime/`, `lib/`, `SEED_README.txt`.

| field | value |
|---|---|
| date | 2026-10-21 |
| HEAD | `b3fec6ed` |
| seed binary md5 | `21c957730d268f1e7883176fa5413b65` |
| self-emission C | 46 `.c` + 47 `.h` (10307965 bytes) |
| fixed point | `21c957730d268f1e7883176fa5413b65` |
| lib manifest | `lib/manifest.md5` (38 std files; md5 `e390dff49f843bda62f221ef6184a1de`) |
| archive md5 | `e4338befc2a95daeca2b103d00da37c3` |

Provenance note: the archived binary (md5 21c957730d268f1e7883176fa5413b65) was captured by
scripts/seed/archive_seed.sh at HEAD b3fec6ed; gcc of the archive's self-emission
C reproduces the self-emission fixed point `21c957730d268f1e7883176fa5413b65` — both are the same
compiler state at HEAD b3fec6ed. The compiler self-build uses `-ffast` (user
programs default to `-fsafe`), so the recorded fixed point is the `-ffast`
binary. Rebuild recipes + full canonical flag-set requirement (`gcc -m32
-std=c89 -O0 -Wall -Wno-long-long -Wno-pointer-sign
-Wno-implicit-function-declaration`; the fixed point reproduces ONLY with
`-Wall` present) are recorded in `zig1-seed/SEED_README.txt`.
## 2026-10-21 — seed v108 (HEAD 4929f70e)

Seed rotation via scripts/seed/archive_seed.sh. Archive layout: top-level dir
`zig1-seed/` with `zig1`, `gen/` (46 `.c` + 47 `.h` incl.
emitted `zig_special_types.h`, 10307965 bytes), `c_exit.c` (top level),
`runtime/`, `lib/`, `SEED_README.txt`.

| field | value |
|---|---|
| date | 2026-10-21 |
| HEAD | `4929f70e` |
| seed binary md5 | `21c957730d268f1e7883176fa5413b65` |
| self-emission C | 46 `.c` + 47 `.h` (10307965 bytes) |
| fixed point | `21c957730d268f1e7883176fa5413b65` |
| lib manifest | `lib/manifest.md5` (37 std files; md5 `f98a25b905994f17c72a39d4507c3d7e`) |
| archive md5 | `f73943f4ce5170e3c776fb985a24cb43` |

Provenance note: the archived binary (md5 21c957730d268f1e7883176fa5413b65) was captured by
scripts/seed/archive_seed.sh at HEAD 4929f70e; gcc of the archive's self-emission
C reproduces the self-emission fixed point `21c957730d268f1e7883176fa5413b65` — both are the same
compiler state at HEAD 4929f70e. The compiler self-build uses `-ffast` (user
programs default to `-fsafe`), so the recorded fixed point is the `-ffast`
binary. Rebuild recipes + full canonical flag-set requirement (`gcc -m32
-std=c89 -O0 -Wall -Wno-long-long -Wno-pointer-sign
-Wno-implicit-function-declaration`; the fixed point reproduces ONLY with
`-Wall` present) are recorded in `zig1-seed/SEED_README.txt`.
## 2026-10-21 — seed v107 (HEAD 65785344)

Seed rotation via scripts/seed/archive_seed.sh. Archive layout: top-level dir
`zig1-seed/` with `zig1`, `gen/` (46 `.c` + 47 `.h` incl.
emitted `zig_special_types.h`, 10307965 bytes), `c_exit.c` (top level),
`runtime/`, `lib/`, `SEED_README.txt`.

| field | value |
|---|---|
| date | 2026-10-21 |
| HEAD | `65785344` |
| seed binary md5 | `21c957730d268f1e7883176fa5413b65` |
| self-emission C | 46 `.c` + 47 `.h` (10307965 bytes) |
| fixed point | `21c957730d268f1e7883176fa5413b65` |
| lib manifest | `lib/manifest.md5` (36 std files; md5 `aac8a4bf651d8d616c2b4ee3400c58f3`) |
| archive md5 | `5ec6e497bb962ff0fdf3145311acc4a1` |

Provenance note: the archived binary (md5 21c957730d268f1e7883176fa5413b65) was captured by
scripts/seed/archive_seed.sh at HEAD 65785344; gcc of the archive's self-emission
C reproduces the self-emission fixed point `21c957730d268f1e7883176fa5413b65` — both are the same
compiler state at HEAD 65785344. The compiler self-build uses `-ffast` (user
programs default to `-fsafe`), so the recorded fixed point is the `-ffast`
binary. Rebuild recipes + full canonical flag-set requirement (`gcc -m32
-std=c89 -O0 -Wall -Wno-long-long -Wno-pointer-sign
-Wno-implicit-function-declaration`; the fixed point reproduces ONLY with
`-Wall` present) are recorded in `zig1-seed/SEED_README.txt`.
## 2026-10-21 — seed v106 (HEAD 51ca1fd2)

Seed rotation via scripts/seed/archive_seed.sh. Archive layout: top-level dir
`zig1-seed/` with `zig1`, `gen/` (46 `.c` + 47 `.h` incl.
emitted `zig_special_types.h`, 10307965 bytes), `c_exit.c` (top level),
`runtime/`, `lib/`, `SEED_README.txt`.

| field | value |
|---|---|
| date | 2026-10-21 |
| HEAD | `51ca1fd2` |
| seed binary md5 | `21c957730d268f1e7883176fa5413b65` |
| self-emission C | 46 `.c` + 47 `.h` (10307965 bytes) |
| fixed point | `21c957730d268f1e7883176fa5413b65` |
| lib manifest | `lib/manifest.md5` (35 std files; md5 `87a231a3a2d511814cf413ae1a5586eb`) |
| archive md5 | `46dff057dd1751a937021dba97ad118f` |

Provenance note: the archived binary (md5 21c957730d268f1e7883176fa5413b65) was captured by
scripts/seed/archive_seed.sh at HEAD 51ca1fd2; gcc of the archive's self-emission
C reproduces the self-emission fixed point `21c957730d268f1e7883176fa5413b65` — both are the same
compiler state at HEAD 51ca1fd2. The compiler self-build uses `-ffast` (user
programs default to `-fsafe`), so the recorded fixed point is the `-ffast`
binary. Rebuild recipes + full canonical flag-set requirement (`gcc -m32
-std=c89 -O0 -Wall -Wno-long-long -Wno-pointer-sign
-Wno-implicit-function-declaration`; the fixed point reproduces ONLY with
`-Wall` present) are recorded in `zig1-seed/SEED_README.txt`.
## 2026-10-20 — seed v105 (HEAD acf76052)

Seed rotation via scripts/seed/archive_seed.sh. Archive layout: top-level dir
`zig1-seed/` with `zig1`, `gen/` (46 `.c` + 47 `.h` incl.
emitted `zig_special_types.h`, 10307965 bytes), `c_exit.c` (top level),
`runtime/`, `lib/`, `SEED_README.txt`.

| field | value |
|---|---|
| date | 2026-10-20 |
| HEAD | `acf76052` |
| seed binary md5 | `21c957730d268f1e7883176fa5413b65` |
| self-emission C | 46 `.c` + 47 `.h` (10307965 bytes) |
| fixed point | `21c957730d268f1e7883176fa5413b65` |
| lib manifest | `lib/manifest.md5` (34 std files; md5 `04710546e55a844f82598fd6d6ab7991`) |
| archive md5 | `cc2ea2be17d018556b4b7dd9f365a73b` |

Provenance note: the archived binary (md5 21c957730d268f1e7883176fa5413b65) was captured by
scripts/seed/archive_seed.sh at HEAD acf76052; gcc of the archive's self-emission
C reproduces the self-emission fixed point `21c957730d268f1e7883176fa5413b65` — both are the same
compiler state at HEAD acf76052. The compiler self-build uses `-ffast` (user
programs default to `-fsafe`), so the recorded fixed point is the `-ffast`
binary. Rebuild recipes + full canonical flag-set requirement (`gcc -m32
-std=c89 -O0 -Wall -Wno-long-long -Wno-pointer-sign
-Wno-implicit-function-declaration`; the fixed point reproduces ONLY with
`-Wall` present) are recorded in `zig1-seed/SEED_README.txt`.
## 2026-10-20 — seed v104 (HEAD 8bb1361d)

Seed rotation via scripts/seed/archive_seed.sh. Archive layout: top-level dir
`zig1-seed/` with `zig1`, `gen/` (46 `.c` + 47 `.h` incl.
emitted `zig_special_types.h`, 10307965 bytes), `c_exit.c` (top level),
`runtime/`, `lib/`, `SEED_README.txt`.

| field | value |
|---|---|
| date | 2026-10-20 |
| HEAD | `8bb1361d` |
| seed binary md5 | `21c957730d268f1e7883176fa5413b65` |
| self-emission C | 46 `.c` + 47 `.h` (10307965 bytes) |
| fixed point | `21c957730d268f1e7883176fa5413b65` |
| lib manifest | `lib/manifest.md5` (34 std files; md5 `3e8b6f6628973414425c1df63f8c4455`) |
| archive md5 | `cfe7fe31edd16a526d549201dfbd7c2b` |

Provenance note: the archived binary (md5 21c957730d268f1e7883176fa5413b65) was captured by
scripts/seed/archive_seed.sh at HEAD 8bb1361d; gcc of the archive's self-emission
C reproduces the self-emission fixed point `21c957730d268f1e7883176fa5413b65` — both are the same
compiler state at HEAD 8bb1361d. The compiler self-build uses `-ffast` (user
programs default to `-fsafe`), so the recorded fixed point is the `-ffast`
binary. Rebuild recipes + full canonical flag-set requirement (`gcc -m32
-std=c89 -O0 -Wall -Wno-long-long -Wno-pointer-sign
-Wno-implicit-function-declaration`; the fixed point reproduces ONLY with
`-Wall` present) are recorded in `zig1-seed/SEED_README.txt`.
## 2026-10-19 — seed v103 (HEAD 21443e21)

Seed rotation via scripts/seed/archive_seed.sh. Archive layout: top-level dir
`zig1-seed/` with `zig1`, `gen/` (46 `.c` + 47 `.h` incl.
emitted `zig_special_types.h`, 10256124 bytes), `c_exit.c` (top level),
`runtime/`, `lib/`, `SEED_README.txt`.

| field | value |
|---|---|
| date | 2026-10-19 |
| HEAD | `21443e21` |
| seed binary md5 | `b299b4b435e624d0ddbd2edde681cbc3` |
| self-emission C | 46 `.c` + 47 `.h` (10256124 bytes) |
| fixed point | `b299b4b435e624d0ddbd2edde681cbc3` |
| lib manifest | `lib/manifest.md5` (33 std files; md5 `74771fa978e6644b194690783bff21cc`) |
| archive md5 | `c4d1e7a6f3d7403dee2c683a3a5ab438` |

Provenance note: the archived binary (md5 b299b4b435e624d0ddbd2edde681cbc3) was captured by
scripts/seed/archive_seed.sh at HEAD 21443e21; gcc of the archive's self-emission
C reproduces the self-emission fixed point `b299b4b435e624d0ddbd2edde681cbc3` — both are the same
compiler state at HEAD 21443e21. The compiler self-build uses `-ffast` (user
programs default to `-fsafe`), so the recorded fixed point is the `-ffast`
binary. Rebuild recipes + full canonical flag-set requirement (`gcc -m32
-std=c89 -O0 -Wall -Wno-long-long -Wno-pointer-sign
-Wno-implicit-function-declaration`; the fixed point reproduces ONLY with
`-Wall` present) are recorded in `zig1-seed/SEED_README.txt`.
## 2026-10-19 — seed v102 (HEAD 389e0030)

Seed rotation via scripts/seed/archive_seed.sh. Archive layout: top-level dir
`zig1-seed/` with `zig1`, `gen/` (46 `.c` + 47 `.h` incl.
emitted `zig_special_types.h`, 10256124 bytes), `c_exit.c` (top level),
`runtime/`, `lib/`, `SEED_README.txt`.

| field | value |
|---|---|
| date | 2026-10-19 |
| HEAD | `389e0030` |
| seed binary md5 | `b299b4b435e624d0ddbd2edde681cbc3` |
| self-emission C | 46 `.c` + 47 `.h` (10256124 bytes) |
| fixed point | `b299b4b435e624d0ddbd2edde681cbc3` |
| archive md5 | `702f34d87b7e6bf401dd206d2517dbee` |

Provenance note: the archived binary (md5 b299b4b435e624d0ddbd2edde681cbc3) was captured by
scripts/seed/archive_seed.sh at HEAD 389e0030; gcc of the archive's self-emission
C reproduces the self-emission fixed point `b299b4b435e624d0ddbd2edde681cbc3` — both are the same
compiler state at HEAD 389e0030. The compiler self-build uses `-ffast` (user
programs default to `-fsafe`), so the recorded fixed point is the `-ffast`
binary. Rebuild recipes + full canonical flag-set requirement (`gcc -m32
-std=c89 -O0 -Wall -Wno-long-long -Wno-pointer-sign
-Wno-implicit-function-declaration`; the fixed point reproduces ONLY with
`-Wall` present) are recorded in `zig1-seed/SEED_README.txt`.
## 2026-10-18 — seed v101 (HEAD dfc773a1)

Seed rotation via scripts/seed/archive_seed.sh. Archive layout: top-level dir
`zig1-seed/` with `zig1`, `gen/` (46 `.c` + 47 `.h` incl.
emitted `zig_special_types.h`, 10256124 bytes), `c_exit.c` (top level),
`runtime/`, `lib/`, `SEED_README.txt`.

| field | value |
|---|---|
| date | 2026-10-18 |
| HEAD | `dfc773a1` |
| seed binary md5 | `b299b4b435e624d0ddbd2edde681cbc3` |
| self-emission C | 46 `.c` + 47 `.h` (10256124 bytes) |
| fixed point | `b299b4b435e624d0ddbd2edde681cbc3` |
| archive md5 | `378f5ea01db25ec69f455fbce52bc947` |

Provenance note: the archived binary (md5 b299b4b435e624d0ddbd2edde681cbc3) was captured by
scripts/seed/archive_seed.sh at HEAD dfc773a1; gcc of the archive's self-emission
C reproduces the self-emission fixed point `b299b4b435e624d0ddbd2edde681cbc3` — both are the same
compiler state at HEAD dfc773a1. The compiler self-build uses `-ffast` (user
programs default to `-fsafe`), so the recorded fixed point is the `-ffast`
binary. Rebuild recipes + full canonical flag-set requirement (`gcc -m32
-std=c89 -O0 -Wall -Wno-long-long -Wno-pointer-sign
-Wno-implicit-function-declaration`; the fixed point reproduces ONLY with
`-Wall` present) are recorded in `zig1-seed/SEED_README.txt`.
## 2026-10-18 — seed v100 (HEAD 7bbf2116)

Seed rotation via scripts/seed/archive_seed.sh. Archive layout: top-level dir
`zig1-seed/` with `zig1`, `gen/` (46 `.c` + 47 `.h` incl.
emitted `zig_special_types.h`, 10253723 bytes), `c_exit.c` (top level),
`runtime/`, `lib/`, `SEED_README.txt`.

| field | value |
|---|---|
| date | 2026-10-18 |
| HEAD | `7bbf2116` |
| seed binary md5 | `99e903494c716c1ea9d779b646303d1d` |
| self-emission C | 46 `.c` + 47 `.h` (10253723 bytes) |
| fixed point | `99e903494c716c1ea9d779b646303d1d` |
| archive md5 | `c73fef7b07fb4a6fc57dafa77821e47c` |

Provenance note: the archived binary (md5 99e903494c716c1ea9d779b646303d1d) was captured by
scripts/seed/archive_seed.sh from the working tree that became commit
`7bbf2116` (the post-fix OpenWatcom mapping); the capture happened before that
commit, when `git rev-parse HEAD` was `0595fab4`, which is why the original
entry's HEAD label was capture-time rather than source-time. The actual source
state is `7bbf2116`, and gcc of the archive's self-emission C reproduces the
self-emission fixed point `99e903494c716c1ea9d779b646303d1d` — both are the
same compiler state at `7bbf2116`. The compiler self-build uses `-ffast` (user
programs default to `-fsafe`), so the recorded fixed point is the `-ffast`
binary. Rebuild recipes + full canonical flag-set requirement (`gcc -m32
-std=c89 -O0 -Wall -Wno-long-long -Wno-pointer-sign
-Wno-implicit-function-declaration`; the fixed point reproduces ONLY with
`-Wall` present) are recorded in `zig1-seed/SEED_README.txt`.
## 2026-10-18 — seed v99 (HEAD f244c7c5)

Seed rotation via scripts/seed/archive_seed.sh. Archive layout: top-level dir
`zig1-seed/` with `zig1`, `gen/` (46 `.c` + 47 `.h` incl.
emitted `zig_special_types.h`, 10253743 bytes), `c_exit.c` (top level),
`runtime/`, `lib/`, `SEED_README.txt`.

| field | value |
|---|---|
| date | 2026-10-18 |
| HEAD | `f244c7c5` |
| seed binary md5 | `1ef248e0c9782cfe646de73634dae4d8` |
| self-emission C | 46 `.c` + 47 `.h` (10253743 bytes) |
| fixed point | `1ef248e0c9782cfe646de73634dae4d8` |
| archive md5 | `c51e8019d0a1a7088c714aa1ff39fa09` |

Provenance note: the archived binary (md5 1ef248e0c9782cfe646de73634dae4d8) was captured by
scripts/seed/archive_seed.sh at HEAD f244c7c5; gcc of the archive's self-emission
C reproduces the self-emission fixed point `1ef248e0c9782cfe646de73634dae4d8` — both are the same
compiler state at HEAD f244c7c5. The compiler self-build uses `-ffast` (user
programs default to `-fsafe`), so the recorded fixed point is the `-ffast`
binary. Rebuild recipes + full canonical flag-set requirement (`gcc -m32
-std=c89 -O0 -Wall -Wno-long-long -Wno-pointer-sign
-Wno-implicit-function-declaration`; the fixed point reproduces ONLY with
`-Wall` present) are recorded in `zig1-seed/SEED_README.txt`.
## 2026-10-16 — seed v98 (HEAD 313372d3)

Seed rotation via scripts/seed/archive_seed.sh. Archive layout: top-level dir
`zig1-seed/` with `zig1`, `gen/` (46 `.c` + 47 `.h` incl.
emitted `zig_special_types.h`, 9900439 bytes), `c_exit.c` (top level),
`runtime/`, `lib/`, `SEED_README.txt`.

| field | value |
|---|---|
| date | 2026-10-16 |
| HEAD | `313372d3` |
| seed binary md5 | `f18b69ece1917bf970a036b276e5e403` |
| self-emission C | 46 `.c` + 47 `.h` (9900439 bytes) |
| fixed point | `f18b69ece1917bf970a036b276e5e403` |
| archive md5 | `74acfdadbb48fb658e59cf8da6ad678a` |

Provenance note: the archived binary (md5 f18b69ece1917bf970a036b276e5e403) was captured by
scripts/seed/archive_seed.sh at HEAD 313372d3; gcc of the archive's self-emission
C reproduces the self-emission fixed point `f18b69ece1917bf970a036b276e5e403` — both are the same
compiler state at HEAD 313372d3. The compiler self-build uses `-ffast` (user
programs default to `-fsafe`), so the recorded fixed point is the `-ffast`
binary. Rebuild recipes + full canonical flag-set requirement (`gcc -m32
-std=c89 -O0 -Wall -Wno-long-long -Wno-pointer-sign
-Wno-implicit-function-declaration`; the fixed point reproduces ONLY with
`-Wall` present) are recorded in `zig1-seed/SEED_README.txt`.
## 2026-10-11 — seed v97 (HEAD 875b9a9e)

Seed rotation via scripts/seed/archive_seed.sh. Archive layout: top-level dir
`zig1-seed/` with `zig1`, `gen/` (45 `.c` + 46 `.h` incl.
emitted `zig_special_types.h`, 9821325 bytes), `c_exit.c` (top level),
`runtime/`, `lib/`, `SEED_README.txt`.

| field | value |
|---|---|
| date | 2026-10-11 |
| HEAD | `875b9a9e` |
| seed binary md5 | `bafbba9454cd2b134bdc3d50c65384e0` |
| self-emission C | 45 `.c` + 46 `.h` (9821325 bytes) |
| fixed point | `bafbba9454cd2b134bdc3d50c65384e0` |
| archive md5 | `7a2630c7ef37de664dd3a4da310c94cd` |

Provenance note: the archived binary (md5 bafbba9454cd2b134bdc3d50c65384e0) was captured by
scripts/seed/archive_seed.sh at HEAD 875b9a9e; gcc of the archive's self-emission
C reproduces the self-emission fixed point `bafbba9454cd2b134bdc3d50c65384e0` — both are the same
compiler state at HEAD 875b9a9e. The compiler self-build uses `-ffast` (user
programs default to `-fsafe`), so the recorded fixed point is the `-ffast`
binary. Rebuild recipes + full canonical flag-set requirement (`gcc -m32
-std=c89 -O0 -Wall -Wno-long-long -Wno-pointer-sign
-Wno-implicit-function-declaration`; the fixed point reproduces ONLY with
`-Wall` present) are recorded in `zig1-seed/SEED_README.txt`.
## 2026-10-10 — seed v96 (HEAD 94eb3567)

Seed rotation via scripts/seed/archive_seed.sh. Archive layout: top-level dir
`zig1-seed/` with `zig1`, `gen/` (45 `.c` + 46 `.h` incl.
emitted `zig_special_types.h`, 9819137 bytes), `c_exit.c` (top level),
`runtime/`, `lib/`, `SEED_README.txt`.

| field | value |
|---|---|
| date | 2026-10-10 |
| HEAD | `94eb3567` |
| seed binary md5 | `46e3e7af98af3b5ff2a960c7c96025e3` |
| self-emission C | 45 `.c` + 46 `.h` (9819137 bytes) |
| fixed point | `46e3e7af98af3b5ff2a960c7c96025e3` |
| archive md5 | `b55f6140612196e4baf86d5deaca66ec` |

Provenance note: the archived binary (md5 46e3e7af98af3b5ff2a960c7c96025e3) was captured by
scripts/seed/archive_seed.sh at HEAD 94eb3567; gcc of the archive's self-emission
C reproduces the self-emission fixed point `46e3e7af98af3b5ff2a960c7c96025e3` — both are the same
compiler state at HEAD 94eb3567. The compiler self-build uses `-ffast` (user
programs default to `-fsafe`), so the recorded fixed point is the `-ffast`
binary. Rebuild recipes + full canonical flag-set requirement (`gcc -m32
-std=c89 -O0 -Wall -Wno-long-long -Wno-pointer-sign
-Wno-implicit-function-declaration`; the fixed point reproduces ONLY with
`-Wall` present) are recorded in `zig1-seed/SEED_README.txt`.
## 2026-10-10 — seed v95 (HEAD f960d174)

Seed rotation via scripts/seed/archive_seed.sh. Archive layout: top-level dir
`zig1-seed/` with `zig1`, `gen/` (45 `.c` + 46 `.h` incl.
emitted `zig_special_types.h`, 9818402 bytes), `c_exit.c` (top level),
`runtime/`, `lib/`, `SEED_README.txt`.

| field | value |
|---|---|
| date | 2026-10-10 |
| HEAD | `f960d174` |
| seed binary md5 | `6efc9524c6caf0bb9484565082170ed5` |
| self-emission C | 45 `.c` + 46 `.h` (9818402 bytes) |
| fixed point | `6efc9524c6caf0bb9484565082170ed5` |
| archive md5 | `ee4e9763d51f76b2b2058dd254377b20` |

Provenance note: the archived binary (md5 6efc9524c6caf0bb9484565082170ed5) was captured by
scripts/seed/archive_seed.sh at HEAD f960d174; gcc of the archive's self-emission
C reproduces the self-emission fixed point `6efc9524c6caf0bb9484565082170ed5` — both are the same
compiler state at HEAD f960d174. The compiler self-build uses `-ffast` (user
programs default to `-fsafe`), so the recorded fixed point is the `-ffast`
binary. Rebuild recipes + full canonical flag-set requirement (`gcc -m32
-std=c89 -O0 -Wall -Wno-long-long -Wno-pointer-sign
-Wno-implicit-function-declaration`; the fixed point reproduces ONLY with
`-Wall` present) are recorded in `zig1-seed/SEED_README.txt`.
## 2026-10-08 — seed v94 (HEAD 78dd4593)

Seed rotation via scripts/seed/archive_seed.sh. Archive layout: top-level dir
`zig1-seed/` with `zig1`, `gen/` (45 `.c` + 46 `.h` incl.
emitted `zig_special_types.h`, 9793884 bytes), `c_exit.c` (top level),
`runtime/`, `lib/`, `SEED_README.txt`.

| field | value |
|---|---|
| date | 2026-10-08 |
| HEAD | `78dd4593` |
| seed binary md5 | `296c48f676deec290387b57132e4e2bd` |
| self-emission C | 45 `.c` + 46 `.h` (9793884 bytes) |
| fixed point | `296c48f676deec290387b57132e4e2bd` |
| archive md5 | `16ca54bd63320a4ec1d8e8aee3fe2c43` |

Provenance note: the archived binary (md5 296c48f676deec290387b57132e4e2bd) was captured by
scripts/seed/archive_seed.sh at HEAD 78dd4593; gcc of the archive's self-emission
C reproduces the self-emission fixed point `296c48f676deec290387b57132e4e2bd` — both are the same
compiler state at HEAD 78dd4593. The compiler self-build uses `-ffast` (user
programs default to `-fsafe`), so the recorded fixed point is the `-ffast`
binary. Rebuild recipes + full canonical flag-set requirement (`gcc -m32
-std=c89 -O0 -Wall -Wno-long-long -Wno-pointer-sign
-Wno-implicit-function-declaration`; the fixed point reproduces ONLY with
`-Wall` present) are recorded in `zig1-seed/SEED_README.txt`.

## 2026-10-07 — seed v93 (HEAD b8cd33da)

Seed rotation via scripts/seed/archive_seed.sh. Archive layout: top-level dir
`zig1-seed/` with `zig1`, `gen/` (45 `.c` + 46 `.h` incl.
emitted `zig_special_types.h`, 9815724 bytes), `c_exit.c` (top level),
`runtime/`, `lib/`, `SEED_README.txt`.

| field | value |
|---|---|
| date | 2026-10-07 |
| HEAD | `b8cd33da` |
| seed binary md5 | `639902d5146233091f6b2f98508ce3eb` |
| self-emission C | 45 `.c` + 46 `.h` (9815724 bytes) |
| fixed point | `639902d5146233091f6b2f98508ce3eb` |
| archive md5 | `e1955908f3aa58992592f9c021c36d42` |

Provenance note: the archived binary (md5 639902d5146233091f6b2f98508ce3eb) was captured by
scripts/seed/archive_seed.sh at HEAD b8cd33da; gcc of the archive's self-emission
C reproduces the self-emission fixed point `639902d5146233091f6b2f98508ce3eb` — both are the same
compiler state at HEAD b8cd33da. Fix-wave re-rotation (guard the narrowed
`Type.payload_idx`/`Type.alignment` casts): the fixed point moved from
`44b8e7fff5a115743ab5c62adb849555` (prior v93 emission at HEAD `d69f10e7`, archive md5
`84d295ae04e20c4b722ed219bd9a74f1`) to `639902d5146233091f6b2f98508ce3eb`; this is the same
plan closeout re-baselined, so the entry remains v93. The compiler self-build uses `-ffast` (user
programs default to `-fsafe`), so the recorded fixed point is the `-ffast`
binary. Rebuild recipes + full canonical flag-set requirement (`gcc -m32
-std=c89 -O0 -Wall -Wno-long-long -Wno-pointer-sign
-Wno-implicit-function-declaration`; the fixed point reproduces ONLY with
`-Wall` present) are recorded in `zig1-seed/SEED_README.txt`.

## 2026-10-06 — seed v92 (HEAD f094c1ab)

Seed rotation via scripts/seed/archive_seed.sh. Archive layout: top-level dir
`zig1-seed/` with `zig1`, `gen/` (45 `.c` + 46 `.h` incl.
emitted `zig_special_types.h`, 9763768 bytes), `c_exit.c` (top level),
`runtime/`, `lib/`, `SEED_README.txt`.

| field | value |
|---|---|
| date | 2026-10-06 |
| HEAD | `f094c1ab` |
| seed binary md5 | `d40e875a7ba3aa55d441af56006f6023` |
| self-emission C | 45 `.c` + 46 `.h` (9763768 bytes) |
| fixed point | `d40e875a7ba3aa55d441af56006f6023` |
| archive md5 | `3cacdd44df75c0ce96abfd51af93f928` |

Provenance note: the archived binary (md5 d40e875a7ba3aa55d441af56006f6023) was captured by
scripts/seed/archive_seed.sh at HEAD f094c1ab; gcc of the archive's self-emission
C reproduces the self-emission fixed point `d40e875a7ba3aa55d441af56006f6023` — both are the same
compiler state at HEAD f094c1ab. The compiler self-build uses `-ffast` (user
programs default to `-fsafe`), so the recorded fixed point is the `-ffast`
binary. Rebuild recipes + full canonical flag-set requirement (`gcc -m32
-std=c89 -O0 -Wall -Wno-long-long -Wno-pointer-sign
-Wno-implicit-function-declaration`; the fixed point reproduces ONLY with
`-Wall` present) are recorded in `zig1-seed/SEED_README.txt`.
## 2026-10-05 — seed v91 (HEAD 52672f75)

Seed rotation via scripts/seed/archive_seed.sh. Archive layout: top-level dir
`zig1-seed/` with `zig1`, `gen/` (45 `.c` + 46 `.h` incl.
emitted `zig_special_types.h`, 10422002 bytes), `c_exit.c` (top level),
`runtime/`, `lib/`, `SEED_README.txt`.

| field | value |
|---|---|
| date | 2026-10-05 |
| HEAD | `52672f75` |
| seed binary md5 | `0b8c3e4ac0b1fc49c0bdf8caf9d39945` |
| self-emission C | 45 `.c` + 46 `.h` (10422002 bytes) |
| fixed point | `0b8c3e4ac0b1fc49c0bdf8caf9d39945` |
| archive md5 | `39669954c928df59263e5d03cbaacd1d` |

Provenance note: the archived binary (md5 0b8c3e4ac0b1fc49c0bdf8caf9d39945) was captured by
scripts/seed/archive_seed.sh at HEAD 52672f75; gcc of the archive's self-emission
C reproduces the self-emission fixed point `0b8c3e4ac0b1fc49c0bdf8caf9d39945` — both are the same
compiler state at HEAD 52672f75. The compiler self-build uses `-ffast` (user
programs default to `-fsafe`), so the recorded fixed point is the `-ffast`
binary. Rebuild recipes + full canonical flag-set requirement (`gcc -m32
-std=c89 -O0 -Wall -Wno-long-long -Wno-pointer-sign
-Wno-implicit-function-declaration`; the fixed point reproduces ONLY with
`-Wall` present) are recorded in `zig1-seed/SEED_README.txt`.
## 2026-10-03 — seed v90 (HEAD 0538e450)

Seed rotation via scripts/seed/archive_seed.sh. Archive layout: top-level dir
`zig1-seed/` with `zig1`, `gen/` (45 `.c` + 46 `.h` incl.
emitted `zig_special_types.h`, 10377021 bytes), `c_exit.c` (top level),
`runtime/`, `lib/`, `SEED_README.txt`.

| field | value |
|---|---|
| date | 2026-10-03 |
| HEAD | `0538e450` |
| seed binary md5 | `f78bebc448e267b32419afdb13afb386` |
| self-emission C | 45 `.c` + 46 `.h` (10377021 bytes) |
| fixed point | `f78bebc448e267b32419afdb13afb386` |
| archive md5 | `430f4f9ce415852b4ca5b1bb01261189` |

Provenance note: the archived binary (md5 f78bebc448e267b32419afdb13afb386) was captured by
scripts/seed/archive_seed.sh at HEAD 0538e450; gcc of the archive's self-emission
C reproduces the self-emission fixed point `f78bebc448e267b32419afdb13afb386` — both are the same
compiler state at HEAD 0538e450. The compiler self-build uses `-ffast` (user
programs default to `-fsafe`), so the recorded fixed point is the `-ffast`
binary. Rebuild recipes + full canonical flag-set requirement (`gcc -m32
-std=c89 -O0 -Wall -Wno-long-long -Wno-pointer-sign
-Wno-implicit-function-declaration`; the fixed point reproduces ONLY with
`-Wall` present) are recorded in `zig1-seed/SEED_README.txt`.
## 2026-09-30 — seed v89 (HEAD 28106aaa)

Seed rotation via scripts/seed/archive_seed.sh. Archive layout: top-level dir
`zig1-seed/` with `zig1`, `gen/` (45 `.c` + 46 `.h` incl.
emitted `zig_special_types.h`, 10367719 bytes), `c_exit.c` (top level),
`runtime/`, `lib/`, `SEED_README.txt`.

| field | value |
|---|---|
| date | 2026-09-30 |
| HEAD | `28106aaa` |
| seed binary md5 | `8216fedc8dd69db084d453be80f3c010` |
| self-emission C | 45 `.c` + 46 `.h` (10367719 bytes) |
| fixed point | `8216fedc8dd69db084d453be80f3c010` |
| archive md5 | `a1549c5b5d9ad23da4d41d214d9ad3c5` |

Provenance note: the archived binary (md5 8216fedc8dd69db084d453be80f3c010) was captured by
scripts/seed/archive_seed.sh at HEAD 28106aaa; gcc of the archive's self-emission
C reproduces the self-emission fixed point `8216fedc8dd69db084d453be80f3c010` — both are the same
compiler state at HEAD 28106aaa. The compiler self-build uses `-ffast` (user
programs default to `-fsafe`), so the recorded fixed point is the `-ffast`
binary. Rebuild recipes + full canonical flag-set requirement (`gcc -m32
-std=c89 -O0 -Wall -Wno-long-long -Wno-pointer-sign
-Wno-implicit-function-declaration`; the fixed point reproduces ONLY with
`-Wall` present) are recorded in `zig1-seed/SEED_README.txt`.
## 2026-09-25 — seed v88 (HEAD 1b04d679)

Seed rotation via scripts/seed/archive_seed.sh. Archive layout: top-level dir
`zig1-seed/` with `zig1`, `gen/` (45 `.c` + 46 `.h` incl.
emitted `zig_special_types.h`, 9832934 bytes), `c_exit.c` (top level),
`runtime/`, `lib/`, `SEED_README.txt`.

| field | value |
|---|---|
| date | 2026-09-25 |
| HEAD | `1b04d679` |
| seed binary md5 | `a3928c11f9852db9646dff39006ef654` |
| self-emission C | 45 `.c` + 46 `.h` (9832934 bytes) |
| fixed point | `a3928c11f9852db9646dff39006ef654` |
| archive md5 | `3db5ef392ecc349304ffdf14c618e530` |

Provenance note: the archived binary (md5 a3928c11f9852db9646dff39006ef654) was captured by
scripts/seed/archive_seed.sh at HEAD 1b04d679; gcc of the archive's self-emission
C reproduces the self-emission fixed point `a3928c11f9852db9646dff39006ef654` — both are the same
compiler state at HEAD 1b04d679. The compiler self-build uses `-ffast` (user
programs default to `-fsafe`), so the recorded fixed point is the `-ffast`
binary. Rebuild recipes + full canonical flag-set requirement (`gcc -m32
-std=c89 -O0 -Wall -Wno-long-long -Wno-pointer-sign
-Wno-implicit-function-declaration`; the fixed point reproduces ONLY with
`-Wall` present) are recorded in `zig1-seed/SEED_README.txt`.
## 2026-09-25 — seed v87 (HEAD a9645b1c)

Seed rotation via scripts/seed/archive_seed.sh. Archive layout: top-level dir
`zig1-seed/` with `zig1`, `gen/` (45 `.c` + 46 `.h` incl.
emitted `zig_special_types.h`, 9825800 bytes), `c_exit.c` (top level),
`runtime/`, `lib/`, `SEED_README.txt`.

| field | value |
|---|---|
| date | 2026-09-25 |
| HEAD | `a9645b1c` |
| seed binary md5 | `e3f8d737a69d9ba2653eb6ad6aec2b58` |
| self-emission C | 45 `.c` + 46 `.h` (9825800 bytes) |
| fixed point | `e3f8d737a69d9ba2653eb6ad6aec2b58` |
| archive md5 | `71f3e3c652a2cba07fdedb4cbc5dff3b` |

Provenance note: the archived binary (md5 e3f8d737a69d9ba2653eb6ad6aec2b58) was captured by
scripts/seed/archive_seed.sh at HEAD a9645b1c; gcc of the archive's self-emission
C reproduces the self-emission fixed point `e3f8d737a69d9ba2653eb6ad6aec2b58` — both are the same
compiler state at HEAD a9645b1c. The compiler self-build uses `-ffast` (user
programs default to `-fsafe`), so the recorded fixed point is the `-ffast`
binary. Rebuild recipes + full canonical flag-set requirement (`gcc -m32
-std=c89 -O0 -Wall -Wno-long-long -Wno-pointer-sign
-Wno-implicit-function-declaration`; the fixed point reproduces ONLY with
`-Wall` present) are recorded in `zig1-seed/SEED_README.txt`.

## 2026-09-25 — seed v86 (HEAD cdae8b36)

Seed rotation via scripts/seed/archive_seed.sh. Archive layout: top-level dir
`zig1-seed/` with `zig1`, `gen/` (45 `.c` + 46 `.h` incl.
emitted `zig_special_types.h`, 9762739 bytes), `c_exit.c` (top level),
`runtime/`, `lib/`, `SEED_README.txt`.

| field | value |
|---|---|
| date | 2026-09-25 |
| HEAD | `cdae8b36` |
| seed binary md5 | `5d3ca7256a7e43bb7f9685a34365865a` |
| self-emission C | 45 `.c` + 46 `.h` (9762739 bytes) |
| fixed point | `5d3ca7256a7e43bb7f9685a34365865a` |
| archive md5 | `28c8ab28662a990848eb980e112457b2` |

Provenance note: the archived binary (md5 5d3ca7256a7e43bb7f9685a34365865a) was captured by
scripts/seed/archive_seed.sh at HEAD cdae8b36; gcc of the archive's self-emission
C reproduces the self-emission fixed point `5d3ca7256a7e43bb7f9685a34365865a` — both are the same
compiler state at HEAD cdae8b36. The compiler self-build uses `-ffast` (user
programs default to `-fsafe`), so the recorded fixed point is the `-ffast`
binary. Rebuild recipes + full canonical flag-set requirement (`gcc -m32
-std=c89 -O0 -Wall -Wno-long-long -Wno-pointer-sign
-Wno-implicit-function-declaration`; the fixed point reproduces ONLY with
`-Wall` present) are recorded in `zig1-seed/SEED_README.txt`.

## 2026-09-25 — seed v85 (HEAD 1a2d8853)

Seed rotation via scripts/seed/archive_seed.sh. Archive layout: top-level dir
`zig1-seed/` with `zig1`, `gen/` (45 `.c` + 46 `.h` incl.
emitted `zig_special_types.h`, 9752421 bytes), `c_exit.c` (top level),
`runtime/`, `lib/`, `SEED_README.txt`.

| field | value |
|---|---|
| date | 2026-09-25 |
| HEAD | `1a2d8853` |
| seed binary md5 | `96c723914ec8b48fddc2a1d039e49141` |
| self-emission C | 45 `.c` + 46 `.h` (9752421 bytes) |
| fixed point | `96c723914ec8b48fddc2a1d039e49141` |
| archive md5 | `c544e251b044aef37083ca846d65be05` |

Provenance note: the archived binary (md5 96c723914ec8b48fddc2a1d039e49141) was captured by
scripts/seed/archive_seed.sh at HEAD 1a2d8853; gcc of the archive's self-emission
C reproduces the self-emission fixed point `96c723914ec8b48fddc2a1d039e49141` — both are the same
compiler state at HEAD 1a2d8853. The compiler self-build uses `-ffast` (user
programs default to `-fsafe`), so the recorded fixed point is the `-ffast`
binary. Rebuild recipes + full canonical flag-set requirement (`gcc -m32
-std=c89 -O0 -Wall -Wno-long-long -Wno-pointer-sign
-Wno-implicit-function-declaration`; the fixed point reproduces ONLY with
`-Wall` present) are recorded in `zig1-seed/SEED_README.txt`.

## 2026-09-24 — seed v84 (HEAD c3b1401f)

Seed rotation via scripts/seed/archive_seed.sh. Archive layout: top-level dir
`zig1-seed/` with `zig1`, `gen/` (45 `.c` + 46 `.h` incl.
emitted `zig_special_types.h`, 9477730 bytes), `c_exit.c` (top level),
`runtime/`, `lib/`, `SEED_README.txt`.

| field | value |
|---|---|
| date | 2026-09-24 |
| HEAD | `c3b1401f` |
| seed binary md5 | `b7a7da2673d60852006e9ea87909be1d` |
| self-emission C | 45 `.c` + 46 `.h` (9477730 bytes) |
| fixed point | `b7a7da2673d60852006e9ea87909be1d` |
| archive md5 | `50501c4bc00beed12ce06688d3b64664` |

Provenance note: the archived binary (md5 b7a7da2673d60852006e9ea87909be1d) was captured by
scripts/seed/archive_seed.sh at HEAD c3b1401f; gcc of the archive's self-emission
C reproduces the self-emission fixed point `b7a7da2673d60852006e9ea87909be1d` — both are the same
compiler state at HEAD c3b1401f. The compiler self-build uses `-ffast` (user
programs default to `-fsafe`), so the recorded fixed point is the `-ffast`
binary. Rebuild recipes + full canonical flag-set requirement (`gcc -m32
-std=c89 -O0 -Wall -Wno-long-long -Wno-pointer-sign
-Wno-implicit-function-declaration`; the fixed point reproduces ONLY with
`-Wall` present) are recorded in `zig1-seed/SEED_README.txt`.

## 2026-09-24 — seed v83 (HEAD 48006701)

Seed rotation via scripts/seed/archive_seed.sh. Archive layout: top-level dir
`zig1-seed/` with `zig1`, `gen/` (45 `.c` + 46 `.h` incl.
emitted `zig_special_types.h`, 9298528 bytes), `c_exit.c` (top level),
`runtime/`, `lib/`, `SEED_README.txt`.

| field | value |
|---|---|
| date | 2026-09-24 |
| HEAD | `48006701` |
| seed binary md5 | `1e389c5739aea89550d149015f0031d3` |
| self-emission C | 45 `.c` + 46 `.h` (9298528 bytes) |
| fixed point | `1e389c5739aea89550d149015f0031d3` |
| archive md5 | `c58ff2130cb8128bba205d1777d51413` |

Provenance note: the archived binary (md5 1e389c5739aea89550d149015f0031d3) was captured by
scripts/seed/archive_seed.sh at HEAD 48006701; gcc of the archive's self-emission
C reproduces the self-emission fixed point `1e389c5739aea89550d149015f0031d3` — both are the same
compiler state at HEAD 48006701. The compiler self-build uses `-ffast` (user
programs default to `-fsafe`), so the recorded fixed point is the `-ffast`
binary. Rebuild recipes + full canonical flag-set requirement (`gcc -m32
-std=c89 -O0 -Wall -Wno-long-long -Wno-pointer-sign
-Wno-implicit-function-declaration`; the fixed point reproduces ONLY with
`-Wall` present) are recorded in `zig1-seed/SEED_README.txt`.
## 2026-09-23 — seed v82 (HEAD 52e907be)

Seed rotation via scripts/seed/archive_seed.sh. Archive layout: top-level dir
`zig1-seed/` with `zig1`, `gen/` (45 `.c` + 46 `.h` incl.
emitted `zig_special_types.h`, 9226676 bytes), `c_exit.c` (top level),
`runtime/`, `lib/`, `SEED_README.txt`.

| field | value |
|---|---|
| date | 2026-09-23 |
| HEAD | `52e907be` |
| seed binary md5 | `cd38f3167ca3e39982cc2d817b16dc70` |
| self-emission C | 45 `.c` + 46 `.h` (9226676 bytes) |
| fixed point | `cd38f3167ca3e39982cc2d817b16dc70` |
| archive md5 | `98a8b0ef292b31486a37f97c75938f30` |

Provenance note: the archived binary (md5 cd38f3167ca3e39982cc2d817b16dc70) was captured by
scripts/seed/archive_seed.sh at HEAD 52e907be; gcc of the archive's self-emission
C reproduces the self-emission fixed point `cd38f3167ca3e39982cc2d817b16dc70` — both are the same
compiler state at HEAD 52e907be. The compiler self-build uses `-ffast` (user
programs default to `-fsafe`), so the recorded fixed point is the `-ffast`
binary. Rebuild recipes + full canonical flag-set requirement (`gcc -m32
-std=c89 -O0 -Wall -Wno-long-long -Wno-pointer-sign
-Wno-implicit-function-declaration`; the fixed point reproduces ONLY with
`-Wall` present) are recorded in `zig1-seed/SEED_README.txt`.
## 2026-09-23 — seed v81 (HEAD 9873171a)

Seed rotation via scripts/seed/archive_seed.sh. Archive layout: top-level dir
`zig1-seed/` with `zig1`, `gen/` (45 `.c` + 46 `.h` incl.
emitted `zig_special_types.h`, 9226589 bytes), `c_exit.c` (top level),
`runtime/`, `lib/`, `SEED_README.txt`.

| field | value |
|---|---|
| date | 2026-09-23 |
| HEAD | `9873171a` |
| seed binary md5 | `8b43b3b4f111cb9bedfebdd49309bd6a` |
| self-emission C | 45 `.c` + 46 `.h` (9226589 bytes) |
| fixed point | `8b43b3b4f111cb9bedfebdd49309bd6a` |
| archive md5 | `617ee1623331f79aae7957ff8e9138b4` |

Provenance note: the archived binary (md5 8b43b3b4f111cb9bedfebdd49309bd6a) was captured by
scripts/seed/archive_seed.sh at HEAD 9873171a; gcc of the archive's self-emission
C reproduces the self-emission fixed point `8b43b3b4f111cb9bedfebdd49309bd6a` — both are the same
compiler state at HEAD 9873171a. The compiler self-build uses `-ffast` (user
programs default to `-fsafe`), so the recorded fixed point is the `-ffast`
binary. Rebuild recipes + full canonical flag-set requirement (`gcc -m32
-std=c89 -O0 -Wall -Wno-long-long -Wno-pointer-sign
-Wno-implicit-function-declaration`; the fixed point reproduces ONLY with
`-Wall` present) are recorded in `zig1-seed/SEED_README.txt`.
## 2026-09-23 — seed v80 (HEAD b83af0ed)

Seed rotation via scripts/seed/archive_seed.sh. Archive layout: top-level dir
`zig1-seed/` with `zig1`, `gen/` (45 `.c` + 46 `.h` incl.
emitted `zig_special_types.h`, 9223401 bytes), `c_exit.c` (top level),
`runtime/`, `lib/`, `SEED_README.txt`.

| field | value |
|---|---|
| date | 2026-09-23 |
| HEAD | `b83af0ed` |
| seed binary md5 | `43fe3df1509ffb5728c8250133ab7827` |
| self-emission C | 45 `.c` + 46 `.h` (9223401 bytes) |
| fixed point | `43fe3df1509ffb5728c8250133ab7827` |
| archive md5 | `4a499af291e17445736106d40eb14ab1` |

Provenance note: the archived binary (md5 43fe3df1509ffb5728c8250133ab7827) was captured by
scripts/seed/archive_seed.sh at HEAD b83af0ed; gcc of the archive's self-emission
C reproduces the self-emission fixed point `43fe3df1509ffb5728c8250133ab7827` — both are the same
compiler state at HEAD b83af0ed. The compiler self-build uses `-ffast` (user
programs default to `-fsafe`), so the recorded fixed point is the `-ffast`
binary. Rebuild recipes + full canonical flag-set requirement (`gcc -m32
-std=c89 -O0 -Wall -Wno-long-long -Wno-pointer-sign
-Wno-implicit-function-declaration`; the fixed point reproduces ONLY with
`-Wall` present) are recorded in `zig1-seed/SEED_README.txt`.
## 2026-09-23 — seed v79 (HEAD a825fc36)

Seed rotation via scripts/seed/archive_seed.sh. Archive layout: top-level dir
`zig1-seed/` with `zig1`, `gen/` (45 `.c` + 46 `.h` incl.
emitted `zig_special_types.h`, 9220738 bytes), `c_exit.c` (top level),
`runtime/`, `lib/`, `SEED_README.txt`.

| field | value |
|---|---|
| date | 2026-09-23 |
| HEAD | `a825fc36` |
| seed binary md5 | `d5608123de41de68663aa1842fcca9f2` |
| self-emission C | 45 `.c` + 46 `.h` (9220738 bytes) |
| fixed point | `d5608123de41de68663aa1842fcca9f2` |
| archive md5 | `101b8f72037be1e6279c5209391e0a13` |

Provenance note: the archived binary (md5 d5608123de41de68663aa1842fcca9f2) was captured by
scripts/seed/archive_seed.sh at HEAD a825fc36; gcc of the archive's self-emission
C reproduces the self-emission fixed point `d5608123de41de68663aa1842fcca9f2` — both are the same
compiler state at HEAD a825fc36. The compiler self-build uses `-ffast` (user
programs default to `-fsafe`), so the recorded fixed point is the `-ffast`
binary. Rebuild recipes + full canonical flag-set requirement (`gcc -m32
-std=c89 -O0 -Wall -Wno-long-long -Wno-pointer-sign
-Wno-implicit-function-declaration`; the fixed point reproduces ONLY with
`-Wall` present) are recorded in `zig1-seed/SEED_README.txt`.
## 2026-09-23 — seed v78 (HEAD 7b7dea33)

Seed rotation via scripts/seed/archive_seed.sh. Archive layout: top-level dir
`zig1-seed/` with `zig1`, `gen/` (45 `.c` + 46 `.h` incl.
emitted `zig_special_types.h`, 9221201 bytes), `c_exit.c` (top level),
`runtime/`, `lib/`, `SEED_README.txt`.

| field | value |
|---|---|
| date | 2026-09-23 |
| HEAD | `7b7dea33` |
| seed binary md5 | `4b8a6364ef47e8ebdfc5e4506b7cff02` |
| self-emission C | 45 `.c` + 46 `.h` (9221201 bytes) |
| fixed point | `4b8a6364ef47e8ebdfc5e4506b7cff02` |
| archive md5 | `8fff355b0423235500f044ddc84af62b` |

Provenance note: the archived binary (md5 4b8a6364ef47e8ebdfc5e4506b7cff02) was captured by
scripts/seed/archive_seed.sh at HEAD 7b7dea33; gcc of the archive's self-emission
C reproduces the self-emission fixed point `4b8a6364ef47e8ebdfc5e4506b7cff02` — both are the same
compiler state at HEAD 7b7dea33. The compiler self-build uses `-ffast` (user
programs default to `-fsafe`), so the recorded fixed point is the `-ffast`
binary. Rebuild recipes + full canonical flag-set requirement (`gcc -m32
-std=c89 -O0 -Wall -Wno-long-long -Wno-pointer-sign
-Wno-implicit-function-declaration`; the fixed point reproduces ONLY with
`-Wall` present) are recorded in `zig1-seed/SEED_README.txt`.
## 2026-09-23 — seed v77 (HEAD c88684f5)

Seed rotation via scripts/seed/archive_seed.sh. Archive layout: top-level dir
`zig1-seed/` with `zig1`, `gen/` (45 `.c` + 46 `.h` incl.
emitted `zig_special_types.h`, 9203778 bytes), `c_exit.c` (top level),
`runtime/`, `lib/`, `SEED_README.txt`.

| field | value |
|---|---|
| date | 2026-09-23 |
| HEAD | `c88684f5` |
| seed binary md5 | `c635bbf952501ca5993e6c60f63a4a5f` |
| self-emission C | 45 `.c` + 46 `.h` (9203778 bytes) |
| fixed point | `c635bbf952501ca5993e6c60f63a4a5f` |
| archive md5 | `6ca3b47c216754a0fb4b11c3cab7bd10` |

Provenance note: the archived binary (md5 c635bbf952501ca5993e6c60f63a4a5f) was captured by
scripts/seed/archive_seed.sh at HEAD c88684f5; gcc of the archive's self-emission
C reproduces the self-emission fixed point `c635bbf952501ca5993e6c60f63a4a5f` — both are the same
compiler state at HEAD c88684f5. The compiler self-build uses `-ffast` (user
programs default to `-fsafe`), so the recorded fixed point is the `-ffast`
binary. Rebuild recipes + full canonical flag-set requirement (`gcc -m32
-std=c89 -O0 -Wall -Wno-long-long -Wno-pointer-sign
-Wno-implicit-function-declaration`; the fixed point reproduces ONLY with
`-Wall` present) are recorded in `zig1-seed/SEED_README.txt`.
## 2026-09-22 — seed v76 (HEAD 38612d19)

Seed rotation via scripts/seed/archive_seed.sh. Archive layout: top-level dir
`zig1-seed/` with `zig1`, `gen/` (45 `.c` + 46 `.h` incl.
emitted `zig_special_types.h`, 9182817 bytes), `c_exit.c` (top level),
`runtime/`, `lib/`, `SEED_README.txt`.

| field | value |
|---|---|
| date | 2026-09-22 |
| HEAD | `38612d19` |
| seed binary md5 | `efa91f8d7c000df51d5547b2628f6e9f` |
| self-emission C | 45 `.c` + 46 `.h` (9182817 bytes) |
| fixed point | `efa91f8d7c000df51d5547b2628f6e9f` |
| archive md5 | `d3df69da8b0c029e4373fef816c86ff4` |

Provenance note: the archived binary (md5 efa91f8d7c000df51d5547b2628f6e9f) was captured by
scripts/seed/archive_seed.sh at HEAD 38612d19; gcc of the archive's self-emission
C reproduces the self-emission fixed point `efa91f8d7c000df51d5547b2628f6e9f` — both are the same
compiler state at HEAD 38612d19. The compiler self-build uses `-ffast` (user
programs default to `-fsafe`), so the recorded fixed point is the `-ffast`
binary. Rebuild recipes + full canonical flag-set requirement (`gcc -m32
-std=c89 -O0 -Wall -Wno-long-long -Wno-pointer-sign
-Wno-implicit-function-declaration`; the fixed point reproduces ONLY with
`-Wall` present) are recorded in `zig1-seed/SEED_README.txt`.
## 2026-09-22 — seed v75 (HEAD 05245298)

Seed rotation via scripts/seed/archive_seed.sh. Archive layout: top-level dir
`zig1-seed/` with `zig1`, `gen/` (45 `.c` + 46 `.h` incl.
emitted `zig_special_types.h`, 9181738 bytes), `c_exit.c` (top level),
`runtime/`, `lib/`, `SEED_README.txt`.

| field | value |
|---|---|
| date | 2026-09-22 |
| HEAD | `05245298` |
| seed binary md5 | `c8f1a76a97e0fe385faf757d5c4015ba` |
| self-emission C | 45 `.c` + 46 `.h` (9181738 bytes) |
| fixed point | `c8f1a76a97e0fe385faf757d5c4015ba` |
| archive md5 | `884f00cd4b90a934253e8b3a14e4a8e6` |

Provenance note: the archived binary (md5 c8f1a76a97e0fe385faf757d5c4015ba) was captured by
scripts/seed/archive_seed.sh at HEAD 05245298; gcc of the archive's self-emission
C reproduces the self-emission fixed point `c8f1a76a97e0fe385faf757d5c4015ba` — both are the same
compiler state at HEAD 05245298. The compiler self-build uses `-ffast` (user
programs default to `-fsafe`), so the recorded fixed point is the `-ffast`
binary. Rebuild recipes + full canonical flag-set requirement (`gcc -m32
-std=c89 -O0 -Wall -Wno-long-long -Wno-pointer-sign
-Wno-implicit-function-declaration`; the fixed point reproduces ONLY with
`-Wall` present) are recorded in `zig1-seed/SEED_README.txt`.
## 2026-09-22 — seed v74 (HEAD 3f9d70e1)

Seed rotation via scripts/seed/archive_seed.sh. Archive layout: top-level dir
`zig1-seed/` with `zig1`, `gen/` (45 `.c` + 46 `.h` incl.
emitted `zig_special_types.h`, 9169327 bytes), `c_exit.c` (top level),
`runtime/`, `lib/`, `SEED_README.txt`.

| field | value |
|---|---|
| date | 2026-09-22 |
| HEAD | `3f9d70e1` |
| seed binary md5 | `bea0a1c4c96140ced060d386fc99d145` |
| self-emission C | 45 `.c` + 46 `.h` (9169327 bytes) |
| fixed point | `bea0a1c4c96140ced060d386fc99d145` |
| archive md5 | `18e05ec36c7ba13bcc9aaf69d2ed3b8e` |

Provenance note: the archived binary (md5 bea0a1c4c96140ced060d386fc99d145) was captured by
scripts/seed/archive_seed.sh at HEAD 3f9d70e1; gcc of the archive's self-emission
C reproduces the self-emission fixed point `bea0a1c4c96140ced060d386fc99d145` — both are the same
compiler state at HEAD 3f9d70e1. The compiler self-build uses `-ffast` (user
programs default to `-fsafe`), so the recorded fixed point is the `-ffast`
binary. Rebuild recipes + full canonical flag-set requirement (`gcc -m32
-std=c89 -O0 -Wall -Wno-long-long -Wno-pointer-sign
-Wno-implicit-function-declaration`; the fixed point reproduces ONLY with
`-Wall` present) are recorded in `zig1-seed/SEED_README.txt`.
## 2026-09-22 — seed v73 (HEAD d49a3f36)

Seed rotation via scripts/seed/archive_seed.sh. Archive layout: top-level dir
`zig1-seed/` with `zig1`, `gen/` (45 `.c` + 46 `.h` incl.
emitted `zig_special_types.h`, 9168986 bytes), `c_exit.c` (top level),
`runtime/`, `lib/`, `SEED_README.txt`.

| field | value |
|---|---|
| date | 2026-09-22 |
| HEAD | `d49a3f36` |
| seed binary md5 | `3c55361afc2a898352379aa9a8bfff26` |
| self-emission C | 45 `.c` + 46 `.h` (9168986 bytes) |
| fixed point | `3c55361afc2a898352379aa9a8bfff26` |
| archive md5 | `2c27579e32ee37c4661c5500305cd947` |

Provenance note: the archived binary (md5 3c55361afc2a898352379aa9a8bfff26) was captured by
scripts/seed/archive_seed.sh at HEAD d49a3f36; gcc of the archive's self-emission
C reproduces the self-emission fixed point `3c55361afc2a898352379aa9a8bfff26` — both are the same
compiler state at HEAD d49a3f36. The compiler self-build uses `-ffast` (user
programs default to `-fsafe`), so the recorded fixed point is the `-ffast`
binary. Rebuild recipes + full canonical flag-set requirement (`gcc -m32
-std=c89 -O0 -Wall -Wno-long-long -Wno-pointer-sign
-Wno-implicit-function-declaration`; the fixed point reproduces ONLY with
`-Wall` present) are recorded in `zig1-seed/SEED_README.txt`.
## 2026-09-22 — seed v72 (HEAD ff704f7b)

Seed rotation via scripts/seed/archive_seed.sh. Archive layout: top-level dir
`zig1-seed/` with `zig1`, `gen/` (45 `.c` + 46 `.h` incl.
emitted `zig_special_types.h`, 9168555 bytes), `c_exit.c` (top level),
`runtime/`, `lib/`, `SEED_README.txt`.

| field | value |
|---|---|
| date | 2026-09-22 |
| HEAD | `ff704f7b` |
| seed binary md5 | `e46810b5ec6327f7bdf5288836e55c51` |
| self-emission C | 45 `.c` + 46 `.h` (9168555 bytes) |
| fixed point | `e46810b5ec6327f7bdf5288836e55c51` |
| archive md5 | `5ed3debdb199ceafe0117f45183b3a39` |

Provenance note: the archived binary (md5 e46810b5ec6327f7bdf5288836e55c51) was captured by
scripts/seed/archive_seed.sh at HEAD ff704f7b; gcc of the archive's self-emission
C reproduces the self-emission fixed point `e46810b5ec6327f7bdf5288836e55c51` — both are the same
compiler state at HEAD ff704f7b. The compiler self-build uses `-ffast` (user
programs default to `-fsafe`), so the recorded fixed point is the `-ffast`
binary. Rebuild recipes + full canonical flag-set requirement (`gcc -m32
-std=c89 -O0 -Wall -Wno-long-long -Wno-pointer-sign
-Wno-implicit-function-declaration`; the fixed point reproduces ONLY with
`-Wall` present) are recorded in `zig1-seed/SEED_README.txt`.

## 2026-09-22 — seed v71 (HEAD f7c6f99c)

Seed rotation via scripts/seed/archive_seed.sh. Archive layout: top-level dir
`zig1-seed/` with `zig1`, `gen/` (45 `.c` + 46 `.h` incl.
emitted `zig_special_types.h`, 9149230 bytes), `c_exit.c` (top level),
`runtime/`, `lib/`, `SEED_README.txt`.

| field | value |
|---|---|
| date | 2026-09-22 |
| HEAD | `f7c6f99c` |
| seed binary md5 | `e5ba7d74a78536683d2633c4655e027e` |
| self-emission C | 45 `.c` + 46 `.h` (9149230 bytes) |
| fixed point | `e5ba7d74a78536683d2633c4655e027e` |
| archive md5 | `fae87bb36b621b07642d4db57a8c7212` |

Provenance note: the archived binary (md5 e5ba7d74a78536683d2633c4655e027e) was captured by
scripts/seed/archive_seed.sh at HEAD f7c6f99c; gcc of the archive's self-emission
C reproduces the self-emission fixed point `e5ba7d74a78536683d2633c4655e027e` — both are the same
compiler state at HEAD f7c6f99c. The compiler self-build uses `-ffast` (user
programs default to `-fsafe`), so the recorded fixed point is the `-ffast`
binary. Rebuild recipes + full canonical flag-set requirement (`gcc -m32
-std=c89 -O0 -Wall -Wno-long-long -Wno-pointer-sign
-Wno-implicit-function-declaration`; the fixed point reproduces ONLY with
`-Wall` present) are recorded in `zig1-seed/SEED_README.txt`.

## 2026-09-22 — seed v70 (HEAD 0e9f705c)

Seed rotation via scripts/seed/archive_seed.sh. Archive layout: top-level dir
`zig1-seed/` with `zig1`, `gen/` (45 `.c` + 46 `.h` incl.
emitted `zig_special_types.h`, 9134766 bytes), `c_exit.c` (top level),
`runtime/`, `lib/`, `SEED_README.txt`.

| field | value |
|---|---|
| date | 2026-09-22 |
| HEAD | `0e9f705c` |
| seed binary md5 | `5c4d6eb627944dd4c5e0ff68a1089f43` |
| self-emission C | 45 `.c` + 46 `.h` (9134766 bytes) |
| fixed point | `5c4d6eb627944dd4c5e0ff68a1089f43` |
| archive md5 | `dd805c837557235f5fc5dd576282555e` |

Provenance note: the archived binary (md5 5c4d6eb627944dd4c5e0ff68a1089f43) was captured by
scripts/seed/archive_seed.sh at HEAD 0e9f705c; gcc of the archive's self-emission
C reproduces the self-emission fixed point `5c4d6eb627944dd4c5e0ff68a1089f43` — both are the same
compiler state at HEAD 0e9f705c. The compiler self-build uses `-ffast` (user
programs default to `-fsafe`), so the recorded fixed point is the `-ffast`
binary. Rebuild recipes + full canonical flag-set requirement (`gcc -m32
-std=c89 -O0 -Wall -Wno-long-long -Wno-pointer-sign
-Wno-implicit-function-declaration`; the fixed point reproduces ONLY with
`-Wall` present) are recorded in `zig1-seed/SEED_README.txt`.

## 2026-09-22 — seed v69 (HEAD 7205460c)

Seed rotation via scripts/seed/archive_seed.sh. Archive layout: top-level dir
`zig1-seed/` with `zig1`, `gen/` (45 `.c` + 46 `.h` incl.
emitted `zig_special_types.h`, 9135064 bytes), `c_exit.c` (top level),
`runtime/`, `lib/`, `SEED_README.txt`.

| field | value |
|---|---|
| date | 2026-09-22 |
| HEAD | `7205460c` |
| seed binary md5 | `b30033e88075b82243b5601ea3b1c38c` |
| self-emission C | 45 `.c` + 46 `.h` (9135064 bytes) |
| fixed point | `b30033e88075b82243b5601ea3b1c38c` |
| archive md5 | `bbaeab7c4a77e3d20342a5a0cfd78646` |

Provenance note: the archived binary (md5 b30033e88075b82243b5601ea3b1c38c) was captured by
scripts/seed/archive_seed.sh at HEAD 7205460c; gcc of the archive's self-emission
C reproduces the self-emission fixed point `b30033e88075b82243b5601ea3b1c38c` — both are the same
compiler state at HEAD 7205460c. The compiler self-build uses `-ffast` (user
programs default to `-fsafe`), so the recorded fixed point is the `-ffast`
binary. Rebuild recipes + full canonical flag-set requirement (`gcc -m32
-std=c89 -O0 -Wall -Wno-long-long -Wno-pointer-sign
-Wno-implicit-function-declaration`; the fixed point reproduces ONLY with
`-Wall` present) are recorded in `zig1-seed/SEED_README.txt`.

## 2026-09-22 — seed v68 (HEAD 5c0212ba)

Seed rotation via scripts/seed/archive_seed.sh. Archive layout: top-level dir
`zig1-seed/` with `zig1`, `gen/` (45 `.c` + 46 `.h` incl.
emitted `zig_special_types.h`, 9134614 bytes), `c_exit.c` (top level),
`runtime/`, `lib/`, `SEED_README.txt`.

| field | value |
|---|---|
| date | 2026-09-22 |
| HEAD | `5c0212ba` |
| seed binary md5 | `02c10559914a7a85704f7eca5c87bbff` |
| self-emission C | 45 `.c` + 46 `.h` (9134614 bytes) |
| fixed point | `02c10559914a7a85704f7eca5c87bbff` |
| archive md5 | `462dde37abb64c56292c8deb5f2439b1` |

Provenance note: the archived binary (md5 02c10559914a7a85704f7eca5c87bbff) was captured by
scripts/seed/archive_seed.sh at HEAD 5c0212ba; gcc of the archive's self-emission
C reproduces the self-emission fixed point `02c10559914a7a85704f7eca5c87bbff` — both are the same
compiler state at HEAD 5c0212ba. The compiler self-build uses `-ffast` (user
programs default to `-fsafe`), so the recorded fixed point is the `-ffast`
binary. Rebuild recipes + full canonical flag-set requirement (`gcc -m32
-std=c89 -O0 -Wall -Wno-long-long -Wno-pointer-sign
-Wno-implicit-function-declaration`; the fixed point reproduces ONLY with
`-Wall` present) are recorded in `zig1-seed/SEED_README.txt`.
## 2026-09-22 — seed v67 (HEAD 8443a6d6)

Seed rotation via scripts/seed/archive_seed.sh. Archive layout: top-level dir
`zig1-seed/` with `zig1`, `gen/` (45 `.c` + 46 `.h` incl.
emitted `zig_special_types.h`, 9118109 bytes), `c_exit.c` (top level),
`runtime/`, `lib/`, `SEED_README.txt`.

| field | value |
|---|---|
| date | 2026-09-22 |
| HEAD | `8443a6d6` |
| seed binary md5 | `923fe0f041704c1e4a21af6c7fbc513f` |
| self-emission C | 45 `.c` + 46 `.h` (9118109 bytes) |
| fixed point | `923fe0f041704c1e4a21af6c7fbc513f` |
| archive md5 | `855a88689457f631df7c42c903c69c5a` |

Provenance note: the archived binary (md5 923fe0f041704c1e4a21af6c7fbc513f) was captured by
scripts/seed/archive_seed.sh at HEAD 8443a6d6; gcc of the archive's self-emission
C reproduces the self-emission fixed point `923fe0f041704c1e4a21af6c7fbc513f` — both are the same
compiler state at HEAD 8443a6d6. The compiler self-build uses `-ffast` (user
programs default to `-fsafe`), so the recorded fixed point is the `-ffast`
binary. Rebuild recipes + full canonical flag-set requirement (`gcc -m32
-std=c89 -O0 -Wall -Wno-long-long -Wno-pointer-sign
-Wno-implicit-function-declaration`; the fixed point reproduces ONLY with
`-Wall` present) are recorded in `zig1-seed/SEED_README.txt`.
## 2026-09-22 — seed v66 (HEAD 268a4d74)

Seed rotation via scripts/seed/archive_seed.sh. Archive layout: top-level dir
`zig1-seed/` with `zig1`, `gen/` (45 `.c` + 46 `.h` incl.
emitted `zig_special_types.h`, 9117952 bytes), `c_exit.c` (top level),
`runtime/`, `lib/`, `SEED_README.txt`.

| field | value |
|---|---|
| date | 2026-09-22 |
| HEAD | `268a4d74` |
| seed binary md5 | `d62848983b239405407ad9a2cec9c609` |
| self-emission C | 45 `.c` + 46 `.h` (9117952 bytes) |
| fixed point | `d62848983b239405407ad9a2cec9c609` |
| archive md5 | `dbe6b19aa232c56fd1bb8e0aa21af8fa` |

Provenance note: the archived binary (md5 d62848983b239405407ad9a2cec9c609) was captured by
scripts/seed/archive_seed.sh at HEAD 268a4d74; gcc of the archive's self-emission
C reproduces the self-emission fixed point `d62848983b239405407ad9a2cec9c609` — both are the same
compiler state at HEAD 268a4d74. The compiler self-build uses `-ffast` (user
programs default to `-fsafe`), so the recorded fixed point is the `-ffast`
binary. Rebuild recipes + full canonical flag-set requirement (`gcc -m32
-std=c89 -O0 -Wall -Wno-long-long -Wno-pointer-sign
-Wno-implicit-function-declaration`; the fixed point reproduces ONLY with
`-Wall` present) are recorded in `zig1-seed/SEED_README.txt`.
## 2026-09-22 — seed v65 (HEAD f466ab23)

Seed rotation via scripts/seed/archive_seed.sh. Archive layout: top-level dir
`zig1-seed/` with `zig1`, `gen/` (45 `.c` + 46 `.h` incl.
emitted `zig_special_types.h`, 9112382 bytes), `c_exit.c` (top level),
`runtime/`, `lib/`, `SEED_README.txt`.

| field | value |
|---|---|
| date | 2026-09-22 |
| HEAD | `f466ab23` |
| seed binary md5 | `845165786674f82870abea053616d0d2` |
| self-emission C | 45 `.c` + 46 `.h` (9112382 bytes) |
| fixed point | `845165786674f82870abea053616d0d2` |
| archive md5 | `2f2ba33a3239a1b004e9e242b0c01e3b` |

Provenance note: the archived binary (md5 845165786674f82870abea053616d0d2) was captured by
scripts/seed/archive_seed.sh at HEAD f466ab23; gcc of the archive's self-emission
C reproduces the self-emission fixed point `845165786674f82870abea053616d0d2` — both are the same
compiler state at HEAD f466ab23. The compiler self-build uses `-ffast` (user
programs default to `-fsafe`), so the recorded fixed point is the `-ffast`
binary. Rebuild recipes + full canonical flag-set requirement (`gcc -m32
-std=c89 -O0 -Wall -Wno-long-long -Wno-pointer-sign
-Wno-implicit-function-declaration`; the fixed point reproduces ONLY with
`-Wall` present) are recorded in `zig1-seed/SEED_README.txt`.
## 2026-09-22 — seed v64 (HEAD 1fa2cb1e)

Seed rotation via scripts/seed/archive_seed.sh. Archive layout: top-level dir
`zig1-seed/` with `zig1`, `gen/` (45 `.c` + 46 `.h` incl.
emitted `zig_special_types.h`, 9111707 bytes), `c_exit.c` (top level),
`runtime/`, `lib/`, `SEED_README.txt`.

| field | value |
|---|---|
| date | 2026-09-22 |
| HEAD | `1fa2cb1e` |
| seed binary md5 | `17a476d2543c2ca9dcf0d7e7cb09ba01` |
| self-emission C | 45 `.c` + 46 `.h` (9111707 bytes) |
| fixed point | `17a476d2543c2ca9dcf0d7e7cb09ba01` |
| archive md5 | `0abd7af67a38bb26d92953245e32944e` |

Provenance note: the archived binary (md5 17a476d2543c2ca9dcf0d7e7cb09ba01) was captured by
scripts/seed/archive_seed.sh at HEAD 1fa2cb1e; gcc of the archive's self-emission
C reproduces the self-emission fixed point `17a476d2543c2ca9dcf0d7e7cb09ba01` — both are the same
compiler state at HEAD 1fa2cb1e. The compiler self-build uses `-ffast` (user
programs default to `-fsafe`), so the recorded fixed point is the `-ffast`
binary. Rebuild recipes + full canonical flag-set requirement (`gcc -m32
-std=c89 -O0 -Wall -Wno-long-long -Wno-pointer-sign
-Wno-implicit-function-declaration`; the fixed point reproduces ONLY with
`-Wall` present) are recorded in `zig1-seed/SEED_README.txt`.
## 2026-09-21 — seed v63 (HEAD d5b9c654)

Seed rotation via scripts/seed/archive_seed.sh. Archive layout: top-level dir
`zig1-seed/` with `zig1`, `gen/` (45 `.c` + 46 `.h` incl.
emitted `zig_special_types.h`, 9111708 bytes), `c_exit.c` (top level),
`runtime/`, `lib/`, `SEED_README.txt`.

| field | value |
|---|---|
| date | 2026-09-21 |
| HEAD | `d5b9c654` |
| seed binary md5 | `5d792f50cea61b9ef09fbd353c4557b0` |
| self-emission C | 45 `.c` + 46 `.h` (9111708 bytes) |
| fixed point | `5d792f50cea61b9ef09fbd353c4557b0` |
| archive md5 | `71880fbdabf20b542389031ab5cbdc11` |

Provenance note: the archived binary (md5 5d792f50cea61b9ef09fbd353c4557b0) was captured by
scripts/seed/archive_seed.sh at HEAD d5b9c654; gcc of the archive's self-emission
C reproduces the self-emission fixed point `5d792f50cea61b9ef09fbd353c4557b0` — both are the same
compiler state at HEAD d5b9c654. The compiler self-build uses `-ffast` (user
programs default to `-fsafe`), so the recorded fixed point is the `-ffast`
binary. Rebuild recipes + full canonical flag-set requirement (`gcc -m32
-std=c89 -O0 -Wall -Wno-long-long -Wno-pointer-sign
-Wno-implicit-function-declaration`; the fixed point reproduces ONLY with
`-Wall` present) are recorded in `zig1-seed/SEED_README.txt`.
## 2026-09-21 — seed v62 (HEAD 394296dd)

Seed rotation via scripts/seed/archive_seed.sh. Archive layout: top-level dir
`zig1-seed/` with `zig1`, `gen/` (45 `.c` + 46 `.h` incl.
emitted `zig_special_types.h`, 9103599 bytes), `c_exit.c` (top level),
`runtime/`, `lib/`, `SEED_README.txt`.

| field | value |
|---|---|
| date | 2026-09-21 |
| HEAD | `394296dd` |
| seed binary md5 | `6322cd4f916a7cc47c883b22f1f44905` |
| self-emission C | 45 `.c` + 46 `.h` (9103599 bytes) |
| fixed point | `6322cd4f916a7cc47c883b22f1f44905` |
| archive md5 | `e083175349cef5e1369d961aa0795837` |

Provenance note: the archived binary (md5 6322cd4f916a7cc47c883b22f1f44905) was captured by
scripts/seed/archive_seed.sh at HEAD 394296dd; gcc of the archive's self-emission
C reproduces the self-emission fixed point `6322cd4f916a7cc47c883b22f1f44905` — both are the same
compiler state at HEAD 394296dd. The compiler self-build uses `-ffast` (user
programs default to `-fsafe`), so the recorded fixed point is the `-ffast`
binary. Rebuild recipes + full canonical flag-set requirement (`gcc -m32
-std=c89 -O0 -Wall -Wno-long-long -Wno-pointer-sign
-Wno-implicit-function-declaration`; the fixed point reproduces ONLY with
`-Wall` present) are recorded in `zig1-seed/SEED_README.txt`.
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
