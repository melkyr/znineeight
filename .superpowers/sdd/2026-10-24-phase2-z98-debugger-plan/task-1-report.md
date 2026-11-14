# P3-M1 Task 1 report — `--debug`/`-d` map emission (compiler side)

**Status:** DONE_WITH_CONCERNS
**Branch:** `zig1_improvements`
**Code commit:** `4df9a753` `feat(c89_emit): -d debug map emission (Phase2 P3-M1)`
**Docs commit:** (this report)
**Final seed-built compiler:** `/tmp/z98_build/zig1_5_clean`; script closure
`hop1 == hop2 == f963c2c49ab4ca66ac340917d5634494`.

---

## 1. What was implemented

### 1.1 `sf/src/debug_map.zig` (new)

- `DebugSpanStore` — parallel per-function spill of `DebugSpanEntry`
  (`bb`, `inst`, `span_start`) keyed by `LirSlot.disk_offset`. It is deliberately
  outside `lir_stream` (record format / `expected_len` untouched). Lowering appends
  one function's list before the scratch reset; emission reads exactly one
  function's list at a time (O(one function) RAM). Spill file:
  `<output-dir>/.zig1_dbg.tmp` (`w+b`).
- `DebugSpanEntry` list type + append/ensure helpers live in `sf/src/lir.zig`
  (next to `LirSideEntry`); `LirInst` is unchanged (still 32 B).
- `DebugSymbolList` — one small record per fn/global (kind, extern flag,
  name/module/type ids, resolved source line/file id, declaration span).
  Used for `.syms`, `.cnames`, and the async fallback.
- `DebugMapWriter` — streamed writers for the three binding sidecars:
  - header: 8-byte magic + `u32 version=1` + `u32 record_count` +
    `u32 file_total_len` (count + length patched by absolute seek at close);
  - `.syms`: `u8 kind`, `u32 src_line`, `str16 src_name`, `str16 module_stem`,
    `str16 src_file`, sorted by `(src_file, src_line, name)`;
  - `.lines`: group `str16 src_file`, `str16 out_file`, `u32 run_count`, then
    runs `u32 src_line, u32 out_line_start, u32 out_count`; groups in emission
    order, RLE on adjacent out lines sharing a source line, group run count
    patched by seek at group end. `record_count` = total runs;
  - `.cnames`: `str16 src_name`, `str16 mangled_name`, sorted by `src_name`
    (ties module/kind), emitted whenever `-d`.
- All strings are little-endian `u16`-prefixed; all integers little-endian.

### 1.2 `sf/src/lir.zig`

- Adds only `DebugSpanEntry` / `DebugSpanArrayList` (+ init/ensure/append/getSlice).
  No `LirInst` change; `lir_stream.zig` is untouched (`git diff` empty).

### 1.3 `sf/src/lower.zig`

- `LirLowerer` gains `debug_enabled: u8` and `debug_spans: DebugSpanArrayList`.
- `emitInst` (was `:574`) captures the current AST node span for the inst's
  `(bb, inst)` ordinal **before** appending, only when enabled and
  `span_start != 0`. Off: one flag check, no list work, no allocation.

### 1.4 `sf/src/c89_emit.zig`

- `BufferedWriter.line: u32`, incremented on `\n` in `bufferedWriterWrite` and
  `bufferedWriterWriteByte` (indent emits spaces only). Output bytes unaffected.
- `emitInst` body-loop hook records one run per LIR inst:
  `out_line = line_before+1`, `out_count = after-before`, mapped through the
  faulted-in function span table. DCE / nest-inlined skips never call
  `emitInst`, so they produce no row. `.lines` RLE lives in the writer.
- Per-function span load into emitter scratch; async step/driver fallback maps
  every synthetic inst to the suspending function's declaration line (see §6).
- `C89Emitter` debug pointers default null; with `-d` off no map path runs.

### 1.5 `sf/src/main.zig`

- CLI: `--debug` / `-d`; usage line; `CompilerCli.debug`.
- Banner on stderr for all normal runs:
  `Z98 Compiler 2026 (map: on|off)`; suppressed only by `--quiet`.
- Operator ruling A: `-d` without `--output-dir` writes
  `error: --debug/-d requires --output-dir`, exits 2, emits no C and no map.
- Opens the debug span spill at the start of lowering; appends one function's
  spans before each scratch reset (non-async function + module-init).
- Captures fn/global symbol records while the AST/source is alive (line via
  `sourceManagerGetLocation`).
- Emission: opens `<root-stem>.z98dbg.{syms,lines,cnames}` in `--output-dir`,
  begins/ends one `.lines` group per emitted module `.c` (emission order),
  closes (sorts symbols, patches headers) before build-script emission.

### 1.6 `scripts/compiler/gate_debug_map.sh` (new)

Gate style follows `gate_cipher_rodata.sh` (`set -euo pipefail`, `ROOT` from
script dir, `ZIG1` arg, `mktemp -d` + trap, note/bad, exit 0/1). It defaults the
baseline compiler to the archived seed binary extracted from
`release/seed/zig1-seed.tgz` (pre-change v119 compiler).

Assertions: one of each map file; magics/version; `.syms` contains `main` with a
plausible line; 3× maps byte-identical; no-`-d` creates zero map files and the
emitted `.c` set is byte-identical to the baseline compiler; `-d` without
`--output-dir` rc 2 + empty stdout + no maps; banner on/off and `--quiet`
suppression.

---

## 2. RED gate evidence (written first, before implementation)

Command:

```bash
bash scripts/compiler/gate_debug_map.sh \
  /tmp/z98_seed/zig1-seed/zig1 /tmp/z98_seed/zig1-seed/zig1
```

Output (rc=1):

```
[gate_debug_map] zig1: /tmp/z98_seed/zig1-seed/zig1
[gate_debug_map] baseline zig1: /tmp/z98_seed/zig1-seed/zig1
[gate_debug_map] FAIL: missing 'map: on' banner
[gate_debug_map] FAIL: expected one .z98dbg.syms, got 0
[gate_debug_map] FAIL: expected one .z98dbg.lines, got 0
[gate_debug_map] FAIL: expected one .z98dbg.cnames, got 0
DEBUG_MAP GATE FAILED
```

---

## 3. GREEN gate evidence (final build)

Command:

```bash
bash scripts/compiler/gate_debug_map.sh \
  /tmp/z98_build/zig1_5_clean /tmp/z98_seed/zig1-seed/zig1
```

Output (rc=0):

```
[gate_debug_map] zig1: /tmp/z98_build/zig1_5_clean
[gate_debug_map] baseline zig1: /tmp/z98_seed/zig1-seed/zig1
[gate_debug_map] ok .syms main row
[gate_debug_map] determinism: 3x map byte-identical
[gate_debug_map] purity: no-'-d' .c set byte-identical to pre-change baseline
[gate_debug_map] banner on/off + --quiet suppression ok
DEBUG_MAP GATE OK
```

Independent structural check on `hello` (`-d`):

```
main_B90321E3.z98dbg.syms    16714 B   header count 249, total 16714
main_B90321E3.z98dbg.lines     154 B   header count 2, total 154, 2 groups / 2 runs
main_B90321E3.z98dbg.cnames   7896 B   header count 249, total 7896
MAIN kind 0 line 2 mod main_B90321E3 file examples/z98/hello/main.zig
```

`.lines` rows for the test set were independently parsed and every run checked
against the real source-file and emitted `.c` line counts:

| Program | groups | runs | bad rows |
|---|---:|---:|---:|
| hello | 2 | 2 | 0 |
| mud_server | 5 | 519 | 0 |
| lisp_interpreter_curr | 11 | 989 | 0 |
| z9torr | 35 | 8659 | 0 |

Header `record_count` equaled the sum of group run counts in all four.

---

## 4. Battery (final build)

### 4.1 Seed build

```bash
bash scripts/seed/build_from_seed.sh release/seed/zig1-seed.tgz /tmp/z98_build
```

`=== [seed] Done: /tmp/z98_build ===`
`[seed] two-hop closure OK: hop1 == hop2 == f963c2c49ab4ca66ac340917d5634494`

### 4.2 Corpus — frozen-1124 subset, 0 movers

```bash
bash scripts/corpus/classify /tmp/z98_build/zig1_5_clean /tmp/corpus_final2.txt
# current universe 1187 dirs; filter to the frozen snapshot universe (1132 at
# c0c26eeb, minus the 8 designed fixtures) => 1124 lines
```

Result:

```
1124 lines
md5 518eca1a9b5d3e1cc5a48abce214abd8
950 OK / 58 GREEN / 116 FAIL / 0 ICE / 0 CRASH
```

Byte-identical to the frozen anchor; **0 movers**. (The 8 designed fixtures
removed from the snapshot universe are the T0–T4 set:
`fnptr_opt_aggregate_{coerce,emit}_xmod`, `iswindows_deadarm_{errunion,prune,cond_if}_xmod`,
`conditional_import_{if,switch}_xmod`, `comptime_if_noelse_deadarm_xmod`. The
55 dirs added after the snapshot were not part of the frozen gate.)

### 4.3 Runtime goldens — 5/5

| Program | measured | expected | result |
|---|---|---|---|
| game_of_life (100 gen) | `fcbf7e7cead5082f0a8caadd5a8f0ff9` | `fcbf7e7c…` | MATCH |
| lisp `(+ 1 2)` | `b3d9f8974da24ddbf9d389f3d7d97322` | `b3d9f897…` | MATCH |
| json_parser | `8bda3d5a1ec07d14a301bc343df32bf8` | `8bda3d5a…` | MATCH |
| mud server stdout | `66c8f0abb926cca7baf9a0d1692ab318` | `66c8f0ab…` | MATCH |
| mud client bytes | `93147d0f0bbd983a9d844fea8b7a6fa7` | `93147d0f…` | MATCH |

Mud canonical session used `examples/z98/mud_server/demo/session.sh` (rc 0).

### 4.4 8 dump-MD5 pins

Command (`<seed-built compiler> <mode> --dump-c89 <entry> | md5sum`, repo root,
relative entry paths):

| Entry | `-fsafe` | `-ffast` |
|---|---|---|
| `examples/z98/mud_server/main.zig` | `76c05e6e35ec0357dd61e330bd825c99` | `3611017bb1ae0806288107347395a5e8` |
| `examples/z98/game_of_life/main.zig` | `f83316ad82c40077553cb25fbec7620b` | `d1bc475b1e088475e3b527e0c06d13f1` |
| `examples/z98/lisp_interpreter_curr/main.zig` | `e51e62ddb5d1c099c3d67f972a7181a8` | `21339525dc1d2aab1b539b19b8375872` |
| `examples/z98/json_parser/main.zig` | `b3f05fbea0b8dc5ca34a8ca0b73dbb09` | `cf25f6ecf323bca4ad7789e161be0bf6` |

Pre-change archived-seed baseline measured with the same command **equals these
exactly, 8/8** (`diff /tmp/pins_oldbin.txt /tmp/pins_final2.txt` empty).
The values in QUICK_REF:386-400 are the stale v103 table; all 8 differ from it
on this v119 seed (see Concerns).

### 4.5 Markers

```bash
/tmp/z98_build/zig1_5_clean -q --markers --dump-c89 \
  --output-dir /tmp/z1mk examples/z98/mud_server/main.zig 2> /tmp/markers_final2.bin
```

`3086 lines / 35145 bytes`, md5 `61ff9ae11b996bd454bf25e7f47b8491`.
Pre-change seed binary produced the identical marker stream
(`3086 / 35145`, same md5). `-q` is used so the new banner does not add one
stderr line; the marker payload itself is unchanged.

### 4.6 Examples — 26/26 build + 26/26 run

Build per dir (`-ffast -o <out> <entry>` + `sh build_target.sh linux prog`);
run CWD = example dir, stdin `/dev/null`, timeout 25 (mud 8, rogue fed `q\n`).

```
BUILD pass=26 fail=0   RUN ok=26 bad=0
```

All 26 stdout md5s matched the recorded table:
`8c0d394c`, `b53b3a3d`, `f6a54779`, `fcbf7e7c`, `8cf0a784`, `74630882`,
`8bda3d5a`×2, `dc22fa47`, `1c1f0a41`×4, `c3c7765e`, `d5966775`, mud rc124
`9545fe1d`, `d095a94d`, `45d2f0fb`, `3fb6709e`×2, `c6c047cb`, `264ea6b1`,
`3d70c50b`, `7421137a`, z9play rc1 `f35b7ef7`, z9torr rc1 `f666af15`.

### 4.7 `check_emit_support.sh`

`bash scripts/check_emit_support.sh /tmp/z98_build/zig1_5_clean`
→ `OK: 8/8 support files byte-identical to canonical` (rc 0). The task brief
said 5/5; the tree now checks 8 (6 core + 2 conditional preludes).

---

## 5. Cost measurement (final build, 3 runs each; `/usr/bin/time -v`)

`-q -ffast`, entry paths as listed; `-d` includes map emission.

| Program | mode | wall (s, 3 runs) | max RSS (KiB, 3 runs) | median ΔRSS |
|---|---|---|---:|---:|
| hello | off | 0.04 / 0.04 / 0.04 | 6088 / 6096 / 6168 | — |
| hello | on | 0.05 / 0.05 / 0.04 | 6388 / 6192 / 6320 | ≈ +0.2 MB |
| mud_server | off | 0.05 / 0.05 / 0.05 | 8088 / 8172 / 8092 | — |
| mud_server | on | 0.06 / 0.06 / 0.06 | 8580 / 8600 / 8324 | ≈ +0.4 MB |
| lisp_interpreter_curr | off | 0.07 / 0.07 / 0.07 | 6288 / 6388 / 6552 | — |
| lisp_interpreter_curr | on | 0.07 / 0.07 / 0.07 | 6588 / 6716 / 6456 | ≈ +0.2 MB |
| z9torr | off | 1.12 / 1.02 / 1.00 | 20728 / 20248 / 20764 | — |
| z9torr | on | 1.05 / 1.05 / 1.18 | 22076 / 22332 / 22008 | ≈ +1.8 MB |

Time delta is ≈ 0–0.05 s. RSS delta is not literally zero: the per-function
span table is O(one function) but z9torr's largest emitted function is
sufficiently large to add ~1.8 MB peak; the map itself is streamed and never
retained whole. This is within the design's O(one function) streaming rule,
but larger than the brief's "expect ≈0" wording.

---

## 6. Self-review findings / concerns

1. **QUICK_REF 8-pin table is stale for v119.** The brief/globals say compare
   "old values QUICK_REF:386-400, expect unchanged". Those are v103 values and
   none matches the current pre-change compiler. The authoritative pre-change
   baseline is the archived v119 seed binary: measured new == old 8/8 (and the
   gate proves no-`-d` `.c` bytes for hello). No regression; the table needs a
   future re-baseline.
2. **Markers reference count is stale.** QUICK_REF/inventory cite 3437 lines /
   38384 B; current pre-change and post-change both produce 3086 / 35145
   (marker payload unchanged). The banner adds one stderr line for non-`-q`
   runs (required behavior), which is why `-q` is used for the marker compare.
3. **Async fidelity is function-granular.** Async step/driver functions get no
   per-inst spans from lowering (they bypass `emitInst`). The emitter fallback
   attributes every inst in them to the suspending function's declaration line
   (spec §7.3 caveat), not the exact suspension statement.
4. **`.syms` / `.cnames` scope.** `.syms` contains fn and global declarations;
   `.cnames` contains fn/global name pairs (types are not included). The
   consumer treats `.cnames` as optional; this matches the debugger's backtrace
   and symbol use.
5. **`-d` without `--output-dir` stderr.** Banner is emitted first (all-runs
   banner rule), then the exact error line. If "one clean line" was meant to
   exclude the banner on this error path, the banner order should be revisited.
6. **Tech docs not updated.** `docs/sf/AGENTS.md` §1.1.1 asks for tech-doc
   updates when pipeline code changes; the task's explicit deliverables named
   only the code files, gate, and this report, so no `sf/docs/tech_docs/` edit
   was made. Flagged for operator decision.
7. **Potential issue reviewed and accepted:** `debugLoadFnSpans` runs before
   `lirOptRun`; that pass only replaces insts in place (no count/ordinal
   change), so `(bb, inst)` keys stay valid. DCE/nest skips produce no rows by
   construction.
8. **No `lir_stream` change:** `git diff -- sf/src/lir_stream.zig` is empty;
   `LirInst` remains 32 B; map state is parallel spill only.
9. **Determinism:** 3 gate runs byte-identical; no pointer/address-dependent
   ordering; symbol sorts use string/line/module keys.

---

## 7. Files changed

Code commit `4df9a753`:

- `sf/src/debug_map.zig` (new, 554 lines)
- `sf/src/lir.zig` (+49)
- `sf/src/lower.zig` (+21)
- `sf/src/c89_emit.zig` (+114/−2)
- `sf/src/main.zig` (+138)
- `scripts/compiler/gate_debug_map.sh` (new, 191 lines, mode 100755)

Docs commit: this report.

---

# Fix round 1

**Status:** DONE_WITH_CONCERNS
**Commit:** `d7882717` `fix(c89_emit): hoisted-decl rows + per-function span reuse (Phase2 P3-M1)`
**Final seed-built compiler:** `/tmp/z98_build/zig1_5_clean`; closure
`hop1 == hop2 == 11de43a053bdde3be3ddc61caac31df6`.

## F2 — hoisted declarations now produce map rows

- `emitHoistedDecls` builds a per-function `temp_span[]` (temp id -> source
  span) from the faulted-in `(bb, inst)` debug spans and the first inst that
  defines each temp. `debugInstDefTemp` mirrors `dceResultPos`'s extra result
  arms (`width_wrap`, overflow ops, `int_cast_checked`, `va_arg`) and adds
  `call`, `call_direct`, `tail_call`, `decl_temp`, `decl_local`.
- Each hoisted declaration output line (including `zig_poison_fill` lines) now
  adds a `.lines` run mapped to that owning statement's Z98 line via the shared
  `debugMapAddSpanRun`. Map byte format is unchanged.
- Temps whose def span is synthetic/EOF-only fall back to the function
  declaration span instead of emitting an out-of-file line; body rows whose
  span is at/after the source content length are dropped.
- The temp table/scan/allocation are behind `emitter.debug_map != null`; the
  no-`-d` path allocates and scans nothing.

Gate extension (written before the fix, RED observed first): compiles
`examples/z98/fibonacci/main.zig` with `-d`, extracts every contiguous
`zT_*` hoisted declaration line at the top of emitted functions, and requires
each one to be covered by a `.lines` run whose `src_line` is a real source
line.

RED (old build, before fix; rc=1, relevant lines):

```
[gate_debug_map] ok .syms main row
[gate_debug_map] FAIL: hoisted declaration line main_65487C87.c:4 is not mapped to a plausible src_line
[gate_debug_map] FAIL: hoisted declaration line main_65487C87.c:5 is not mapped to a plausible src_line
...
[gate_debug_map] FAIL: hoisted declaration line main_65487C87.c:53 is not mapped to a plausible src_line
DEBUG_MAP GATE FAILED
```

GREEN (final build):

```
bash scripts/compiler/gate_debug_map.sh \
  /tmp/z98_build/zig1_5_clean /tmp/z98_seed/zig1-seed/zig1
[gate_debug_map] ok .syms main row
[gate_debug_map] ok hoisted declarations mapped (22 lines)
[gate_debug_map] determinism: 3x map byte-identical
[gate_debug_map] purity: no-'-d' .c set byte-identical to pre-change baseline
[gate_debug_map] banner on/off + --quiet suppression ok
DEBUG_MAP GATE OK
```

Independent `.lines` row validation after the fix (source line within source
file, output run within emitted `.c`):

| Program | rows | bad |
|---|---:|---:|
| mud_server | 885 | 0 |
| lisp_interpreter_curr | 1520 | 0 |
| z9torr | 13922 | 0 |

## F3 — per-function span storage reused regardless of `async_pending`

- `CompilerContext.debug_span_buf` is one reusable `DebugSpanArrayList` on the
  emission arena. Every function/module-init lowering starts with
  `lowerer.debug_spans = ctx.debug_span_buf; len = 0`, and immediately after
  lowering the (possibly grown) list is copied back and `len` reset — before
  the async/scratch-reset branch. Map span memory is therefore bounded by the
  largest single function (plus geometric growth slack), not by every function
  after the first async one.
- Async synthetic step/driver rows still use the F2 declaration-span fallback.
- The map spill itself remains streamed and keyed by `LirSlot.disk_offset`.

## Off-path neutrality / pins

- No-`-d` output bytes: gate purity PASS vs the archived pre-change seed binary.
- 8 dump-MD5 pins re-run on the final build; `diff` vs the pre-change archived
  seed baseline is EMPTY (8/8 unchanged):

```
mud_server          -fsafe 76c05e6e35ec0357dd61e330bd825c99   -ffast 3611017bb1ae0806288107347395a5e8
game_of_life        -fsafe f83316ad82c40077553cb25fbec7620b   -ffast d1bc475b1e088475e3b527e0c06d13f1
lisp_interpreter_curr -fsafe e51e62ddb5d1c099c3d67f972a7181a8 -ffast 21339525dc1d2aab1b539b19b8375872
json_parser         -fsafe b3f05fbea0b8dc5ca34a8ca0b73dbb09   -ffast cf25f6ecf323bca4ad7789e161be0bf6
```

- `scripts/check_emit_support.sh /tmp/z98_build/zig1_5_clean`
  → `OK: 8/8 support files byte-identical to canonical` (rc 0).
- The diff is gated by `debug_map != null` / `cli.debug` everywhere except the
  shared `BufferedWriter.line` counter added in round 0; no full battery was
  re-run because no off-path code changed. (The gate still re-checks no-`-d`
  purity against the archived seed.)

## RSS before/after (`-q -ffast`, 3 runs, `/usr/bin/time -v`)

"Before" = round-0 build measured before this fix; "after" = final build.

| Program | mode | before max RSS (KiB) | after max RSS (KiB) |
|---|---|---|---|
| hello | off | 6088 / 6096 / 6168 | 6280 / 6256 / 6428 |
| hello | on | 6388 / 6192 / 6320 | 6376 / 6476 / 6580 |
| mud_server | off | 8088 / 8172 / 8092 | 8000 / 8176 / 8104 |
| mud_server | on | 8580 / 8600 / 8324 | 8428 / 8408 / 8472 |
| lisp_interpreter_curr | off | 6288 / 6388 / 6552 | 6496 / 6448 / 6484 |
| lisp_interpreter_curr | on | 6588 / 6716 / 6456 | 6816 / 6864 / 6512 |
| z9torr | off | 20728 / 20248 / 20764 | 20768 / 20516 / 20460 |
| z9torr | on | 22076 / 22332 / 22008 | 21408 / 21312 / 21396 |

z9torr `-d` median: **22,076 → 21,396 KiB** (−680 KiB). The dedicated
per-function buffer removes the post-first-async accumulation, leaving the
largest function's own O(one function) span table plus map/symbol state.
`-d` delta vs the same-build off run is ≈880 KiB (21,396 − 20,516 median)
instead of ≈1,348 KiB before (22,076 − 20,728). Wall time unchanged within
noise (z9torr 1.07–1.08 s on vs 1.02–1.04 s off).

## Files changed (fix commit `d7882717`)

- `sf/src/c89_emit.zig` (+102/−10): hoisted-decl temp spans/rows, function
  declaration fallback, span/source-length filtering, shared run helper.
- `sf/src/main.zig` (+18): reusable `debug_span_buf`; per-function reset/copy
  independent of `async_pending`.
- `scripts/compiler/gate_debug_map.sh` (+71): hoisted-declaration case.

## Fix-round concerns

1. The hoisted gate uses `fibonacci` (an existing example) rather than a new
   fixture, so no corpus-universe change was introduced.
2. Async rows remain function-declaration-granular, not suspension-statement
   granular (spec §7.3 caveat).
3. Temps with synthetic/EOF-only def spans are attributed to the function
   declaration line; the alternative was an unmapped declaration line or an
   out-of-file line number.
4. F1 banner behavior untouched, as adjudicated.
5. Tech docs remain untouched per the task's explicit file list (same
   outstanding note as round 0).
