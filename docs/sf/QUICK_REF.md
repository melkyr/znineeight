# Z98 Compiler Quick Reference

## ⭐ SUBAGENT CHEAT-SHEET — READ THIS SECTION BEFORE ANY BUILD/COMPILE/RUN ⭐

**Every subagent doing build/compile/run/gate work MUST read this section first.** These are the
exact, verified commands. Do not improvise flags or rediscover linking — copy these.

> **Runtime safety:** `-fsafe` is the default (six runtime checks — cast / div-mod / shift /
> null-unwrap / index-OOB / integer-overflow — plus `undefined` `0xAA` poison); `-ffast` disables
> them. `unreachable`/`@panic` trap in **both** modes (`@panic` prints `panic: <msg>` to **stderr**).
> `std.arena.alloc` is `ArenaError![*]u8` — use `try`/`catch`, never `orelse` (`error[3016]`).

### Build zig1 (the compiler under test)

zig0 is retired and the old zig0 cycle (`sf/scripts/build_release.sh`,
`sf/build/out_release/`) no longer builds current `sf/src` — do NOT use it as
the build path or gate on it. Rebuild from the committed seed with the recipe
in the next section; that is the only supported path.

### Seed model — rebuild zig1 from the committed seed (`release/seed/`)

**Seed location + contents:** the committed rotating seed is
`release/seed/zig1-seed.tgz` (git-tracked; provenance + rotation history in
`release/seed/CHANGELOG.md`, full recipes + current md5s in
`release/seed/SEED_README.txt`).

**Current seed: v89.** Archive md5 `a1549c5b5d9ad23da4d41d214d9ad3c5`; archived binary md5
(= v89's rotation fixed point) `8216fedc8dd69db084d453be80f3c010`; `gen/` 45 `.c` + 46 `.h`;
`lib/` 30 std `.zig`. **This block is updated at every plan closeout that rotates the seed**;
the branch's in-progress fixed point is recorded in the active plan's workspace ledger.
The FX14-F–FX17-F notes below record each amendment's own fixed point and its
"seed v88 NOT rotated (closeout-only)" status at the time; the Volume II Task 22
closeout (2026-09-30) has since rotated the seed to v89 at this fixed point.

Top-level `zig1-seed/`: `zig1` (reference binary), `gen/` (its self-emission C89
module set — 45 `.c` + 46 `.h`, including `zig_special_types.h`; the emitted
runtime/support sources are NOT in `gen/`), top-level `c_exit.c`, `runtime/`
(the emitted 5: `zig_compat.h`, `zig_runtime.h`, `zig_special_types.h`,
`zig_runtime.c`, `zig_pal.c` — NO `net_prelude.h`), `lib/` (all 30 std `.zig`:
`std.zig` plus the 29 `std_*.zig`), and `SEED_README.txt`.

**Std-module inventory:** the `sf/src` std set is **29** `std_*.zig` + `std.zig`
(`std_io`, `std_fmt`, `std_arena`, `std_str`, `std_mem`, `std_math`, `std_debug`,
`std_net`, `std_async`, `std_bits`, `std_os`, `std_os_pal`, `std_time`,
`std_time_pal`, `std_buf`, `std_file`, `std_file_pal`, `std_stdin`,
`std_stdin_pal`, `std_stream`, `std_crypto`, `std_parse`, `std_map`, `std_sort`,
`std_heap`, `std_rle`, `std_base64`, `std_hex`, `std_utf8`). `std.zig` re-exports
the core **13** names (`io/fmt/arena/str/mem/math/debug/net/async/bits/os/time/buf`);
the higher-layer modules (L3-L6) are imported by path, not re-exported.
`scripts/seed/build_from_seed.sh` installs all 30 into the rebuilt compiler's `lib/`.

- **Compiler↔std separation:** the compiler's import graph reaches **no std module** —
  the transitive `@import` closure from `sf/src/main.zig` is zero std modules. The std lib is
  **user-side `.zig`, compiled on demand** from `<exe_dir>/lib/`; the self-emission fixed point
  is therefore **independent of the std lib** (adding or removing std modules does not move it).
- zig0 is retired; the seed model (`scripts/seed/build_from_seed.sh`) is the only rebuild path.
- **C89-AHEAD note:** `runtime/` carries the compiler's **emitted, mode-specific** support (the
  `-ffast` self-emission support), not the canonical `-fsafe` `sf/src/include` files, so a
  gcc-only rebuild of the archive C reproduces the archived binary's fixed point exactly.

**Rebuild recipe 1 (forward — from the seed binary):**
```bash
cd /workspace/znineeight
bash scripts/seed/build_from_seed.sh release/seed/zig1-seed.tgz <out_dir>
```
- GATE: `=== [seed] Done: <out_dir> ===`; result `<out_dir>/zig1_5_clean` md5 MUST equal the fixed
  point recorded for the current HEAD (the active plan's workspace ledger). The committed seed's own
  archived-binary md5 + fixed point are in `release/seed/SEED_README.txt` /
  `release/seed/CHANGELOG.md`.
- The dump MUST run from the repo root with the RELATIVE `sf/src/main.zig` path (module basename-hash
  tokens are path-derived). `<out_dir>` MUST be a fresh dir (the script `rm -rf`s it) — never point it
  at `/tmp/fx_subfolder` (the reference compiler lives there).
- Missing seed binary: the script auto-reconstructs the seed compiler from its own `gen/` C
  (`--reconstruct-only <seed> <out>` does that alone).

**Rebuild recipe 2 (seed binary lost — rebuild from the seed's C only):** self-contained, no repo
include path, no zig0: stage `<seed>/runtime/zig_runtime.c` + `<seed>/runtime/zig_pal.c` +
`<seed>/c_exit.c` beside `gen/*.c`, ONE canonical-flag `gcc -c -I <seed>/runtime` over all of them,
then link `*.o` (the three runtime TUs MUST be compiled under the full flag set, NOT dropped onto
the link line — without `-Wall` the fixed point is not byte-reproduced). Exact commands, and the
archived binary md5 the result must equal, are in `release/seed/SEED_README.txt`.

**Flag-set rule (binding):** every `gcc -c` MUST be
`gcc -m32 -std=c89 -O0 -Wall -Wno-long-long -Wno-pointer-sign -Wno-implicit-function-declaration -I <inc>`
— the fixed point reproduces ONLY with `-Wall`. Self-emission link set =
`zig_runtime.c` + `zig_pal.c` + `c_exit.c` (`zig_pal.c` alone is insufficient).

**Rotation protocol (closeout-only):** rotate the seed ONLY at a plan closeout that moved the
self-emission fixed point **or changed the archive's `lib/` payload** (the archive embeds the
std `.zig` set, so a plan that adds/removes std modules rotates the seed even when the fixed
point is unmoved), via
`bash scripts/seed/archive_seed.sh <zig1_binary> <gen_dir> release/seed/zig1-seed.tgz --update-changelog`
(gcc-rebuilds the archive C self-contained to the NEW fixed point + prepends the provenance entry to
`release/seed/CHANGELOG.md`). The seed lives at `release/seed/` (tracked), never `/tmp`.


### Calling convention (Win9x) — `extern "stdcall"` / `extern "cdecl"`  [added: 2026-09-14]

- **Surface:** a calling convention may be written on an extern fn declaration and on a function-pointer type — `extern "stdcall" fn(...) T`, `extern "cdecl" fn(...) T`, `extern "c" fn(...) T`; a bare `fn(...) T` is default cdecl. Accepted names: `"c"`/`"cdecl"` → cdecl (byte-identical to no string), `"stdcall"` → stdcall. Unknown → `error[3045]`; variadic `stdcall` → `error[3012]`; assigning a cross-convention fn-pointer → `error[3000]` (all clean: rc=2, 0 `.c`).
- **`Z98_STDCALL` macro** (emitted in `zig_compat.h`; canonical source `sf/src/include/zig_compat.h` + hand-written bytes in `sf/src/emit_support.zig`): `__attribute__((stdcall))` on Win32 gcc, `__stdcall` on MSVC/Watcom, **empty on non-Windows** — so linux default-cdecl emission is byte-identical.
- **Option-B use-site-cast rule (operator ruling; SUPERSEDES the earlier forced-prototype rule):** do **NOT** emit a second convention-bearing prototype for a convention extern. The C header remains the **sole declaration source** (this is what lets `std_net` use the real `<winsock.h>`/`windows.h` prototypes without conflict). The convention rides on the fn type/LIR and is applied **at the use site** as a cast to the convention-qualified `FS_…` fn-pointer typedef in `zig_special_types.h`: `((zT_…_FS_…)MessageBoxA)(...)`. `typeRegistryGetOrCreateFn` marks the stdcall fn type used so the `FS_…` typedef is emitted. Standalone (non-header-covered) stdcall fixtures are **emission-inspection only** — the cast names the extern symbol, whose declaration is the C header's responsibility.
- **`std_net` Win32 externs** are migrated to `extern "stdcall"` (all 15 in `sf/src/std_net.zig`); every `std`-importing program's dump gains the `FS_…` typedefs + use-site casts (the re-export pulls `std_net` in).



### Compile + RUN a program (repro or example) with zig1  — VERIFIED RECIPE
```bash
sf/build/out_release/zig1 --dump-c89 <FILE.zig> > /tmp/x.c 2>/tmp/x.err ; echo "dump rc=$?"
gcc -m32 -std=c89 -Wno-long-long -Wno-pointer-sign -I sf/src/include \
    /tmp/x.c sf/src/include/zig_runtime.c sf/src/include/zig_pal.c -o /tmp/x ; echo "gcc rc=$?"
/tmp/x ; echo "run rc=$?"
```
- You **must** link `sf/src/include/zig_runtime.c` AND `sf/src/include/zig_pal.c`, and pass
  `-I sf/src/include`. Missing any of these is the #1 cause of wasted turns.
- **Default safety mode is `-fsafe`.** A user program's emitted C includes the six check guards, so it
  differs from the `-ffast` compiler self-emission. Pass `-ffast` to `zig1` to reproduce pre-C89-AHEAD
  emitted C. No new link flags are needed — `pal_trap()` lives in the already-linked `zig_pal.c`.
- For **mud_server** add `sf/src/include/net_runtime.c` ONLY when building the pre-F6
  `examples/zig0/mud_server` bootstrap example — the migrated `examples/z98/mud_server`
  (std_net) links WITHOUT it (F6).
- For a **no-`main` repro** (compile-only, no link/run) use `gcc -m32 -std=c89 -c ... -o /dev/null`.
- **[updated: 2026-08-14] examples/repros now use bare `@import("std")`**, resolved
  via the search path: (1) importer's dir, (2) `-I`/`--lib-dir` dirs in CLI order, (3) the default
  install path `<exe_dir>/lib`, (4) CWD. To run a migrated example/repro you must first install the
  canonical std lib next to the compiler under test:
  `mkdir -p <exe_dir>/lib && cp sf/src/std.zig sf/src/std_io.zig sf/src/std_fmt.zig sf/src/std_arena.zig sf/src/std_net.zig sf/src/std_str.zig sf/src/std_mem.zig sf/src/std_math.zig sf/src/std_debug.zig sf/src/std_async.zig sf/src/std_bits.zig sf/src/std_os.zig sf/src/std_os_pal.zig sf/src/std_time.zig sf/src/std_time_pal.zig sf/src/std_buf.zig sf/src/std_file.zig sf/src/std_file_pal.zig sf/src/std_stdin.zig sf/src/std_stdin_pal.zig sf/src/std_stream.zig sf/src/std_crypto.zig sf/src/std_parse.zig sf/src/std_map.zig sf/src/std_sort.zig sf/src/std_heap.zig sf/src/std_rle.zig sf/src/std_base64.zig sf/src/std_hex.zig sf/src/std_utf8.zig <exe_dir>/lib/`
  (for `/tmp/fx_subfolder/zig1` that is `/tmp/fx_subfolder/lib/`). The canonical set
  includes `std_fmt.zig` (the print-formatting layer, auto-imported by the compiler
  whenever a `print` is lowered); a compiler whose `lib/` predates it can resolve a
  `print`-using program only when the std_fmt file is import-adjacent.
- A compiler ICE shows as `dump rc=134` (SIGABRT) with a `PANIC:` line — note the panic text may land
  on **stdout** (`/tmp/x.c`), not stderr.

### Windows (`-osw`) build — Win9x target; `-lwsock32` iff `std_net` is emitted  [updated: 2026-09-10]

EMITEMIT prunes modules with no value reference, so the emitted set follows what the program actually uses: a **stdio-only** `@import("std")` program emits **no `std_net_*.c/.h`** and needs **no `-lwsock32`**; only a program that value-references net keeps `std_net` and needs it.
- `net_prelude.h` is now **emitted into the output dir by the compiler** (self-contained emission, alongside `zig_compat.h`/`zig_runtime.h`/`zig_runtime.c`/`zig_pal.c`/`c_exit.c`); it resolves via `-I .` in the dump dir. It is no longer pulled from `sf/src/include`. (Pre-EMITEMIT it was a committed-only header and every std importer linked wsock32 — that note is superseded.)
- **PROBE (2026-09-10, EMITEMIT):** never-net `repro/mi_matrix/std_import_bare_xmod` `-osw` emits no `std_net`; mingw `-c` with an include dir lacking `net_prelude.h` rc=0, link **without** `-lwsock32` rc=0, `wine` runs. Net `repro/mi_matrix/net_bind_startup_xmod` emits `std_net`; link **without** `-lwsock32` FAILS (`undefined _imp__WSAStartup@8`), **with** rc=0.
- The emitted companion `build_target.sh` already carries `-lwsock32` in its mingw branch iff `std_net` was emitted (the `.bat`/owc scripts likewise on `-osw`); prefer it:
```bash
cd /workspace/znineeight
# 1) emit the self-contained dir (default emission; no --dump-c89 needed)
timeout 120 <zig1> -osw -o <dump> <entry.zig>
# 2) build for windows (mingw gcc); the script adds -lwsock32 iff std_net was emitted
cd <dump> && timeout 120 sh build_target.sh mingw
```
- Harness wrapper: `scripts/win32_cross/cross_build_run.sh <zig1> <entry> <workdir> <exe> [-lwsock32]` — pass `-lwsock32` only for a net-using program.

### Spill level switch (`-s<N>`) — RAM/I-O tradeoff  [updated: 2026-09-17]

`-s<N>` picks how many of the six spills live in RAM instead of the `.zig1_*.tmp` disk files.
Default `-s0` = all on disk. Deactivation order (oldest-spill-first): **S-AST → S-LIR → S-HASH →
S-RES → S-SIDE → S-EXTRA** — `-s1` moves AST to RAM, `-s2` also LIR, ... `-s6` = all RAM (no spill
files). S-EXTRA is the AST index-side `extra_children`/`extra_ranges` write-through pool pair
(`.zig1_extra_ec.tmp` / `.zig1_extra_er.tmp`). Higher `-s` = more RAM, less disk I/O; emission is
**byte-identical in every mode** (same data, different storage). Measured self-compile
(self-hosted binary, `--markers --track-memory`, seed v89): `-s0` pool &asymp; 20.6 M (all disk);
`-s1` pool 57.4 M with 18.4 M live; `-s6` (all RAM) 130.6 M. `-s0` fits the 64 MB `-mm` default;
`-s2`+ must be paired with `-mm128` (else `memory limit exceeded`, rc=3), and `-s6` needs the
larger `-mm0` cap. Range 0..6; bare
`-s` / non-digit / out-of-range (`-s7`) error rc=1. Per-level smoke: `.zig1_ast.tmp` absent at
`-s1`, `.zig1_lir.tmp` absent at `-s2`, ..., `.zig1_extra_ec.tmp`/`.zig1_extra_er.tmp` absent at
`-s6` — the spill-file ladder is the mode marker.

### Corpus gate (`repro/mi_matrix/*/main.zig` + the top-level `repro/` sweep) — classify by gcc EXIT CODE  [updated: 2026-09-02]
For each `repro/mi_matrix/*/main.zig`: run `zig1 --dump-c89 --output-dir DIR`, then compile
every emitted per-module `.c` file:
```bash
for f in DIR/*.c; do gcc -m32 -std=c89 -Wno-long-long -Wno-pointer-sign -I sf/src/include -c "$f" -o /dev/null || exit 1; done
```
- **Classify by gcc EXIT CODE, never by empty-stderr** (warnings are nonzero-length but rc=0; a
  stderr-emptiness classifier gives false counts like 68/63).
- `dump` rc≥128 = CRASH; stderr matching `error\[(48|9001|3043)\]|AddressSanitizer` = ICE; gcc rc==0 = OK; else FAIL.
  (`error[3048]` file diagnostics and a clean undefined-module-member `error[3042]` reject with 0 `.c` are
  deliberately NOT in the ICE regex — they are frontend rejections, not internal compiler errors, so they
  classify as ordinary FAIL. Genuine ICE markers `error[48]`/`error[9001]`/`error[3043]`/`AddressSanitizer`
  stay ICE. The canonical classifier is `scripts/corpus/classify`.)

- **A repro that fails the frontend (dump emits 0 `.c` files with a `error[NNNN]` diagnostic) is a
  FAILURE — a real compiler gap — NOT "OK".** Do NOT count an empty output dir as OK. The per-file
  gcc loop above is only the emission check; a frontend error must be checked separately:
  ```bash
  if [ -z "$(ls DIR/*.c 2>/dev/null)" ]; then result=FAIL; fi   # 0 .c emitted = frontend gap
  ```
- **Green-guards are a distinct bucket**: a valid program CORRECTLY rejected by the frontend with the
  documented `error[3000]` diagnostic and 0 `.c` emitted is a green-guard (correct rejection matching
  the zig0 oracle), counted SEPARATELY from FAIL; a green-guard moving to OK/FAIL is a regression.
  (See EXPECTED_FAIL.md "Green-guards" section.)


**Analyzer detection paths activated (2026-08-03):** null, lifetime, and doublefree
detection now route through `visitStatement` for full control-flow-aware analysis.
Single wrapper function `detectorVisit` (`sf/src/analyzer.zig:759`); per-pass
statement handler stored in `AnalyzerContext.on_stmt_cb` (`sf/src/analyzer.zig:383`).

### Byte-identical gate (mud / gol / lisp / json) — z98-only, self-consistency check

Gate entries (`examples/z98/` paths, NOT `examples/zig0/`):
```bash
sf/build/out_release/zig1 --dump-c89 <ENTRY> > /tmp/new.c
diff /tmp/ref.c /tmp/new.c   # compare against reference (ref.c captured at prior gate baseline)
```

**Gate-program runtime outputs** (stable byte-identity reference; runtime behavior is the gate — dump byte-identity alone is not sufficient):
- `game_of_life` (100 generations) stdout: `fcbf7e7cead5082f0a8caadd5a8f0ff9`
- `lisp_interpreter_curr` `(+ 1 2)` stdout: `b3d9f8974da24ddbf9d389f3d7d97322`; canonical 12-line feed stdout: `96654b3910a54d8bb7ec3ddfc0f26c6a`
- `json_parser` stdout: `8bda3d5a1ec07d14a301bc343df32bf8`
- `mud_server` server stdout: `66c8f0abb926cca7baf9a0d1692ab318` / client bytes: `93147d0f0bbd983a9d844fea8b7a6fa7` (canonical session via `demo/session.sh`, rc 0)
- `scripts/closeout/verify_upgraded.sh` runs the whole battery and prints `CLOSEOUT OK` (A1-A5, B1-B7) on success.

| Entry Path | Reference md5 (default `-fsafe`; authoritative) | Historical `-ffast` byte-anchor (not re-measured since the C89-AHEAD split) |
|---|---|---|
| `examples/z98/mud_server/main.zig` | `f3be9bb9ebc0c1c9799da2181e2fa7e8` | `ac1579907ce84efa2f9014187070bf94` |
| `examples/z98/game_of_life/main.zig` | `6df1e4d2e9afa0f4163a7053f67384be` | `e023d3cd0bfb23346ac800725c5192f1` |
| `examples/z98/lisp_interpreter_curr/main.zig` | `e27b7c35678974deb130cfc77cb08686` | `21747e2acf177947ad499149bb3fdc98` |
| `examples/z98/json_parser/main.zig` | `d51f17aebdabcd009e453adb2e286d4e` | `2f08bf260bf2b6813fa4d70ffbc88aa9` |

Re-baselined by the FX5 `-fsafe` slice-bounds guards (2026-09-28), then by the
FX14 layout-model pin (2026-09-29, operator ruling A): every gate dump embeds
the per-program 64-bit carrier typedef lines, which gained ` Z98_ALIGN8`, plus
the new f64 carrier, so **both modes move 8/8**. Current live `-ffast` pins are
gol `98e934f3e15be355d47e26ded595dc8a`, lisp
`2514f8b5ddceacba67203af37a7346c3`, json
`e1cc386e9d09e322a068731cb2061621`, mud
`66d547d4a076fc2ce44d6d3aa3092c1d`. FX14 runtime-output identity PRE↔POST was
re-proven by execution in both modes and is byte-identical (gol `fcbf7e7c…`,
lisp `(+ 1 2)` `b3d9f897…`, json `8bda3d5a…`, mud
`66c8f0ab…`/`93147d0f…`). The FX14-F fixed point (moving point hop1 != hop2 ==
hop3, explicit `FIXED_POINT_MD5` gate) is
**`368c34e6cbfceda3091f53d2daac75eb`**; seed v88 NOT rotated (closeout-only).

Re-verified by the FX15-F whole-value nested packed move fix (2026-09-29):
`sf/src` lowering-only change, so all 8 emitted-C pins above are
**UNCHANGED 8/8** and FX15 runtime-output identity PRE↔POST is byte-identical
in both modes. The FX15-F fixed point (moving point hop1 `7ca45053…` != hop2 ==
hop3, explicit `FIXED_POINT_MD5` gate) is
**`1e898a16bac50bd2898262dd6bce176f`**; corpus `-s0` 1076 = 914 OK / 53 GREEN /
109 FAIL with the single mover `packed_union_struct_wholemember_xmod`
GREEN -> OK; seed v88 NOT rotated (closeout-only).

FX15-F fix round 1 (2026-09-29; review Important F1) keeps the per-leaf
recursion cap at 32 nesting levels and makes a failure a clean site
`error[3000]` reject instead of the pre-fix whole-aggregate bitfield fall-
through: field-type nesting 33 deep is accepted (fixture
`packed_nested_whole_depth_ok_xmod`, golden `1 1`), 34 deep cleanly rejects
(`packed_nested_whole_depth_reject_xmod`, 2x `error[3000]`, classify GREEN).
All 8 emitted-C pins stay **UNCHANGED 8/8**, runtime identity stays
byte-identical in both modes, stdlib 266 PASS / 0 FAIL, corpus `-s0`
**1078 = 915 OK / 54 GREEN / 109 FAIL / 0 ICE / 0 CRASH** (zero common-dir
movers vs the FX15-F corpus; +2 depth fixtures), and the new fixed point
(moving point hop1 `a1537257…` != hop2 == hop3, explicit `FIXED_POINT_MD5`
gate) is **`9d63b8cedaff9dff3ab73c2e847c6f60`**; seed v88 NOT rotated.

FX16-F (2026-09-29; Volume II ch7 amendment, operator rulings m0952) implements
the tagged-union `.tag` contextual sugar (A+: all six comparison ops, switch
prongs/capture, P1 pointer reads, R1 cross-module relational), the S2/S1
payload-store clean `error[3000]` rejects, the A4 copied-tag reject
(`error[3076]`), and the adjacent plain-enum compare + pointer `.tag` store
fixes. All 8 emitted-C pins stay **UNCHANGED 8/8** (2x deterministic), 4-MD5
runtime identity not required (no pin moved), stdlib **266 PASS / 0 FAIL**,
example matrix 24/24, emit support 7/7, `verify_upgraded.sh` CLOSEOUT OK,
self-emission 48 `.c` + 48 `.h` / 0 PANIC, corpus `-s0`
**1083 = 917 OK / 55 GREEN / 111 FAIL / 0 ICE / 0 CRASH** (zero common-dir
movers vs the 1078-dir baseline; +5 fixtures), and the new fixed point
(moving point hop1 `2cb6be18e68fd2cac6055f234ec9fc0d` != hop2 == hop3, explicit
`FIXED_POINT_MD5` gate) is **`f54f3bbe1e9406596d2390725ec3c61c`**; seed v88 NOT
rotated.

FX16-F fix round 1 (2026-09-29; review Important I2, operator ruling: FIX): a
real union member named `tag` no longer shadows the synthetic `.tag` in
lowering — the generic tagged-union read arm checks the synthetic tag before
the member walk for a union VALUE (sema already ruled that), so `u.tag` reads
the ordinal and A+ compares/switches dispatch from it (PRE `5 0 0 9 5 0 5 0` ->
POST `0 1 0 1 0 1 1 1`; fixture `tagged_tag_member_shadow_xmod`). The three new
reject-census `expected_error.txt` pins are force-added (`git add -f`), and the
typed-binding copied-tag form (`var b: bool = t == .m`) is pinned as an extra
`error[3076]` + the pre-existing `warning[3000]` (census `3076 7`). All 8
emitted-C pins stay **UNCHANGED 8/8** 2x; stdlib 266 PASS (targeted 3 PASS);
matrix 24/24; emit 7/7; CLOSEOUT OK; self-emission 48/48 / 0 PANIC; corpus
`-s0` **1084 = 918 OK / 55 GREEN / 111 FAIL / 0 ICE / 0 CRASH** (zero
common-dir movers; +1 fixture), and the new fixed point (moving point hop1
`8d3857f22a349a3e3710aad34b0b31eb` != hop2 == hop3, explicit
`FIXED_POINT_MD5` gate) is **`207e23ee39120654d9b2c32d1426c704`**; seed v88 NOT
rotated.

FX17-F (2026-10-01; Volume II ch16, operator rulings m1012 D1–D5) enforces
function-pointer signature matching at every assignment/coercion position: a
signature-mismatched coercion (`fn(*i32) void` -> `fn(*void) void`, wrong
return/arity/callconv/variadic, through one `?fn` layer, cross-module, both
directions) is now a level-0 raw `error[3000]` with the site's message plus
`source:`/`target:` notes; the shared level-0 reporter is renamed
`semanticAnalyzerFloatNarrowReport` -> `semanticAnalyzerTypeMismatchReport`.
Exact matches, named aliases, callconv matches, `?fn`, `@ptrCast` and
`@ptrToInt`/`@intToPtr` stay legal; the `*const fn` warning, `null`/`undefined`
-> `fn`, and the parked `s.draw_fn.*(...)` link defect are documented residuals
(not enforced). Fixtures `fn_ptr_signature_reject_xmod` (`3000 23`) /
`fn_ptr_signature_ok_xmod` + standalone `repro/fn_ptr_signature_{reject,ok}.z98`.
All 8 emitted-C pins stay **UNCHANGED 8/8** 2x; stdlib 266 PASS; matrix 24/24;
emit 7/7; CLOSEOUT OK; self-emission 48/48 / 0 PANIC; build_test 0/9; run_all
13/13; corpus `-s0` **1086 = 919 OK / 56 GREEN / 111 FAIL / 0 ICE / 0 CRASH**
(zero common-dir movers; +2 fixtures); the FX17-F fixed point (moving point
hop1 `9abebc39410001110ac0433a3a2a208b` != hop2 == hop3, explicit
`FIXED_POINT_MD5` gate) is **`8216fedc8dd69db084d453be80f3c010`**; seed v88 NOT
rotated.

- Self-consistency gate: compare current zig1 `--dump-c89` against a pre-captured reference .c file. If the reference .c is outdated (intentional baseline change), re-capture via `cp /tmp/new.c /tmp/ref.c`. Never compare against parent-zig1 output directly — parent builds may fail silently.
- Do **NOT** compare `zig1 --dump-c89` output against `zig0`'s C output. `zig0` emits a legacy bootstrap format that is byte-level incompatible with zig1.

### TCO gate recipes (examples/z98/tco_*) — [updated: 2026-08-03]

Self-recursion TCO: emitted C must contain a `z_bb_0:` label in the recursive fn + rebind assigns +
`goto z_bb_0;` back-edge (NO retained self `call`). Deep recursion (100k) must run with O(1) stack.

```bash
# tco_factorial (self-recursion, i32)
sf/build/out_release/zig1 --dump-c89 examples/z98/tco_factorial/main.zig > /tmp/tf.c ; echo "dump rc=$?"
grep -n "goto z_bb_0;" /tmp/tf.c            # expect: fact() has rebind assigns + back-edge
grep -c "zF_.*_fact(" /tmp/tf.c             # fwd-decl + def + main call sites only; NO self-call in fact body
gcc -m32 -std=c89 -Wno-long-long -Wno-pointer-sign -I sf/src/include \
    /tmp/tf.c sf/src/include/zig_runtime.c sf/src/include/zig_pal.c -o /tmp/tf ; echo "gcc rc=$?"
/tmp/tf ; echo "run rc=$?"                  # expect: "fact(10) = 3628800" then "deep ok", rc=0

# tco_return_try (self-recursion through E!i32 try)
sf/build/out_release/zig1 --dump-c89 examples/z98/tco_return_try/main.zig > /tmp/tr.c ; echo "dump rc=$?"
grep -n "goto z_bb_0;" /tmp/tr.c             # expect: count() back-edge (try-CFG eliminated)
gcc -m32 -std=c89 -Wno-long-long -Wno-pointer-sign -I sf/src/include \
    /tmp/tr.c sf/src/include/zig_runtime.c sf/src/include/zig_pal.c -o /tmp/tr ; echo "gcc rc=$?"
/tmp/tr ; echo "run rc=$?"                  # expect: "count(10) = 10" then "count(100000) = 100000", rc=0

# tco_defer (self-recursion with defer — defer fires ONCE at terminal return, not per-iteration)
# [updated: 2026-08-03]
sf/build/out_release/zig1 --dump-c89 examples/z98/tco_defer/main.zig > /tmp/td.c ; echo "dump rc=$?"
grep -n "goto z_bb_0;" /tmp/td.c               # expect: back-edge present
# Verify defer body NOT in the self-TCO rebind/jump block (nop'd by lower.zig:3641-3645)
# Verify defer body PRESENT in terminal-return path before the final `return` (emitted at lowerFn:4457)
gcc -m32 -std=c89 -Wno-long-long -Wno-pointer-sign -I sf/src/include \
    /tmp/td.c sf/src/include/zig_runtime.c sf/src/include/zig_pal.c -o /tmp/td ; echo "gcc rc=$?"
/tmp/td ; echo "run rc=$?"                     # expect: defer fires exactly once at end, rc=0
```

Gate: dump rc=0, gcc rc=0, run rc=0, `goto z_bb_0;` present, no self-call retained in the emitted
recursive fn. A compiler ICE shows as `dump rc=134` with a `PANIC:` line (may land on stdout).
`gcc -Wunused-label` warnings for `z_bb_0:` are expected and harmless.

**Consumer-guard note:** `hasOtherConsumers` (`lower.zig:4265`) scans all blocks before
`zeroCallCFG` to ensure no secondary consumers of the call result exist. Defensive — not
triggerable by current Z98 patterns. [updated: 2026-08-03]

### z_bb_0: labels in every function — [updated: 2026-08-03]

Since the TCO feature (F-S2/F-S3), **every** emitted function body contains a `z_bb_0:` label
(AMENDMENT 8). It is the entry-block label emitted by the `.loop_header` LirInst arm
(`c89_emit.zig:2775`), and it is the target of self-TCO `goto z_bb_0;` back-edges. It is EXPECTED:
- For self-recursive fns it is the live TCO jump target.
- For all other fns it is an unused label → `gcc -Wunused-label` warning (tolerated; the md5-gate
  baselines already include the label).

Do NOT treat `z_bb_0:` or the unused-label warning as a regression.

### Multi-Module Build — self-contained output dir  [updated: 2026-09-10]

`zig1 -o DIR <entry>` emits a **complete self-contained C89 tree** (needed-only module `.c`/`.h`
plus runtime/platform headers and runtime sources) and a companion `build_target.sh`. Build it:

```bash
zig1 -o DIR <entry>            # default emission (no --dump-c89 needed)
cd DIR
gcc -m32 -std=c89 -O0 -Wall -Wno-long-long -Wno-pointer-sign \
    -Wno-implicit-function-declaration -I . -c *.c
gcc -m32 -O0 *.o -o prog
# or simply:
sh DIR/build_target.sh         # (./DIR/build_target.sh after the first run)
```
- `-I .` is enough — the emitted dir carries its own runtime/platform headers (`zig_compat.h`,
  `zig_runtime.h`, and `net_prelude.h` iff `std_net` is emitted). No repo
  `-I sf/src/include` and no hand-listed `zig_runtime.c`/`zig_pal.c`/`c_exit.c` trio are needed;
  the emitted support sources are already in `DIR/*.c`.
- Run `gcc -c` INSIDE DIR — `gcc -c DIR/*.c` from outside writes the `.o` files to the caller's
  CWD, so the `*.o` link glob fails (`cannot find DIR/*.o`).
- The emitted `build_target.sh` uses an intentional **modules-then-runtime link order** (the
  compiler-enumerated module `.o` list first, runtime `.o` last). This deliberately differs from
  the seed recipe's plain alphabetical `*.o` glob and is not a bug.
- `--dump-c89` remains a debug alias: single-file to stdout without `-o`, or per-module `.c`/`.h`
  with `-o`.

### Editing source
Use `edit` (exact strings) or `fastedit` (line ranges, see AGENTS.md §X.7 — re-read the region
immediately before each edit; edit bottom-to-top). No `sed`/python/bulk transforms.

---


### Canonical Examples vs Oracle Examples

- **Canonical examples** under `examples/z98/` — use `@cInclude` + `extern fn` (valid Z98 syntax).
- **Oracle examples** under `examples/zig0/` — use zig0-compatible syntax. Only for oracle comparison against `zig0` output, not as working-example reference.
- The gcc compile recipe includes `-I sf/src/include` which auto-declares bootstrap functions (`__bootstrap_print` etc.) from `zig_runtime.h`.


## Bootstrap Build (zig0 → zig1)


```bash
cd /workspace/znineeight
rm -rf out_release && mkdir -p out_release
./sf/build/zig0 --header-priority-include -o out_release/zig1.c sf/src/main.zig
gcc -m32 -std=c89 -Wno-long-long -Iinclude out_release/*.c sf/src/include/zig_pal.c -o out_release/zig1
```

Debug build:
```bash
gcc -m32 -g -O0 -std=c89 -Wno-long-long -Iinclude out_release/*.c sf/src/include/zig_pal.c -o out_release/zig1
```

## LISP refactor testing building zig1 pipeline

How the LISP / sema-refactor work actually builds and tests `zig1` (differential vs `zig0`).
`zig1` is fully determined by **`sf/src/main.zig` (+ its imports)** and **`sf/build/zig0`** — the
output directory and gcc *warning* flags do NOT change the resulting compiler.

**1. Build zig1 from the current source (isolated output dir):**
```bash
OUT=/tmp/z1
rm -rf "$OUT" && mkdir -p "$OUT"          # always clean: stale .c/.h cause false Slice_* type errors
./sf/build/zig0 --header-priority-include -o "$OUT/zig1.c" sf/src/main.zig   # emits 35 per-module .c
gcc -m32 -std=c89 -Wno-long-long -Wno-pointer-sign "$OUT"/*.c sf/src/include/zig_pal.c -o "$OUT/zig1"
```
Debug build (for GDB): append `-g -O0 -Wno-implicit-function-declaration` to the gcc line.

- zig0 emits **35 per-module `.c` files** into `$OUT` (gcc globs `"$OUT"/*.c`; there is no single `zig1.c` object).
- The bootstrap `-Iinclude` above is **stale** (no root `include/` dir exists) — omit it. `-Wno-pointer-sign`
  only mutes warnings. Gate on the `error:` count, never warnings.
- Always build from the **repo** `sf/src/main.zig`, never a `/tmp` `git worktree` (those hold older source = a different/older zig1).

**2. Compile + run an example with that zig1:**
```bash
"$OUT/zig1" --dump-c89 examples/zig0/lisp_interpreter_curr/main.zig > /tmp/lisp.c
gcc -m32 -std=c89 -Wno-long-long -Wno-pointer-sign -Isf/src/include \
    /tmp/lisp.c sf/src/include/zig_runtime.c sf/src/include/zig_pal.c -o /tmp/lisp 2>&1 | grep -c 'error:'
# use `gcc -c` (no link) for no-main repros; pre-F6 mud_server examples need net_runtime.c (F6-migrated z98 mud_server does not)
```

**3. Differential / gate (what "passing" means):**
- `zig0` is the reference oracle: `./sf/build/zig0 -o DIR/out.c repro.zig` (emits per-module `repro.c` in `DIR`).
- Refactor gate: `man/gol/mud/lisp --dump-c89` **byte-identical** to baselines + `lisp` `error:` count == `12` + self-host gcc `0` errors.
- Current baselines (HEAD `c3d61919`): `man c379bd194d73d06a9dbac02431a82b2d`, `gol 8aa260ce9d467995f657e46552712fb1`,
  `mud 35051e34cd0ba883a08ff60569ae262f`, `lisp 74a721caef6f121fe6d744870dbb7c37`; `zig1` ≈ `621772` bytes.
- Markers: `"$OUT/zig1" --markers --dump-c89 <entry> 2>mk` then `grep -ac '^PREFIX' mk`
  (watch prefix collisions: `FS:C`/`FS:CK`, `IFST:K`/`IFST:K2` → use the `:N` variant).

## Compile Examples with zig1

```bash
./out_release/zig1 --dump-c89 examples/zig0/mandelbrot/mandelbrot.zig > out.c
./out_release/zig1 --dump-c89 examples/zig0/game_of_life/main_lin.zig > out.c
./out_release/zig1 --dump-c89 examples/zig0/mud_server/main.zig > out.c
```

With markers (diagnostic output to stderr):
```bash
./out_release/zig1 --markers --dump-c89 examples/zig0/mud_server/main.zig > out.c 2>diag.txt
```

## Compile Z98 Examples (@cInclude)

```bash
./out_release/zig1 --dump-c89 examples/z98/json_parser/main.zig > out.c
gcc -m32 -std=c89 -Wno-pointer-sign -Isf/src/include out.c \
    sf/src/include/zig_runtime.c sf/src/include/zig_pal.c -o app
```

## GCC Compile + Link

```bash
gcc -m32 -std=c89 -Wno-pointer-sign \
  -Iout_release -Isf/src/include \
  out.c \
  sf/src/include/zig_runtime.c \
  sf/src/include/zig_pal.c \
  -o app
```

## Build mud_server (full cycle)

```bash
cd /workspace/znineeight
rm -rf out_release && mkdir -p out_release
./sf/build/zig0 --header-priority-include -o out_release/zig1.c sf/src/main.zig
gcc -m32 -std=c89 -Wno-long-long -Iinclude out_release/*.c sf/src/include/zig_pal.c -o out_release/zig1
./out_release/zig1 --dump-c89 examples/zig0/mud_server/main.zig > /tmp/mud.c
gcc -m32 -std=c89 -Wno-pointer-sign -Iout_release -Isf/src/include \
  /tmp/mud.c sf/src/include/zig_runtime.c sf/src/include/zig_pal.c \
  sf/src/include/net_runtime.c -o /tmp/mud
```

Check error count:
```bash
gcc ... 2>&1 | grep -c "error:"
```

## Build and Run Tests

```bash
cd /workspace/znineeight && ./sf/scripts/build_test.sh
```

Note: `build_test.sh` links `sf/src/include/zig_pal.c` into each test binary (required since
`pal.zig` gained the `pal_file_*` file-I/O externs; without it every test binary fails to link).

## Std-lib Runtime Gate

Runtime-behavior gate for the std-lib fixtures (spec
`docs/superpowers/specs/2026-09-18-std-lib-test-hardening-design.md` §2). The
corpus classifier stays compile-only; this gate builds, links, RUNS, and
golden-diffs each fixture.

```bash
# full discovered std set (repro/mi_matrix/stdlib_*/ + stdlib_test/*/)
bash scripts/stdlib/run_fixtures.sh <seed-built-zig1_5_clean>

# restrict to explicit dirs (repo-relative or absolute)
bash scripts/stdlib/run_fixtures.sh <zig1> repro/mi_matrix/stdlib_bits_table_xmod

# re-capture a fixture's goldens from the observed run (writes expected.txt +
# expected.rc and prints what it wrote; refuses an undeclared nonzero rc).
# ALWAYS review the observed output against the fixture's documented GREEN
# contract before committing a capture.
bash scripts/stdlib/run_fixtures.sh --capture <zig1> repro/mi_matrix/stdlib_bits_table_xmod

# closeout wrapper (full discovered set; nonzero + STDLIB GATE FAILED on any fail)
bash scripts/stdlib/verify_stdlib.sh <zig1>
```

Per fixture the harness: `zig1 -ffast -o <tmp> <entry>` → gcc every emitted
`.c` with the binding flag-set (`-m32 -std=c89 -O0 -Wall -Wno-long-long
-Wno-pointer-sign -Wno-implicit-function-declaration -I .`) → `sh
<tmp>/build_target.sh linux <prog>` → run 3× under `timeout 120` from a scratch
CWD. A fixture passes only when all 3 stdouts are byte-identical, stdout
`cmp`-equals `<dir>/expected.txt`, and rc equals `<dir>/expected.rc`
(whitespace-trimmed).

**Discovery pin + unpinned-dir guard + port guard (binding):**
- Discovery is `repro/mi_matrix/stdlib_*/` (any `stdlib_*` dir, not just
  `_xmod`) plus `stdlib_test/*/`. In discovery mode the harness asserts the
  discovered dir set EQUALS the committed baseline
  `scripts/stdlib/expected_dirs.txt` (192 dirs today: 185
  `repro/mi_matrix/stdlib_*` + 7 `stdlib_test/*`), so a dropped/renamed/added
  fixture FAILS the gate instead of silently shrinking coverage. Update the pin
  intentionally when a band adds/removes fixtures.
- Independently of the discovery pin, a guard ALWAYS fails
  `unpinned-stdlib-dir (<dir>)` if any `repro/mi_matrix/stdlib_*/` or
  `stdlib_test/*/` dir exists on disk that is not in the pin — even in explicit
  `<dir>` runs, and even for a dir with no resolvable entry (so a std-looking
  dir cannot silently escape the gate). Explicit `<dir>` runs skip only the
  discovery-pin set-equality check (targeted runs), not the guard.
- A fixture that binds TCP ports ships `<dir>/ports.txt` (one port per line,
  `#` comments allowed). The harness fails `PORT-IN-USE:<port>` if a LISTEN
  socket already exists on a declared port before the run.

**Fixture naming contract (binding):**
- Std fixtures live at `repro/mi_matrix/stdlib_<module>_<name>_xmod/` (the
  `_xmod` suffix is the corpus convention; discovery matches any `stdlib_*`
  dir). Workflow-level fixtures live under `stdlib_test/<name>/`.
- Every discovered fixture MUST have a committed `expected.txt` +
  `expected.rc` and be listed in `scripts/stdlib/expected_dirs.txt` (no silent
  skips).

**Golden convention (binding):**
- `<dir>/expected.txt` = exact stdout bytes; `<dir>/expected.rc` = expected exit code.
- A missing golden is a FAIL (no silent skips).
- Goldens are runtime-only (stdout+rc), never emitted-C bytes; captured from a
  known-good compiler at the plan baseline and re-captured only on an intentional
  behavior change.
- `--capture` writes the observed stdout+rc, but REFUSES a nonzero rc that is
  not already declared in an existing `expected.rc` (a crashing fixture is not
  silently frozen — a probe declares its `expected.rc` first).
- Capture only after confirming the observed output matches the fixture's
  documented GREEN contract in its `main.zig` header (never freeze a wrong output).
- Expected-failure probes (e.g. `stdlib_debug_defaulttrap_xmod` rc=134,
  `stdlib_async_waitfor_unregistered_xmod` rc=133) ship an `expected.rc` of the
  signal code and an empty `expected.txt` — the expected failure is itself asserted.
- `.gitignore` carries `!expected.txt` so the stdout goldens are committable source.

`scripts/closeout/verify_upgraded.sh` phase C runs this gate, so `CLOSEOUT OK`
requires it to pass.


## Debug with GDB on zig1

### Build with debug symbols
```bash
gcc -m32 -g -O0 -std=c89 -Wno-long-long -Iinclude out_release/*.c sf/src/include/zig_pal.c -o out_release/zig1
```

### Find function in generated C
```bash
grep -n "function_name_part" out_release/semantic_analyzer.c | head -5
```

### Find line for breakpoint
```bash
grep -n "keyword" out_release/semantic_analyzer.c | head -20
```

### GDB with batch script
```bash
cat > /tmp/gdb.txt <<'EOF'
set pagination off
break out_release/semantic_analyzer.c:LINENO
run examples/zig0/mud_server/main.zig > /dev/null 2> /dev/null
print varname
print another_var
continue
quit
EOF
gdb -batch -x /tmp/gdb.txt --args ./out_release/zig1 --dump-c89
```

### Filter output to variable values
```bash
gdb -batch ... 2>&1 | grep "^\$"
```

### Common breakpoints in resolveSwitchExpr (line numbers may shift after edits)
| Purpose | Approx C Line | Look for |
|---------|---------------|----------|
| Function entry | search for `static unsigned int zF_...manticAnalyzerResolveSwitchExpr` | Declaration line + 14 = unified init |
| Loop start | search for `__loop_0_start` in function body | `if (!(i < prongs.len))` |
| `unified = bt` (i==0) | ~2225 | `un_box[0] = bt;` or `unified = bt;` |
| `bt == unified` check | ~2227 | `bt == un_box[0]` or `bt == unified` |
| TYPE_VOID return | ~2267 | `return zC_..._TYPE_VOID;` |
| Loop exit | ~2275 | `__loop_0_end:` label |

### Verify zig0 C89 variable corruption theory
Replace suspect scalar variable with `[1]u32` box array. If behavior unchanged → corruption theory disproven. Example:
```zig
// Before: var unified: u32 = 0;
// After:  var un_box: [1]u32 = [1]u32{0};   // use un_box[0] everywhere
```

### itoa-based diagnostic markers — use palMarkerWriteInt
```zig
// BEFORE (15+ local vars, zig0 C89 budget risk):
var m: []const u8 = "LABEL:n"; pal_mod.markerWrite(m);
var nb: [10]u8 = undefined; var nl = itoa_mod.itoa(val, nb[0..]);
var ns: usize = @intCast(usize, 9) - @intCast(usize, nl);
pal_mod.markerWrite(nb[ns..@intCast(usize, 9)]);
var e: []const u8 = "\n"; pal_mod.markerWrite(e);

// AFTER (2 local vars, safe everywhere):
// IMPORTANT: zig0 C89 cannot pass string literal directly as []const u8 argument.
// Always use named var before markerWriteInt call.
var m: []const u8 = "LABEL:n"; pal_mod.markerWriteInt(m, val);
```
palMarkerWriteInt defined at pal.zig:99-106. Uses internal 12-byte buf + itoa_mod.itoa.
Output: `LABEL:n<value>\n`.

### Marker extraction — use `grep -a`, NOT `strings`

**CRITICAL:** `strings` strips null bytes and can silently drop entries.
Always use `grep -a` (binary-as-text) on the raw stderr file.

```bash
# Capture markers to file
./out_release/zig1 --markers --dump-c89 examples/zig0/mud_server/main.zig > out.c 2>/tmp/markers.bin

# Extract specific markers
grep -a "^PREFIX:" /tmp/markers.bin

# Count entries (reliable)
grep -a -c "^PREFIX:" /tmp/markers.bin

# Sort unique numeric values
grep -a "^PREFIX:" /tmp/markers.bin | sed 's/PREFIX: *//' | sort -n

# Multi-prefix extraction preserving order
grep -a "^IFST:\|^PBD:\|^EBLK:" /tmp/markers.bin
```

### Common marker labels in sema.zig (all use markerWriteInt)

| Marker | Meaning | Example |
|--------|---------|---------|
| STX:N | resolveExpr entry (node_idx) | STX:N   453 |
| STX:K | resolveExpr entry (kind) | STX:K    24 |
| STX:R | resolveExpr entry (result type) | STX:R    10 |
| A4:N/K/R | STB stored (non-VOID result) | A4:N   453 |
| STB:N/R | STB confirmation | STB:N   453 |
| BLK:N | resolveStmtDepth block handler entry | BLK:N   727 |
| BLK:C | Block child count | BLK:C    11 |
| BCK:B | Block child — block node_idx | BCK:B   727 |
| BCK:I | Block child — index | BCK:I     0 |
| BCK:N | Block child — child node_idx | BCK:N   345 |
| BCK:K | Block child — child kind | BCK:K    30 |
| EBLK:N | resolveExpr block handler entry | EBLK:N  753 |
| IFST:N | if_stmt handler — if_stmt node | IFST:N  427 |
| IFST:C | if_stmt handler — child_1 node | IFST:C  426 |
| IFST:K | if_stmt handler — child_1 kind | IFST:K   79 |
| IFST:2 | if_stmt handler — child_2 node | IFST:2    0 |
| IFST:K2 | if_stmt handler — child_2 kind | IFST:K2   0 |
| WST:N | while_stmt handler — node_idx | WST:N   726 |
| WST:K | while_stmt handler — body kind | WST:K    76 |
| WST:D | while_stmt handler — depth | WST:D     3 |
| PBD:N | resolveSwitchExpr prong body node | PBD:N   753 |
| PBD:K | resolveSwitchExpr prong body kind | PBD:K    76 |

## DISPROVEN zig0 C89 Bugs

Theories that were investigated and ruled out. Do NOT re-investigate.

| Theory | Disproof | Date |
|--------|----------|------|
| **C89 variable budget / stack slot reuse** — local variables corrupted at depth 3+ | Markers with wrong slice offset (`buf[0..vlen]`) produced garbled output, not codegen corruption. After fixing `palMarkerWriteInt`, all markers reliable at ALL depths. Verified with `[1]u32` box array test. | 2026-06-12 |
| **Struct-by-value return corruption** — `Slice_u32` returned by value gets corrupted at caller | 1024-element stress test: 510+ consecutive `getSlice()` calls alternating short(2)/long(63), nested outer-survives-inner, same-start-different-count. EXIT=0. zig0 C89 struct return IS correct. | 2026-06-12 |
| **Parser block truncation** — `parserParseBlock` drops children | Block 829 (.Go prong body) correctly has 8 children (payload start=273, count=8). `extra_children[273..281]` data is correct. Parser creates correct AST. | 2026-06-12 |
| **`astStoreGetExtraChildren` computation** — start/count wrong | GDB verified: payload=17891336, start=273, count=8, `start+count-start=8` in function. Returns `__make_slice_u32(items+273, 8)` correctly. | 2026-06-12 |
| **`astStoreAddExtraChildren` corruption** — appends wrong data | GDB verified: `extra_children[273..281]` = [758,771,784,797,810,818,822,828] — correct AST node indices. | 2026-06-12 |
| **TokenKind value mismatch between zig0 and C header** | C header enum values match Z98 enum order exactly (kw_var=54, kw_const=53, kw_return=68, kw_if=63). Verified via GDB + C define grep. | 2026-06-12 |
| **`strings` vs `grep -a`** — `strings` silently drops marker entries | Confirmed: `strings` strips null bytes. Use `grep -a "^PREFIX:" /tmp/markers.bin` instead. | 2026-06-12 |

## zig0 C89 Compilation Errors — Import/Missing Module Checklist

**DO NOT blame zig0 C89 limitations first.** When zig0 emits `use of undeclared identifier`, `unable to infer type`, or similar compile errors, follow this checklist IN ORDER before considering zig0 bugs:

1. **Missing `@import`** — `grep "const X = @import" <file>` vs `grep "X\." <file>`. If used but not imported, add the import.
2. **Wrong module alias** — files use different aliases for the same module: `lower.zig` → `const pal`, `semantic_analyzer.zig` → `const pal_mod`, `type_registry.zig` → `const pal_mod`. Check: `grep "const pal\|@import.*pal" <file>`.
3. **Stub file (never imported before)** — the file may have pre-existing bugs that were hidden because `main.zig` never imported it. Check: `grep "@import.*<filename>" sf/src/main.zig`.
4. **THEN consider zig0 limitations** — only after (1)-(3) are exhausted.

**Examples of false zig0-blaming (2026-06-27):**
- `pal_mod.markerWriteInt()` in `lower.zig` → "undeclared identifier" → blamed on C89 variable budget. Actual: `lower.zig` imports `const pal`, not `pal_mod`.
- `ast_mod.astStoreGetExtraChildren()` in `comptime_eval.zig` → "undeclared identifier" → blamed on type inference. Actual: `ast_mod` never imported in file (stub, never compiled before).

See AGENTS.md §9.1.1 for full rules. Memory [97cffe29](mnemoria).

## Non-Issues: Warnings That Are NOT Bugs or Blockers

Symptoms that look like failures but are EXPECTED. Do NOT treat them as
regressions, do NOT open blockers for them, and do NOT spend investigation
time chasing them.

| Symptom | Why it is NOT a bug | What to actually check |
|---------|---------------------|------------------------|
| **game_of_life: literal ANSI / terminal-clear escape codes appear in the output** | `system("clear")` writes terminal escape sequences to stdout. When output is piped or captured (not a live TTY), those sequences show up as literal bytes. **Both zig0 AND zig1 behave this way** — it is terminal behavior, not codegen. | Whether the patterns (glider, blinker, block, beehive, LWSS) and the `Generation: N` lines render correctly. The presence of escape codes is irrelevant. |
| **gcc *warnings* (as opposed to errors)** | Build commands intentionally suppress noise via `-Wno-long-long`, `-Wno-pointer-sign`, `-Wno-implicit-function-declaration`. Any remaining gcc *warnings* do not affect correctness of the produced binary. | Only the `error:` count matters. Gate builds on `gcc ... 2>&1 \| grep -c "error:"` equal to `0`. |

**Differential rule:** `zig0` is the reference oracle. A `zig1`-compiled
example is "correct" when its runtime output matches `zig0`'s output, modulo
the terminal-clear artifact described above.

## Memory Recall (DEPRECATED — use mnemoria instead)

> **DEPRECATED.** The old logfmt memory system has been migrated to `mnemoria`.
> See [Memory Recall via Mnemoria](#memory-recall-via-mnemoria) below.
> Logfmt files are preserved at `.opencode/memory/*.logfmt` for reference but
> are no longer the primary query mechanism.

Memory files local: `/workspace/znineeight/.opencode/memory/YYYY-MM-DD.logfmt`

### Read specific date:
```
Read filePath="/workspace/znineeight/.opencode/memory/2026-06-10.logfmt"
```

### Search across all dates:
```bash
grep -r "keyword" /workspace/znineeight/.opencode/memory/
```

### File format (logfmt):
```
ts=2026-06-10T01:14:11.343Z type=plan scope=project content="the memory text"
```

Types: decision, learning, preference, blocker, context, pattern
Scope: project (most common), build, api, database, etc.

### Read recent date files for current session context:
```bash
ls /workspace/znineeight/.opencode/memory/*.logfmt | sort -r | head -5
```

## Memory Recall via Mnemoria

Memories have been migrated from logfmt files to the `mnemoria` CLI tool.
Store at `.opencode/memory/` (managed by mnemoria; do NOT edit manually).

### Query Commands

```bash
# Stats
mnemoria --path .opencode/memory stats

# Search by keyword (semantic)
mnemoria --path .opencode/memory search "keyword"

# Ask a question (RAG-based)
mnemoria --path .opencode/memory ask "What issues were found?"

# Recent timeline
mnemoria --path .opencode/memory timeline --limit 10

# Filter by agent (legacy memories stored under two agents):
mnemoria --path .opencode/memory search --agent legacy-zni "keyword"
mnemoria --path .opencode/memory search --agent legacy-deleted "keyword"

# View timeline for specific agent
mnemoria --path .opencode/memory timeline --agent legacy-zni --limit 5
```

### Legacy Agent Names

| agent_name | Content | Count |
|---|---|---|
| `legacy-zni` | Active memories from pre-migration logfmt system | 1,498 entries |
| `legacy-deleted` | Previously deleted/forgotten memories, retained for reference | 431 entries |

### Type Mapping (logfmt types → mnemonia entry_type)

| logfmt type | mnemonia entry_type |
|---|---|
| learning | discovery |
| decision | decision |
| plan | intent |
| blocker | problem |
| pattern | pattern |
| context | discovery |
| preference | discovery |

### Adding New Memories

```bash
mnemoria --path .opencode/memory add \
  --agent my-agent-name \
  --type discovery \
  --summary "Brief description" \
  "Detailed content here"
```

> **Full reference:** `docs/sf/AGENTS.md` Section 9 covers all conventions, agent naming, and usage patterns in detail.

> **Memory store location (IMPORTANT — do not create a stray store):** the real,
> populated memory database lives at **`.opencode/memory`** (~2,100+ entries).
> ALWAYS pass `--path .opencode/memory` (or `-p .opencode/memory`). Running
> `mnemoria` from the repo root without `--path` reads/creates a DIFFERENT, near-empty
> store at `./mnemoria/` (a stray build-mode artifact with only a handful of entries) —
> that is NOT the project memory. If a search returns very few results, you are on the
> wrong store: re-run with `--path .opencode/memory`, raise `--limit` (default 10 is
> low; try `--limit 40`+), and vary phrasings before concluding a memory is absent.

## Writing Plans & Plan-Mode Write Permissions

The **superpowers `writing-plans` skill** produces bite-sized, TDD, task-by-task
implementation plans. Load it via the `skill` tool when you have a spec/requirements
for a multi-step task, before touching code.

- **Where plans are saved:** `.opencode/plans/YYYY-MM-DD-<feature-name>.md`
  (this overrides the skill's default `docs/superpowers/plans/`). This directory is
  **git-ignored / untracked** — writing a plan there alters nothing in the tracked
  project; it is a scratch/handoff artifact.
- **Plan mode is READ-ONLY for CODE/PROJECT/SYSTEM state only.** Per the durable
  operator decision (mnemoria, 2026-06-26 "m1213", tags `plan-mode,memory-tool,compress,allowed`),
  the following ARE permitted while in plan mode, on the operator's request:
  - Writing/updating **plan `.md` files** under `.opencode/plans/` (untracked, benign).
  - Storing memories via **`mnemoria add`** (a benign collaboration side-channel).
  - Running **`compress`** (context-management meta-op).
- **Still forbidden in plan mode:** source/code edits (`edit`/`fastedit`/`write` on
  tracked project files), shell file-manipulation, `git commit`, `git checkout`,
  config changes — i.e. any real project/code/system mutation.
- **Do not re-litigate this.** If unsure whether a specific plan-mode write is allowed,
  search mnemoria (`--path .opencode/memory search "plan mode memory-tool allowed"`)
  and follow the operator's standing authorization rather than looping.

## Code Review via Superpowers Skill

Trigger the requesting-code-review skill when auditing completed changes.

**Manual review (in-session, plan mode):** `skill: requesting-code-review`
1. Obtain diff: `git diff` or `git diff BASE..HEAD`
2. Audit against template at `~/.cache/opencode/packages/superpowers@.../superpowers/skills/requesting-code-review/code-reviewer.md`
3. Checklist: plan alignment, code quality, architecture, edge cases, tests
4. Categorize: Critical / Important / Minor
5. Give clear verdict: Ready to commit / With fixes / Do not merge

**Subagent review (build mode):** Dispatch general-purpose subagent with `BASE_SHA`/`HEAD_SHA`, fill template from `code-reviewer.md`. Reviewer inspects `git diff BASE..HEAD`, returns Strengths + Issues + Assessment.

**Key principles:** Review early/often. Fix Critical before proceeding, Important before merge. Categorize by actual severity — not everything is Critical. Acknowledge strengths before listing issues.

### Review Hardening (MANDATORY)

- Deviations from contract = `BLOCKED` (never `DONE`); controller must STOP before any commit containing a deviation.
- Reviewer prompts: no "do not flag", no pre-judged severities, no shielding of findings.
- Every fix-task gate battery MUST include RUNTIME execution; compile-only gates forbidden.
- All Important/Critical review findings → fix subagent + re-review, or explicit operator ruling. No self-adjudication.
- Verification claims require evidence (file:line, output). Unevidenced = false.

**Full policy:** `docs/sf/AGENTS.md` §2.5 (post-incident, 2026-07-17).

## zig0 Runtime h/c Architecture

The zig0 bootstrap compiler has a two-tier runtime that supports **both**
the compilation of zig1 itself (zig0 → C89 → gcc link) and the programs
compiled *by* zig1 (zig1 → C89 → gcc link). Understanding this split is
critical when adding new runtime functions or debugging linker errors.

### File Layout

| Path | Role | Used by |
|------|------|---------|
| `src/include/zig_compat.h` | C89 type definitions (`i64`, `u64`, `ZIG_INLINE`, `ZIG_UNUSED`) | All C89 output |
| `src/include/zig_runtime.h` | **Inline** bootstrap helpers (`__bootstrap_X_from_Y` casts, panic, print) | All generated `.c` files |
| `src/runtime/zig_runtime.c` | **Non-inline** runtime (arena alloc, sleep, platform console) | Linked at build |
| `$OUT/zig_runtime.h` | **Copy** of `src/include/zig_runtime.h`, emitted by zig0 via `--header-priority-include` | gcc `#include` resolution |
| `$OUT/zig_runtime.c` | **Generated** runtime .c by zig0 (includes the header) | Linked into zig1 binary |

### How zig0 Copies Headers

zig0 `--header-priority-include` copies key headers from `src/include/`
into the output directory alongside the generated `.c` files. This is why
the gcc link command (`gcc $OUT/*.c`) works without `-I` — each `.c` can
`#include "zig_runtime.h"` relative to its own directory.

To make a new header available, place it in `src/include/` — zig0 copies
all `.h` files from that directory.

### `__bootstrap_X_from_Y` Cast Helpers (Inlines)

Zig0's `@intCast(u32, i64_expr)`, `@intCast(u8, usize_expr)`, etc.
emit calls to `__bootstrap_DSTTYPE_from_SRCTYPE(source)`. These are
**inline** functions defined in `src/include/zig_runtime.h` (lines 99–180).
They use `ZIG_INLINE ZIG_UNUSED` → `static` in C89, so each generated
`.c` file gets its own copy — **no linker symbol needed**.

**Pattern** (all helpers follow this):
```c
ZIG_INLINE ZIG_UNUSED u32 __bootstrap_u32_from_i64(i64 x) {
    if (x < 0 || x > (i64)4294967295U) __bootstrap_panic("integer cast overflow", __FILE__, __LINE__);
    return (u32)x;
}
```

**Win9x safety:** These functions are **pure arithmetic + panic call**.
They use no C standard library (no `stdio.h`, `string.h`, `stdlib.h`,
`malloc`, etc.). The types (`i64`, `u64`, `u32`, etc.) are defined
per-compiler in `zig_compat.h`:
- **MSC (win9x):** `typedef unsigned __int64 u64`
- **Watcom:** `typedef unsigned long long u64`
- **gcc:** `typedef unsigned long long u64`

The `ZIG_INLINE` macro expands to `static __inline` (MSC), `static __inline__`
(gcc), or `static` (other). The `ZIG_UNUSED` macro suppresses
`-Wunused-function`.

### `src/runtime/zig_runtime.c` (Non-Inline Symbols)

For functions that **cannot** be inline (arena alloc, sleep, platform I/O),
implementations live in `src/runtime/zig_runtime.c` as regular linkable symbols.
This file is compiled separately and linked into the final binary. Note that
**not** all bootstrap helpers need a non-inline version — the inline helpers
in the header are sufficient for most casts.

Some helpers exist in BOTH places (inline header + .c definition) as a
safety fallback — see `__bootstrap_u16_from_usize` (line 286 of the .c).

### Adding a New Runtime Definition

**For a new `@intCast` target pair (inline)**:
1. Add to `src/include/zig_runtime.h` following the pattern:
```c
ZIG_INLINE ZIG_UNUSED DST_T __bootstrap_DST_from_SRC(SRC_T x) {
    if (<range check>) __bootstrap_panic("integer overflow in @intCast", __FILE__, __LINE__);
    return (DST_T)x;
}
```
2. Rebuild zig1 — zig0 copies the updated header to `$OUT`.

**For a non-inline function (linkable symbol)**:
1. Declare in `src/include/zig_runtime.h` (as `extern` or `ZIG_INLINE`).
2. Define in `src/runtime/zig_runtime.c` as a regular C function.
3. Ensure the zig1 build or zig0 runtime emission includes the `.c`.

**Common link error:** `undefined reference to '__bootstrap_U64_from_I64'`
→ This exact helper is **missing** from `src/include/zig_runtime.h`.
Add it per the inline pattern above. (Added 2026-06-29 for enum(u8) support.)

### Tech Docs (as-built pipeline reference)
Location: sf/docs/tech_docs/
INDEX.md — master cross-reference (error→phase, function→file, marker→meaning)
00_shared_infra.md — Allocator, Interner, Diagnostics, PAL, Source Manager, utility modules
00_lexer_parser.md — Lexer, Parser, AST
01_import_resolution.md — Module graph & import resolution
02_symbol_registration.md — Symbol table registration
03_type_resolution.md — Type resolution & registry
04_comptime_eval.md — Compile-time evaluation
05_semantic_analysis.md — Semantic analysis (resolveExpr, resolveStmtDepth)
06_static_analyzers.md — Flow-sensitive static analyzers
07_lir_lowering.md — LIR lowering & control-flow flattening
08_c89_emission.md — C89 code emission & name mangling
09_pipeline_orchestration.md — Pipeline orchestration (main.zig, main_dump.zig)
10_c_runtime.md — C runtime layer (zig_runtime.c/h, zig_pal.c/h)
11_build_system.md — Build scripts & output isolation
