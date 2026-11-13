# UNDERSANDED M1 — notes

## Preflight

- Compiler seed: **v149** (committed seed `release/seed/zig1-seed.tgz`).
- Compiler binary: `/tmp/zig1-m1/zig1_5_clean`, md5 `73c75a65e30dfd212fdf93ae1e57a687`
  (md5 matches the v149 archived-binary fixed point).
- Baseline: `ZIG=<above> OUT=/tmp/z9edit_m1_base sh examples/z98/z9edit/tests/tier_edit.sh`
  -> `TIER_EDIT PASS` (38 passed, 0 failed; lexer md5
  `dcc81009e9a36c86e4d90e104c439871`; compile max RSS 6088 KiB).
- Std test convention: fixtures under `repro/mi_matrix/stdlib_<module>_<name>_xmod/`
  (or `stdlib_test/<name>/`) with committed `expected.txt` + `expected.rc`, run by
  `scripts/stdlib/run_fixtures.sh` / `scripts/stdlib/verify_stdlib.sh`
  (`zig1 -ffast -o`, gcc binding flag-set, `build_target.sh linux`, run 3x).

## Corrected G-table (M1 Task 1 audit)

Statuses below are the as-found audit snapshot (pre-M1 patches); M1 closed
G2/G4/G5/G10/G11/G13/G14; G12 was CLOSED-ALREADY (reuse `std_math`, M2
amendment `bbc4cd27`) — see the M2 amendment review below and the tier.

Audited against `sf/src/` on 2026-11-13. Status legend: **CLOSED-ALREADY** = real
surface already satisfies the row; **PARTIAL** = some of it exists (missing part
named); **REAL GAP** = not present; **GAME-SIDE** = deliberately built in
`examples/z98/undersanded/`, not std.

Import convention (docs/sf/QUICK_REF.md:119): only L0–L2 modules are re-exported
by `std.zig`; L3+ modules (`std_file`, `std_parse`, `std_crypto`, `std_gfx`, …)
are imported by path (`@import("std_parse.zig")`), and that is supported/proven
(e.g. `examples/z98/z9torr/main.zig:8`).

| # | Status | Evidence in `sf/src/` (exact names) | Remaining work |
| :-- | :--- | :--- | :--- |
| G1 | **CLOSED-ALREADY** | `std_file.zig`: `open`:319, `close`:324, `read`:328, `write`:332, `seek`:336, `size`:343, `flush`:349, `exists`:353, `mtime`:369, `remove`:383, `rename`:393, `readAll`:405, `writeAll`:433, `openDir`:458, `readDir`:496, `closeDir`:528. `readAll`/`writeAll` confirmed. | none |
| G2 | **PARTIAL** | `std_str.zig` has `eql`:16, `startsWith`:50, `endsWith`:59, `split`:130, `splitLines`:154, `join`:181, `trim`:204, `indexOf`:227, `lastIndexOf`:238, `eqIgnoreCase`:250, `replace`:261, `count`:298, `repeat`:308. **No `splitOnce` anywhere.** **No `parseInt` in `std_str`**; it exists in `std_parse` (G17). | add `splitOnce`; decide whether `std_str.parseInt` is needed or `std_parse.parseInt` is used directly |
| G3 | **PARTIAL** | `std_mem.zig`: `copyU8`:1, `copyU32`:8, `copyU64`:15, `zeroU8`:22, `eqlU8`:29. No generic `copy`/`set`/`eql`; no value-fill (`set`/memset-style) — only zero-fill. Struct copies/eql are covered by the typed variants. | add a value-fill if any caller needs non-zero fill; otherwise the typed surface is sufficient |
| G4 | **REAL GAP** | `std_gfx.zig` has only `gfxPollEvent`:157 (delegates to `std_gfx_pal.pollEvent`:1564, a `PeekMessageA` spin). **No `gfxWaitEvent`; no `MsgWaitForMultipleObjectsEx` binding.** | implement `gfxWaitEvent(g, timeout_ms)` in `std_gfx` + `std_gfx_pal` |
| G5 | **REAL GAP** | `Event` (`std_gfx.zig`:41) fields are `x`,`y` (lines 45–46) in **cells**. `std_gfx_pal.pollEvent` computes `raw.x = mx / st.cw`, `raw.y = my / st.ch` (`std_gfx_pal.zig`:1691–1692); the raw pixels are discarded. No `px`/`py`. | add `Event.px/py` (client pixels) sourced before the cell division |
| G6 | **REAL GAP** | No `sf/src/std_gfx_px.zig` (nor `std_audio`-style sibling). `std_gfx_pal.Surface7Vtbl` (`std_gfx_pal.zig`:429) types only `Blt`:435, `Release`:432, `GetDC`:447, `ReleaseDC`:456, `Restore`:457, `SetClipper`:458, `SetColorKey`:459; `Lock`:455, `Unlock`:462, `BltFast`:437 are still `extern "stdcall" fn() void` placeholders. Reference typed signatures exist in `std_ddraw_pal.zig` (`Blt`:257, `Lock`:277, `Unlock`:284; `BltFast` still placeholder:259). | M9: create `std_gfx_px`; type `std_gfx_pal` `Lock`/`Unlock`/`BltFast` from the `std_ddraw_pal` reference |
| G7 | **REAL GAP** | `std_gfx.zig` has no `gfxSetFixedSize` (pub surface is `gfxOpen`/`gfxOpenMemory`/`gfxTestResize`/…; grep finds none). | M9: add fixed-size window support |
| G8 | **REAL GAP** | No `gfxPresentRect`; existing present is whole-window `beginFrame`/`endFrame` (`std_gfx.zig`:220/226). | M9: add dirty-rect present |
| G9 | **REAL GAP** | No `sf/src/std_audio.zig`. `std_dsound.zig` is streaming only: `dsoundOpen`:30, `dsoundWrite`:43, `dsoundQueued`:48, `dsoundBackendKind`:53, `dsoundClose`:58. No buffer/WAV/play/stop/volume. | M12: new `std_audio` (static buffers + WAV + play/stop/volume) |
| G10 | **REAL GAP** | `std_file.zig` has no path join, no 8.3/short-name validation (only internal `cstr`:123). `std_str.join`:181 is a generic slice join, not path-aware. No `GetShortPathNameA` binding in `std_file_pal.zig`. | implement game-side `pathJoin83`/`is83Name` (M1 Task 3); reject long/non-8.3 names |
| G11 | **PARTIAL** | CRC-32 already exists in `std_crypto.zig`: `crc32Init`:963, `crc32Update`:967, `crc32Final`:1009, with `Crc32Table`:781. It is **not** in `std_bits` and there is no one-shot `crc32(data)`; `std_crypto` is imported by path. | add/choose a one-shot `crc32(data)` wrapper (std_bits or a thin wrapper over std_crypto); do not duplicate the table |
| G12 | **CLOSED-ALREADY** | `std_math.zig`: `min`:1, `max`:6, `minU`:11, `maxU`:16, `abs`:21, `clamp`:26, `clampU`:32. | none (no game-side copies needed) |
| G13 | **PARTIAL** | `std_gfx.EventKind` (`std_gfx.zig`:30) has no `focus_lost`/`focus_gained`; `std_gfx` has no `gfxTestFocus`. Raw focus *is* handled in the sibling `std_ddraw_pal.zig`: `WM_SETFOCUS`:40, `WM_KILLFOCUS`:41, `EVENT_FOCUS`:66, dispatch at 816–819; `std_ddraw.DdrawEvent` (`std_ddraw.zig`:19) exposes only `kind`/`key`/`close`. | M1 Task 4: add `EventKind.focus_lost`/`focus_gained` + `gfxTestFocus` to `std_gfx`/`std_gfx_pal` (reuse the `std_ddraw_pal` WM_SETFOCUS/KILLFOCUS pattern) |
| G14 | **GAME-SIDE** | No writability probe / fallback in `std_file`/`std_os`. `std_os` has `initArgs`:45, `argc`:50, `argv`:54, `exit`:61, `env`:66, `cwd`:240 but **no `modulePath`/exe-dir helper** (`GetModuleFileNameA` not bound). | M1 Task 5: `paths.zig` (`probeWritable`, `resolveDataDir`, `dataDirOrFallback`); add `std_os.modulePath` as needed |
| G15 | **CLOSED-ALREADY** | Link config exists: compiler-generated build targets default to `/subsystem:console,4.0` (`sf/src/c89_emit.zig`:10044, 10102); GUI is opt-in via `EXTRA_LDFLAGS=-Wl,--subsystem,windows` (`scripts/win32_cross/cross_nocrt.sh`:62; used by `examples/z98/z9edit/tests/tier_edit_gui.sh`:119). Both subsystem paths are already exercised by z9edit. | M1 Task 6: game-side `build.sh` picks GUI for `under.exe`, console for `undtool.exe` |
| G16 | **PARTIAL** | `std_file.remove`:383 and `std_file.rename`:393 exist and verify failure via `error.RemoveFailed`/`error.RenameFailed`. No rollback-safe wrapper. Note `rename` uses `MoveFileA`, which does **not** replace an existing target (`examples/z98/z9git/httpgit.zig`:1553). | M7: game-side backup/rollback-safe save wrapper (remove-then-rename dance) |
| G17 | **CLOSED-ALREADY** | `std_parse.zig`: `parseInt`:42, `parseUint`:67, `parseInt64`:82, `parseUint64`:109, `parseFloat`:124, `itoa`:165, `utoa`:191, `itoa64`:208, `utoa64`:231, `ftoa`:429. Importable by path and already used (`examples/z98/z9torr/main.zig:8` imports `std_parse.zig`, `itoa64` at :87). Not re-exported by `std.zig`, which matches the documented path-import convention. | none; do not add duplicate twins |

Other audit facts relevant to M1 tasks: `std_debug` has `setTrapHandler`:119,
`backtrace`:128, `writeCoreDump`:149, `logInt`:31 (trap handler can be wired as
specified). `std_os` lacks an exe/module path helper (Task 5 must add it).
`std_bits` has no CRC (`popcount`/`clz`/`ctz`/rot/`mask`/`extract`/`insert`/
`isPow2`/`nextPow2` only).

## Task 4 import gate amendment

`scripts/win32_cross/check_win9x_imports.sh` `USER32_ALL` adds
`MsgWaitForMultipleObjectsEx` (sorted between `MessageBoxA` and `OpenClipboard`)
and `GetForegroundWindow` (USER32 allow-list; sorted between `GetDC` and
`GetKeyState`), the latter used for real focus polling.
`gfxWaitEvent` uses `MsgWaitForMultipleObjectsEx` to block on the thread input
queue (QS_ALLINPUT) instead of spinning `PeekMessageA`; the call is `nCount=0`,
`pHandles=NULL`, so only queued input signals it. The symbol is exported by
Win98 user32.

## Task 5 import gate amendment

`scripts/win32_cross/check_win9x_imports.sh` `KERNEL32_9X` adds
`CreateDirectoryA` (sorted between `ContinueDebugEvent` and `CreateEventA`;
`KERNEL32_NT` inherits the 9x list). `paths.dataDirOrFallback` uses it to create
the writable-data fallback directory on the win32 branch (POSIX uses `mkdir`).
The symbol is exported by Win98 kernel32.

## Task 6 link configs + skeleton + trap handler (G15)

Ruling A (user-approved): Z98 has no program-level `-D` build option, so the
two presentation modes are chosen at **link time** by thin entries over one
shared implementation, not by a runtime `--headless` flag:

- `app.zig` — shared skeleton: `std_os.initArgs`, trap handler, data-dir
  resolution/probe, read `sample.txt` from the exe dir, write `probe_out.txt`
  into the writable dir (`paths.dataDirOrFallback`), draw one line, exit 0.
- `main.zig` — GUI entry: `gfxOpen(80, 30)` titled `UNDERSANDED`.
- `main_console.zig` — CUI entry: `gfxOpenMemory(80, 30)` + stdout, no window.

`build.sh` (from repo root; `ZIG`/`OUT` env overrides):

- `under.exe` — GUI, no-CRT: `cross_nocrt.sh` with `DUMP_TARGET="-osw"`,
  `EXTRA_LIBS="-luser32 -lgdi32"`, `EXTRA_LDFLAGS="-Wl,--subsystem,windows"`,
  entry `main.zig` (precedent: `z9edit/tests/tier_edit_gui.sh`).
- `undtool.exe` — CUI, no-CRT: `DUMP_TARGET="-osw"`, entry
  `main_console.zig`, console subsystem (no `--subsystem` override). The GDI32/
  USER32 import libs are still linked because the reachable `std_gfx` cell
  surface is compiled into the image even in memory mode; the *subsystem* is
  the console default.
- Both entries get an explicit `-fsafe -W` (warnings-as-errors) dump before the
  cross build; `cross_nocrt.sh` handles the actual dump + no-CRT link.
- `tests/fixtures/sample.txt` is copied beside both exes. `probe_out.txt`
  receives the fixture bytes verbatim (25 bytes:
  `UNDERSANDED M1 sample OK\n`).

Trap handler wiring (spec §33): `debug.setTrapHandler(onTrap)` is installed
after the writable dir is resolved. `onTrap` only uses pre-allocated state:
the `crash.dmp`/`crash.log` path strings are built at startup, the backtrace
`Buf` is `std_buf.initCapacity`-backed by a fixed 64 KiB arena (4 KiB capacity,
1024 frames), and the handler does no allocation or path resolution.
`crash.dmp` uses `std_debug.writeCoreDump`; `crash.log` uses
`std_debug.backtrace`; the handler then prints one line via `@stderrWrite`.
`data.z98` is not created: M1 uses `sample.txt` only (Task 6 vs M6 ruling).

Import gate: `under.exe` and `undtool.exe` both pass
`check_win9x_imports.sh <exe> 9x` with exactly GDI32/KERNEL32/USER32; no
allow-list change was needed in this task.

## Task 7 acceptance tier

`tests/tier_m1_std.sh` (POSIX sh; `ZIG`/`OUT` env, paths resolved from the
script) is split into a FAST gate and SLOW Wine/operator evidence.

FAST (the gate):

- `build.sh` builds both no-CRT Win9x exes; both `-fsafe -W` logs must exist
  and contain no `warning` text.
- `check_win9x_imports.sh <exe> 9x` on both `under.exe` and `undtool.exe`.
- Native Linux driver: `tests/paths_test.zig` via `zig1 -osl` +
  `build_target.sh linux`; it must exit 0 and print `paths_test PASS`, with the
  crc32/8.3/path-join/writability/fallback cases green. Task 7 added test-only
  `std_parse.parseInt`/`std_parse.itoa` reuse cases (`std_parse_parseInt_reuse`,
  `std_parse_itoa_reuse`) — G17 stays closed by reuse; no std twins were added.
- `scripts/stdlib/run_fixtures.sh` for `stdlib_str_splitonce_xmod` and
  `stdlib_crypto_crc32_xmod` (2 PASS / 0 FAIL).
- `z9edit/tests/tier_edit.sh` green (38 cases) with its lexer md5 line
  byte-identical 3x and unchanged from the M1 baseline
  `dcc81009e9a36c86e4d90e104c439871`.
- `git ls-files examples/z98/undersanded` must contain no `.py` tooling.

SLOW evidence (Wine; not a Win98 hardware claim):

- `undtool.exe` in a writable temp workdir exits 0 and writes `probe_out.txt`
  with exactly the `sample.txt` bytes.
- `undtool.exe` in a `chmod 0555` copy directory exits 0: the read-only exe dir
  gains no file, stdout reports `(read-only)` and
  `writable_dir=C:\WINDOWS\TEMP\UNDERSAN\`, and the fallback output is recorded
  at `<wineprefix>/drive_c/windows/temp/UNDERSAN/probe_out.txt` (bytes match
  the sample).
- `under.exe` runs under Xvfb + Wine: `xwininfo -root -tree` sees a window
  titled `UNDERSANDED`, the process exits 0, a root screenshot is recorded, and
  the windowed run also writes a matching `probe_out.txt`.

Each executed slow check prints an `EVIDENCE` line; a failure prints
`EVIDENCE-FAIL` and makes the tier exit nonzero. Missing wine/Xvfb prints
explicit `operator-hardware:` lines (never a silent skip) and is counted as an
evidence skip. The summary is `TIER_M1 PASS` / `TIER_M1 FAIL` with
pass/fail/skip counts. The std set must be synced to the compiler's `lib/`
first (`cp sf/src/std_*.zig /tmp/zig1-m1/lib/`).

## Post-gate follow-up (Task 0.3)

- Trap backtrace frame cap: `std_debug.backtraceLimited` stops after
  `max_frames`; `app.zig` calls it with `1024`, so the handler cannot grow past
  its pre-allocated 4 KiB backtrace budget. `backtrace` remains an unbounded
  wrapper (behavior unchanged) for the blueprint §3 L1 signature.
- `pathJoin83` rejects joined paths of 260+ bytes (Win98 `MAX_PATH`) as `null`,
  in addition to the existing `out.len` bound.
- Accepted evidence-only items (no code change): the Wine/Xvfb `under.exe` root
  screenshot is black (captured outside the presented DDraw surface), and
  missing Wine/Xvfb is counted as an evidence skip via the explicit
  `operator-hardware:` lines rather than a failure.

## M2 amendment review: no amendment needed

Checked the M2 plan's consumed surfaces against M1 actuals (code at
`8b65795d`) and spec §23/§24/§25 (G12 plan/spec amendment `bbc4cd27`):

- **`game.zig` purity:** M2 authors `game.zig` with no I/O; none of the M2
  game modules (`def`/`math`/`rng`/`behavior`/`fight`/`game`) need
  `std_file`/`std_io`/`std_gfx`. M1 adds no dependency that forces I/O.
- **RNG:** xorshift32 is game-owned per spec §25.5 (shifts/XOR only, no
  multiply). `sf/src/std_rand.zig` exists (PCG32 + xoshiro256**) but is
  unusable here — spec §25.5/R7 mandates game-owned xorshift32; M1 adds no
  conflicting surface.
- **Fixed point / i32 math:** `applyPct`, integer ceil, and i32-only combat
  math are self-contained in M2's `math.zig`. G12 is CLOSED-ALREADY by reuse:
  `std_math` provides `min`:1, `max`:6, `abs`:21, `clamp`:26 (plus unsigned
  variants). M2 Task 2 and spec §23 G12 were amended in `bbc4cd27` to reuse
  these — no game-side copies.
- **Flat structs/capacities:** spec §25.1–§25.3 sizes (`MAX_LOG=64`, etc.) are
  authored in M2 Task 1 (`def.zig`); M1 fixed no contradicting values and
  mandates no resize.
- **`GameState`/`LogEntry`/`FightState`:** authored in M2 Task 1
  (state/`def.zig`) from spec §25.3. **`Effect`** is authored in M2 Task 1
  (`def.zig`). No std/platform surface required.
- **std APIs M2 calls:** `std_gfx` cell tier is present — `gfxOpen`:107,
  `gfxOpenMemory`:128, `gfxWaitEvent`:197, `gfxPollEvent`:163,
  `Event.px/py`:49–50, `focus_lost`/`focus_gained`:39–40, `gfxTestKey`:236,
  `gfxTestMouse`:244, `gfxBeginFrame`:258, `gfxDrawText`:305,
  `gfxDumpGrid`:348. `std_io` has `write`:5, `printInt`:19, `readByte`:54.
  The `gfxWaitEvent` import amendment (`MsgWaitForMultipleObjectsEx`) is in
  this NOTES and the import gate.
- **Plumbing:** `under.exe` (GUI) + `undtool.exe` (CUI) no-CRT links, import
  gate, and the native Linux test-driver convention are green in M1.

Verdict: **no amendment needed** for M2.

## M2 preflight

- Compiler: `/tmp/zig1-m1/zig1_5_clean`, md5 `73c75a65e30dfd212fdf93ae1e57a687`,
  seed **v149**. Harness rule after std edits: run
  `cp sf/src/std_*.zig /tmp/zig1-m1/lib/` before the tier.
- Controller resolution: the brief's "3-creature stat rows" means all **five**
  rows its sentence lists (3 commons + 2 flex rares). No `creatures_t1.zig`
  exists yet; it is authored at Task 4. Task 0 only validates/records these
  five rows and their behaviors — no fight code is implemented here.
- Stat rows verbatim from spec §14.2:

  | # | Creature | Family | Role | Zones | Phase | HP | Res | Spd | Atk | Subdue | Sale | Respawn |
  | :-- | :--- | :--- | :--- | :--- | :--- | --: | --: | --: | --: | --: | --: | :--- |
  | 1 | Mystic Eel | Eel | common | Z1,Z2 | both | 70 | 80 | 10 | 6 | 95 | 20 | 3/9/15 |
  | 2 | Mystic Electric Eel | Eel | common | Z1,Z2 | night | 80 | 100 | 16 | 7 | 95 | 30 | 3/9/15 |
  | 4 | Steel Tuna | Tuna | common | Z1,Z2 | both | 120 | 70 | 6 | 8 | 95 | 20 | 3/9/15 |
  | 18 | Anemoniacus *(flex)* | Anemone | rare | Z2 | both | 95 | 115 | 7 | 9 | 60 | 50 | 6/18/30 |
  | 19 | Freezing Perch *(flex)* | Perch | rare | Z3 | both | 105 | 95 | 13 | 10 | 60 | 55 | 6/18/30 |

- Behaviors verbatim from spec §14.3:
  - Mystic Eel — Despair override **+8**. Tutorial creature, learnable bare.
  - Mystic Electric Eel — Thrash override **+8**. **Discharge:** one-shot 8 Hull
    when Resolve crosses below 50%.
  - Steel Tuna — **Armor:** Strike 60% unless Plate. HP<30% → Speed +4.
  - Anemoniacus — Thrash override **+10**. **Discharge:** one-shot 10 Hull when
    HP crosses below 50%.
  - Freezing Perch — Despair override **+8**. **Flees next turn if a single hit
    deals >35% max HP (37).**
- Ruling (§9.1, D10): commons auto-roll silently; rare/named use the subdue
  modal (`SUBDUE_PROMPT_BELOW = 90`).
- Baseline tiers observed from this worktree:
  - `tier_edit.sh` → `TIER_EDIT PASS`, 38 passed / 0 failed; lexer md5
    `dcc81009e9a36c86e4d90e104c439871` (3x); compile max RSS 5916 KiB.
  - `tier_m1_std.sh` → `TIER_M1 PASS`, 37 passed / 0 failed / 0 evidence skips.

## Rule op mapping (frozen for M6/M8 data authoring)

The numeric op values in `behavior.zig` are frozen. M6/M8 `[rules]` rows must
author exactly these numbers; `behavior_test.zig` pins every literal.

Condition ops (`Rule.cond_op`):

| Name | Value |
| :--- | --: |
| `HP_BELOW` | 1 |
| `RES_BELOW` | 2 |
| `ROUND_MOD` | 3 |
| `FIRST_ROUND` | 4 |
| `ALWAYS` | 5 |

Effect ops (`Rule.effect_op`, also `Effect.op` in `def.zig`):

| Name | Value |
| :--- | --: |
| `REGEN_RES` | 1 |
| `REGEN_HP` | 2 |
| `HULL_DMG` | 3 |
| `SET_ARMOR` | 4 |
| `SET_FLEE` | 5 |
| `SET_BLIND` | 6 |
| `SET_INK` | 7 |
| `ADD_SPEED` | 8 |
| `MULT_ATK` | 9 |
| `MISS_STRIKE` | 10 |

Timing (`Rule.timing`): `TIMING_ONESHOT = 0`, `TIMING_PERSISTENT = 1`.

Condition semantics (frozen):

- Round base is **1** (the first round is `round == 1`); `FIRST_ROUND_NUM = 1`.
- `HP_BELOW` holds when `now_hp < cond_a`.
- `RES_BELOW` holds when `now_res < cond_a`.
- `ROUND_MOD` holds when `round % cond_a == cond_b`; `cond_a == 0` → false
  (never divides, so no `-fsafe` trap).
- `FIRST_ROUND` holds when `round == FIRST_ROUND_NUM` (i.e. `round == 1`).
- `ALWAYS` holds unconditionally.
- Threshold one-shot crossing: fire when `prev >= cond_a && now < cond_a`
  (exactly at the threshold counts as not-yet-crossed).
- Non-threshold one-shot (`ROUND_MOD`, `FIRST_ROUND`, `ALWAYS`): `crossed` is
  the condition itself, so the row fires on the first evaluation where it
  holds; the consumed bit prevents any later fire.
- Persistent rows report their effect on every evaluation while the condition
  holds. Unknown condition/effect/timing values are a no-op.

## Percent-threshold convention (M6/M8 data authors)

"Below X%" / "above X%" is the **exact-rational** comparison, never
floor-then-strict-`<`:

- below: `v * 100 < max * pct`
- above: `v * 100 > max * pct`
- single-hit "exceeds X% max HP": `damage * 100 > max_hp * pct` (strict `>`)

Consequences for non-100-divisible maxima: max_res 115 -> 50% boundary is
57.5, so `res = 57` is still below and `res = 58` is above; max_hp 95 -> 30%
boundary is 28.5, so `hp = 28` is below and `hp = 29` is not; max_hp 105 ->
35% is 36.75, so a 37-damage hit triggers the flee check and 36 does not.
This matches the frozen rule-row integer form (e.g. Anemoniacus
`HP_BELOW cond_a = 48` for 95 max HP), so `fight.zig`'s coupling gates,
`speed_below` / `armor_below` / `atk_below`, and `discharge_th` fields must
use the same form.
