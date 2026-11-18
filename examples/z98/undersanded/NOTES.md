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
  | 18 | Anemoniacus *(flex)* | Anemone | rare | Z2 | both | 95 | 80 | 7 | 9 | 65 | 50 | 6/18/30 |
  | 19 | Freezing Perch *(flex)* | Perch | rare | Z3 | both | 105 | 95 | 13 | 10 | 65 | 55 | 6/18/30 |

- Behaviors verbatim from spec §14.3:
  - Mystic Eel — Despair override **+8**. Tutorial creature, learnable bare.
  - Mystic Electric Eel — Thrash override **+8**. **Discharge:** one-shot 8 Hull
    when Resolve crosses below 50%.
  - Steel Tuna — **Armor:** Strike 60% unless Plate. HP<30% → Speed +4.
  - Anemoniacus — Thrash override **+10**. **Discharge:** one-shot 10 Hull when
    HP crosses below 50%.
  - Freezing Perch — Despair override **+8**. **Flees next turn if a single hit
    deals >20% max HP (21).**
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
boundary is 28.5, so `hp = 28` is below and `hp = 29` is not; the strict `>`
also excludes an exact boundary: max_hp 105 -> 20% is exactly 21, so a
21-damage hit does not trigger the Flee and 22 does.
This matches the frozen rule-row integer form (e.g. Anemoniacus
`HP_BELOW cond_a = 48` for 95 max HP), so `fight.zig`'s coupling gates,
`speed_below` / `armor_below` / `atk_below`, and `discharge_th` fields must
use the same form.

## M2 gate

`tests/tier_m2_fight.sh` is the M2 FAST/native gate (no Wine/DDraw evidence in
this tier). It builds and runs `core_test`, `behavior_test`, `fight_test`, and
`ui_test` with `-fsafe -W -osl` + `build_target.sh linux`, checks the scripted
full-fight goldens, the 20-fight evidence table, the purity rule
(`game.zig`/`fight.zig`/`behavior.zig` import no `std_gfx`/`std_io`), and the
z9edit `tier_edit.sh` regression with unchanged lexer goldens.

```
ZIG=/tmp/zig1-m1/zig1_5_clean OUT=/tmp/undersanded_m2_tier \
  sh examples/z98/undersanded/tests/tier_m2_fight.sh
TIER_M2 PASS 29 passed / 0 failed
```

Native driver case counts: `core_test` 12, `behavior_test` 25, `fight_test` 41,
`ui_test` 17. `fight_test` pins the exact full log bytes (`class:msg_id:a:b;`
per entry) for four scripted fights: fight 1 (Subdue), fight 2 (Kill), fight 3
(Overkill), and fight 4 (rare modal). All use the fixed seed 98.

### 20 scripted fights (fixed seed 98, varied action streams)

The gate wording "20 manual fights played" is reproduced mechanically as these
20 deterministic scripted fights (the same runs are asserted in
`fight_test.zig`'s `scripted_20_fight_table`). Actions: `S` Strike, `R`
Restrain, `E` Equipment (no tool), `P` Equipment with Plate (tool arg 1), `F`
Flee, `A` Attempt at a modal. "(cycled)" means the stream repeats until the
fight ends; `A` is supplied at each rare modal unless "declined" is noted.
`Hull` is the player Hull left; `notable` is drawn from the same run's log.

| # | Creature | Outcome | Actions (stream) | Steps | Hull | Notable behavior |
| --: | :--- | :--- | :--- | --: | --: | :--- |
| 1 | Mystic Eel | SUBDUE | `R×8` | 8 | 58 | Common silent auto-roll; Thrash coupling (`msg 9`, +5 Resolve) fired 5×, forcing the extra Restrains; no parting hit on success. |
| 2 | Steel Tuna | KILL | `S×12` | 12 | 12 | 60% armor chipped every Strike; Despair coupling regenerated HP 5×; HP<30% Speed 6→10 still only ties the player; overshoot 3 < margin 12 → Kill, not Overkill. |
| 3 | Mystic Eel | OVERKILL | `S×4` | 4 | 82 | One Despair coupling tick; overshoot 8 ≥ margin 7; creature acted in every live round. |
| 4 | Anemoniacus | SUBDUE | `R` cycled + `A` at modal | 15 | 0 | Rare modal path: 14 Restrains then one successful Attempt; 11 Thrash coupling ticks (+10 Resolve); no failed Attempt/Last Surge; Hull drained to 0; no discharge. |
| 5 | Freezing Perch | CREATURE_FLED | `SRSR` cycled | 6 | 50 | 4 bar switches; the last Strike (24) exceeded 21, so the Perch fled next turn. |
| 6 | Mystic Electric Eel | OVERKILL | `RSRSRSRS` cycled | 8 | 36 | Discharge fired once (8 Hull) when Resolve crossed below 50%; 7 switches, 1 coupling tick; overshoot 8 ≥ margin 8. |
| 7 | Steel Tuna | SUBDUE | `R×10` | 7 | 52 | Restrain-only path; 4 Thrash coupling ticks (+5 Resolve); armor irrelevant to Resolve; silent 95% roll. |
| 8 | Mystic Electric Eel | SUBDUE | `R×12` | 13 | 1 | Speed 16 acted first each round; 9 Thrash ticks; one discharge tick; subdue at Hull 1. |
| 9 | Freezing Perch | SUBDUE | `R×12` | 10 | 10 | Rare modal path, first Attempt succeeded; 5 Thrash ticks; no discharge/surge. |
| 10 | Anemoniacus | KILL | `SRSRSR` cycled | 9 | 18 | No modal opened in this row (killed before Resolve reached 0, `modal=no declines=0`); 8 switches, 1 coupling tick; one discharge (10 Hull) on the HP<50% crossing; overshoot 2 < margin 9 → Kill, not Overkill. |
| 11 | Steel Tuna | KILL | `P` then `S×12` | 7 | 52 | Plate spent one action to negate the 60% armor; the same Strike stream killed in 7 actions instead of 12 (fight 2), with only 2 coupling ticks. Overshoot 1 < margin 12. |
| 12 | Mystic Eel | OVERKILL | `E` then `S×4` | 5 | 76 | Bare Equipment (no tool) only bought a free creature hit; 1 coupling tick; overshoot 8 ≥ margin 7. |
| 13 | Mystic Eel | PLAYER_FLED | `F` | 1 | 100 | Player flee ends the fight immediately, no creature action. |
| 14 | Freezing Perch | CREATURE_FLED | `S×10` | 3 | 80 | Second Strike (24) exceeded 21, so the Perch fled next turn. |
| 15 | Anemoniacus | OVERKILL | `S×10` | 5 | 54 | One discharge tick (10 Hull) on HP<50%; 1 coupling tick; overshoot 10 ≥ margin 9. |
| 16 | Mystic Electric Eel | KILL | `S×12` | 4 | 72 | Speed 16 hit first each round; 1 coupling tick; overshoot 1 < margin 8; Resolve untouched so no discharge. |
| 17 | Steel Tuna | SUBDUE | `RRSRRSRRSRRS` cycled | 11 | 20 | 6 bar switches, 7 coupling ticks; Thrash pulled Resolve back up (`msg 9`, +5) before the silent subdue. |
| 18 | Mystic Eel | SUBDUE | `RRSRRS` cycled | 10 | 46 | 6 bar switches, 2 coupling ticks; mixed stream still closes both gates for a 95% subdue. |
| 19 | Freezing Perch | CREATURE_FLED | `RRSSRRSS` cycled | 5 | 60 | 1 bar switch; second Strike (25) exceeded 21, so the Perch fled next turn. |
| 20 | Anemoniacus | OVERKILL | `RRRRS` cycled, modal declined | 26 | 0 | Rare modal genuinely opened at Resolve 0 and was declined (`modal=yes declines=1`, no RNG); after declining the gate never re-opens; 9 switches, 6 coupling ticks, one discharge; overshoot 9 ≥ margin 9. |

Playable-path evidence (already captured in the Task 4 report from the real
console path under Wine): `undtool.exe` transcripts completed SUBDUE in 8
actions (fight 1), KILL in 12 (fight 2), OVERKILL in 4 (fight 3), and the rare
modal SUBDUE in 15 (fight 4). Those interactive transcripts are the playable
path; the table above is the deterministic, machine-checked equivalent.

### §41 three questions

1. **Does the creature's behavior make me switch which bar I push, mid-fight?**
   **Yes.** The coupling gates invert the bars: Strike pushes HP toward the red
   zone and opens Despair (HP<30%, Res>50%), which regenerates HP, so you switch
   to Restrain to drag Resolve below 50% and close it (fight 2: an all-Strike
   run got 5 Despair HP ticks; fight 14 all-Strike and fight 19 mixed
   `RRSSRRSS`: 2 each). Restrain pushes
   Resolve down and opens Thrash (Res<50%, HP>50%), which regenerates Resolve,
   so you switch back to Strike (fight 1: 5 Thrash ticks in an all-Restrain
   run; fight 4: 11 ticks; fights 7/8/9: 4/9/5 ticks). The discharge rows add a
   second forced switch: repeating one bar through a threshold crossing costs
   8–10 Hull (fights 6, 8, 10, 15, 20).
2. **Does the equipment slot change how I fight, or is it just a damage bonus?**
   **Yes — it changes how I fight.** A Plate action spent a turn to negate
   Steel Tuna's 60% armor, after which the same Strike stream killed in 7
   actions instead of 12 (fight 11 vs fight 2): the slot changes the action
   plan (commit a tempo turn, then full Strikes), not just a passive number.
   Conversely a bare Equipment action with no tool is only a wasted tempo turn
   (fight 12: the creature got a free hit), so the slot is a real
   action-economy decision.
3. **Does Speed feel like a trade-off, or a dominant stat?**
   **Yes — a trade-off, not dominant.** Speed only decides who acts first, and
   ties go to the player: Steel Tuna's HP<30% +4 Speed (6→10) only ties the
   player, so it never steals the first action (fight 2). Fast creatures
   (Mystic Electric Eel 16, Freezing Perch 13) hit before your action and tax
   Hull — MEE subdue ended at Hull 1 (fight 8), and the mixed Perch/MEE runs
   lost Hull before the finisher (fights 5, 6, 16) — while slow Mystic Eel and
   Steel Tuna let you finish cleanly (fights 1, 3, 7). No single Speed value
   dominates: slow creatures still have coupling/armor that forces switches.

All three answers are **yes**; the M2 fight is cleared for M3 without a
stop-present.

## M2 known issues / provisional

- **Post-gate hardening:** `defAt` panics on invalid index, `rngRange` panics on `hi < lo`, the 20-fight table pins `declines`, and Wine `undtool.exe` runs get `</dev/null`.
- **Plate/Brine-Net model is PROVISIONAL.** Spec §10 marks both as Rigged
  (passive, no charge), while M2 honours them only when `tool_active != 0`
  (activated). §41 Q2's answer must be re-validated at M5 with rigged
  semantics.

## M2 → M3 amendment review

Read `2026-11-12-undersanded-m03-sim-replay-plan.md` against the committed M2
surface. Verdict: **no amendment needed**. Every M3-consumed surface is public
and headless, and the M2 gate already drives all five creatures through
`game.startFight`/`game.gameStep`.

- **Full action stream incl. A/D.** `def.Action{kind,arg}` with
  `ACT_STRIKE`…`ACT_DECLINE` (`ACT_ATTEMPT=5`, `ACT_DECLINE=6`,
  `def.zig:105–112`); `game.gameStep` dispatches all six (`game.zig:68–76`), and
  `fight.step` resolves A/D in the rare modal (`fight.zig:511–537`).
  `input.mapKey` already sends A → Attempt and F/Esc → Decline
  (`input.zig:32–37`), so the replay recorder consumes the same Action stream.
- **Deterministic RNG state visibility.** `FightState.rng_state: u32` is public
  (`def.zig:59`); per-fight seeding is `exp.seed + fight_index*77` plus three
  warm-up draws (`fight.zig:155–158`, `rng.zig:32–38`). Decline consumes no
  draws (`fight.zig:526–537`; test `decline_no_rng_gate_refire`).
- **Headless driving.** Pure
  `startFight(s: *GameState, def_index: i32)` and
  `gameStep(s: *GameState, a: Action)` (`game.zig:53`, `:68`); no I/O in
  `game`/`fight` (tier purity check).
- **Log for replay goldens.** Stable `LogEntry{class,msg_id,a,b}` (`def.zig:84`)
  in `GameState.log[64]` + `log_n` (`def.zig:96–97`), drop-oldest
  (`fight.zig:80–91`). M2 already pins exact `class:msg_id:a:b;` bytes
  (`scripted_golden_{subdue,kill,overkill,rare_modal}_bytes`).
- **Five-creature roster.** `creatures.DEFS[5]` + `defAt(0..4)`
  (`creatures_t1.zig:193–210`): Mystic Eel, Mystic Electric Eel, Steel Tuna,
  Anemoniacus (rare), Freezing Perch (rare); `role`/`ROLE_RARE`
  (`creatures_t1.zig:13`) and `F_SHELL` (`def.zig:135`) are public for the
  §25.9 policy. Caveat: no M2 creature sets `F_SHELL` (all `flags=0`), so the
  §25.9 Kill/Shell path cannot be exercised by the five-creature gate — M3
  needs a synthetic shell fixture.
- **Evidence:** `TIER_M2 PASS 29 passed / 0 failed`; `fight_test` prints 20
  headless `FIGHT` rows covering all five creatures, modal Attempt (e.g. fight
  4) and a real modal Decline (fight 20).
- **M3 implementation notes (not M2 amendments).** `game.startFight` hardcodes
  the M2 stream at seed 98 / fight 0 (`game.zig:11–13`); M3's
  `runSim(seed0)` can vary seeds through public state
  (`rng.rngSeed(&s.fight.rng_state, seed0 + i*77)`, or pre-fill `s.exp` and
  call public `fight.startFightDef`). M2 has no `OUT_ASCENT` (Hull-0
  termination is M4), so M3 must report Emergency Ascent rate as the fights
  where `FightState.hull` reaches 0 — the plan's Review Focus already requires
  pinning that metric definition.
- **Average actions must count steps, not `FightState.actions`.** That field
  increments only for Strike/Restrain/Equip (`fight.zig:445–460`); Attempt,
  Decline and Flee do not count. M3's "avg player actions" must count
  `gameStep` calls/steps or rare-modal fights are undercounted.
- **M3 lever 2 is wired.** `LAST_SURGE_RESTORE_PCT` (`fight.zig:37`) drives
  `lastSurge` through `math.ceilPct(max_res, LAST_SURGE_RESTORE_PCT)`
  (`fight.zig:350`); the previous 30% default was bit-identical to the old
  `ceilPct30`, and the M3 lever sets it to 25.
- **Replay headers (`tool=`, `zone=`, `phase=`).** M2 exposes `FightState.tool`
  and the tool constants; M3 can set/record these through public state. Sonar
  itself is later content, not an M3 surface requirement.
- **`--creature <id>` mapping.** Strings (e.g. `perch`) map to def indices in
  M3 tooling; defs carry numeric `id` only. Roadmap note (not verified from M2
  code): display names exist in `render_term.creatureName`; content naming is
  later-milestone work.

## M3 preflight

- Compiler: `/tmp/zig1-m1/zig1_5_clean`, md5
  `73c75a65e30dfd212fdf93ae1e57a687` (seed v149, unchanged from M1/M2).
  Harness rule after std edits still applies: sync the std set to the
  compiler's `lib/` first (`cp sf/src/std_*.zig /tmp/zig1-m1/lib/`).
- M2 tier baseline from this worktree (the hand-played §41 log the sim must
  corroborate; see "§41 three questions" above):

  ```
  ZIG=/tmp/zig1-m1/zig1_5_clean OUT=/tmp/m3_t0/m2_baseline \
    sh examples/z98/undersanded/tests/tier_m2_fight.sh
  TIER_M2 PASS 29 passed / 0 failed
  ```

  Native driver case counts observed: `core_test` 12, `behavior_test` 25,
  `fight_test` 39, `ui_test` 17; `fight_test` prints 20 `FIGHT` rows. z9edit
  `tier_edit.sh` green (38 passed / 0 failed) with lexer md5
  `dcc81009e9a36c86e4d90e104c439871` byte-identical 3x; compile max RSS
  5888 KiB.
- M3 gate premises (pinned; Task 2's report header must print
  `actions=gameStep_steps ascent=hull0 bars=fights_with_switch`):
  - **Loadout:** all gate metrics at **Hull 150** (two T1 Hull upgrades; real boat state is M4). Rare-fight actions reported per-mille (`rare_actions_pm`).
  - **Actions:** player actions = `gameStep` calls/steps (NOT
    `FightState.actions`, which excludes Attempt/Decline/Flee).
  - **Ascent:** Emergency Ascent = `FightState.hull` reached 0; M2 clamps at 0
    and does not terminate, so the sim stops that fight and counts it. Real
    Hull-0 termination is M4.
  - **Bar-switch:** fights with `FightState.switches > 0` over total fights.
  - **Prompt:** a modal-required gate, i.e. `gateOpen` true with
    `subdue_chance < SUBDUE_PROMPT_BELOW` (commons 95 -> 0, so commons never
    prompt).
  - **Freezing Perch flee is reachable:** fights may end `CREATURE_FLED`; the
    sim must count that outcome rather than treating it as an error.
  - **Shell policy fixture:** no M2 def sets `F_SHELL`, so the §25.9 Kill/Shell
    path uses a synthetic `F_SHELL` test fixture in `sim_test`/`ruletest`
    (never added to `DEFS[5]`).
  - **Replay `creature` token table** (spec §28 Player Interaction): `eel` = Mystic Eel,
    `electric_eel` = Mystic Electric Eel, `steel_tuna` = Steel Tuna,
    `anemoniacus` = Anemoniacus, `freezing_perch` = Freezing Perch
    (`eel|electric_eel|steel_tuna|anemoniacus|freezing_perch`).

## M3 gate (final)

`tests/tier_m3_sim.sh` is the M3 FAST/native gate. Run at the gate loadout
(`--sim 200 --seed 98 --hull 150`) it reports **65 passed / 0 failed / 1
evidence skip**: `TIER_M3 PASS 65 passed / 0 failed` (the skip is the SLOW
Wine `undtool.exe` evidence section: no built exe / wine in the native-only
worktree; it is non-gating by design).

- **W1 deferred-fix re-pin:** decline logs the plain copy
  (`MSG_DECLINE_PLAIN`, "The creature recovers its footing.") unless Thrash is
  live (`MSG_DECLINE` keeps the recovering-will wording; Despair-active declines
  also use the plain copy); the `--dump-grid` golden was re-pinned for the
  pinned `DUMP_SEED=98`; rare actions report per-mille (`rare_actions_pm`). No
  assertion was weakened.
- **W1 decline copy:** `MSG_DECLINE` ("will begins to recover") is logged only
  when Thrash is live; otherwise `MSG_DECLINE_PLAIN` (spec §9.3).

| Creature | token | rare_actions_pm | ascent % | switches % | prompts |
| :--- | :--- | ---: | ---: | ---: | ---: |
| Mystic Eel | `eel` | 0 | 0.0 | 100 | 0 |
| Mystic Electric Eel | `electric_eel` | 0 | 0.0 | 100 | 0 |
| Steel Tuna | `steel_tuna` | 0 | 0.0 | 100 | 0 |
| Anemoniacus | `anemoniacus` | 11525 | 4.0 | 100 | 292 |
| Freezing Perch | `freezing_perch` | 5385 | 1.5 | 25 | 73 |

- Rare pm gate `rare_actions_pm ≤ 12000` applies to the two rares: PASS
  (Anemoniacus 11525pm, Freezing Perch 5385pm); commons print 0 and are not
  gate subjects.
- Ascent rate `≤15%` at Hull 150 (`ascent_pm ≤ 150`): PASS (Anemoniacus 40pm,
  Freezing Perch 15pm; commons 0pm).
- Bar-switch `>0`: PASS (100% on eel/electric_eel/steel_tuna/anemoniacus, 25%
  on freezing_perch). Commons prompts `=0`: PASS. Exact report header
  `defs actions=steps ascent=hull0 bars=switches prompt=modal`: PASS.
  Fixed-seed determinism (identical output run twice): PASS.
- `--test-rules` exit 0 with `rules_ok=100`: PASS. `--replay <fixture>` exact
  pinned line: PASS (`replay_eel_98.rep`). `--dump-grid --screen fight`
  byte-identical to `dump_grid_fight.golden`: PASS. Replay v2 writer artifact
  byte-identical to `replay_eel_98.rep`: PASS.
- Unit drivers: `replay_test` 4/4, `sim_test` 8/8, `ruletest_test`
  (`rules_ok=100`), `safety_test` 5/5 (incl. decline-no-RNG,
  commons-never-prompt, surge caps), `replay_cli_test` 3/3.
- Prior gates: `tier_m1_std.sh` `TIER_M1 PASS` (37 passed / 0 failed / 0
  evidence skips); `tier_m2_fight.sh` `TIER_M2 PASS 29 passed / 0 failed`
  (core 12, behavior 25, fight 41, ui 17); z9edit `tier_edit.sh` 38/0 with
  lexer md5 `dcc81009e9a36c86e4d90e104c439871` byte-identical 3x.

### Lever trace + content rebalance (user-authorized)


- **Lever 1:** both flex rares' `subdue_chance` 60→65 (Anemoniacus and
  Freezing Perch). **Lever 2:** `LAST_SURGE_RESTORE_PCT` 30→25
  (`res = (max_res*25 + 99)/100`, integer ceil).
- **Rebalance:** Anemoniacus Resolve 115→80 in `creatures_t1.zig` (HP 95,
  Thrash +10, Discharge 10 Hull unchanged). Required for the
  ≤12 rare-actions gate and is recorded as spec
  §38 P21 under the user's “go 1, yes lets rebalance” authorization. No other
  creature or coupling constant was changed; the ascent-gate loadout is Hull 150.
- **Ascent gate loadout:** measured at **Hull 150** (two T1 Hull upgrades).
  Seed 98: Anemoniacus 4.0%, Freezing Perch 1.5%. Cross-seed worst:
  Anemoniacus **8.5% (85 pm, seed 4)**, Freezing Perch **5.0% (50 pm, seed
  59)**. Recorded, not tuned.

### M3 -> M4 amendment review (Task 6)

Read `2026-11-12-undersanded-m04-expedition-loop-plan.md` against the
shipped M3 sim surfaces. Verdict: **no amendment needed** — the M3 report is
per-creature fight metrics with no World/availability/rare-pipeline input, so
M4's World and encounter work is validated by M4's own `world_test`/
`encounter_test` (M4 plan Tasks 1–2) without a per-zone report shape.

- **Hull-0 is not an outcome.** `fight.zig` clamps `hull` at 0
  (`fight.zig:314-315`, `:500-502`) and `def.OUT_*` has no ascent value
  (`def.zig:114-119`); `sim.zig:135-138` stops the loop at `hull == 0` and
  counts `ascents` (`sim.zig:147-148`). M4 owns termination, the +1 phase and
  dropping current-fight loot (spec §6); do not expect the fight resolver to
  end the fight at Hull 0.
- **Seed convention.** `fight.startFightDef` seeds each fight from
  `exp.seed + fight_index*77` with three warm-up draws (`rng.zig:33-40`;
  spec:1173,1186). M4 `depart` must draw `exp.seed` from `world.rng_state`
  (M4 plan:56; spec:1186) and set `exp.fight_index` per fight; the sim bypasses
  Depart and sets `exp.seed = seed0`, `exp.fight_index = i` directly
  (`sim.zig:117-118`).
- **`--hull` is sim-only.** `undtool` defaults Hull to 100 and overrides it per
  sim fight (`undtool.zig:248`, `:310-323`; `sim.zig:120-121`); the gate uses
  150 (spec:1249). M4's real Hull is persistent fight/boat state (spec §6,
  spec:1249), not the tool flag.
- **Dense `DEFS` index vs `id`.** `creatures.DEFS` is a 5-element array indexed
  0..4 (`creatures_t1.zig:193-199`; `undtool.zig:28-34`), while
  `CreatureDef.id` is 1/2/4/18/19 (`creatures_t1.zig:81,101,126,149,174`).
  `World.ready` is `zone*MAX_CREATURES + def_index` (spec:1229); M4 must pin
  `def_index` to the dense array index (converting ids in tables), not index
  `ready[]` by `id`.
- **Zone/phase masks are not populated.** All five shipped rows leave
  `zone_mask` and `phase_mask` at 0 (`creatures_t1.zig:24-25`; constructors
  never write them). M4's `tables_t1.zig` must carry the per-zone/per-phase
  pools itself (M4 plan:26,51), or M4 must fill the masks; availability cannot
  be derived from the current `DEFS` as shipped.
- **Only five creature rows exist.** `DEFS` has Mystic Eel, Mystic Electric
  Eel, Steel Tuna, Anemoniacus, Freezing Perch (`creatures_t1.zig:193-199`),
  but spec §13 Z1–Z3 names additional creatures (Rust Tuna, Kelp Crab, Spark
  Anemone, …; spec:536-578) with no defs yet. M4 implements the Z1–Z3 tables
  itself (M4 plan:51 stubs Z4–Z8/D); the real gap is that those Z1–Z3 tables
  name creatures whose `CreatureDef` rows do not exist until M8.
- **M3 report shape is independent.** `SimReport` aggregates one `CreatureDef`
  (`sim.zig:35-48`, `:102-162`), the §25.9 policy reads fight state plus
  `cdef.flags`/`cdef.subdue_chance` (`sim.zig:81-97`, `:131`) but no World
  input; the header/`sim creature=` line are tooling output
  (`undtool.zig:67-90`, `:400-401`). Availability, rare-chance arithmetic,
  renormalization and empty-pool Rest belong to M4 unit tests; per-zone sim
  runs would only re-partition the same fight metrics.
- **R8 note.** The sim is safe with `var s: GameState = undefined` because
  `fight.startFightDef` reads only the seed fields of `exp` and never touches
  `world` (`sim.zig:115-119`; `fight.zig:115-158`); M4's World/expedition path
  must explicitly initialize `GameState.world` (R8, spec §24).

## M4 preflight

M3 gate confirmed green from this worktree before M4 work starts:

```
ZIG=/tmp/zig1-m1/zig1_5_clean OUT=/tmp/m4_t0/m3_gate \
  sh examples/z98/undersanded/tests/tier_m3_sim.sh
TIER_M3 PASS 65 passed / 0 failed / 1 evidence skips
```

The single skip is the SLOW Wine `undtool.exe` evidence section (no built exe /
wine in the native-only worktree); non-gating by design.

- **13 missing non-boss T1 defs are authored at M4 (DEFS 5→18):** Rust Tuna,
  Kelp Crab, Brine Jelly, Chitin Barnacle, Spark Anemone, Mileel, Tunisteel,
  Coral Crab, Abyssal Lantern-Jelly, Neon Ghost-Ray, Glass Squid, Brine Angler,
  Ironclad Wrasse. The boss row stays M11; M4 authors no boss def.
- **Boat tiers:** `boat[5]` stores tier counts 0–3 (0 = base). Derived tables:
  Hull 100/125/150/200, Speed 10/12/15/19, Cargo 0/1/2/3, Oxygen 3/4/5/6,
  Precision margin 10/15/20/25. Max fights = 3 + `boat[OXYGEN]`.
- **`World.hull` added** (base 100, persists across the expedition;
  `FightState.hull` is the per-fight copy). Dock Rest +40 clamps to the Hull
  table max.
- **Return leg = travel phases only** (no arrival action); outbound = 1 Depart
  phase + travel.
- **Grudge application = M5.** M4 sets/clears `family_overkill_mask` on
  overkill and applies wariness at fight start (+15 res/max_res, clear bit) via
  `consumeWariness`; release sets the wary bit.
- **Renewal semantics (spec §5/§14.2):** `ready = cycle + respawn[outcome]`
  used **verbatim** for subdue/kill/overkill — no multiplying. Creature-flee
  uses the subdue-length value; boss 20/40 is handled at M11.
- **Dormant M4 fields:** `F_PHASING`/`F_INK`/`F_DECOY`/`blind_chance` will be
  set at M4 but stay inert until M8 wires the fight logic. `--dump-grid
  --screen dock|map|node` is extended at M4.

### M4 resume amendments (2026-11-18)

- **Compiler seed v151** (`a2fc8105…`, `/tmp/seed151_build/zig1_5_clean`) is the
  compiler for the remaining M4 tasks; the v149 pin above is historical. Re-run
  the M4 drivers with v151 before dispatching.
- **Dock Rest is Task 4d** (spec §5): `restAtDock(g)` — +40 Hull clamped to
  `hullMax`, exactly 1 phase, no condition, no RNG. The earlier `restAtNode`
  path (+30) stays node-only; `expeditionStep` already returns early at dock.
- **Console nav is Task 4c:** pure `nav.zig` (`navStep` + `navRun`), nav-local
  screen ids, keys per the plan (dock `R/U/C/B/T/D/Q`; map `1–9`/`Esc`; node
  `H/R/S`; when a Subdue settlement is pending the node hint becomes
  `[R]elease  [S]ell`). `undtool --play` (gfx-free) and `undtool --fight` (M2
  chooser) are the two entry points; `app.runConsoleFight` runs nav.
  Enablers: `NO_FIGHT` moves to `def.zig`, `game.newGame`, `input.readKey` pub.
  `renderMap` gains a key-hint line (map golden regenerated); `renderNode`
  gains the conditional settlement line.
- **`MSG_SECURED` (Task 4b)** gets the static row text `"Secured."`; parts
  detail stays in `securedLine`.
- **D18 discipline:** no indexed writes through a nested struct field
  (`g.exp.hold[i]`, `g.world.ready[i]`, `g.world.boat[i]`) in nav/tests; use a
  `*Expedition`/`*World` pointer or a whole-struct literal.
- **Do not edit `examples/torrent_example_defects.md` in this worktree.** Its
  copy ends at D18; `zig1_start` now has D16–D23 (D22 OWC bare fn-ptr, D23
  MinGW 3.4.2 import casts), next free slot D24. None of D16–D23 blocks M4;
  D18 is the only one that touches game code.

### M5 amendment review (M4 Task 6)

Resolved at M5 kickoff (spec §38 **P22**): the M5 plan now owns `nav.zig`/`render_term.zig` dock dispatch, `World.materials`/`tools_owned`/`tool_selected`, persistent `Expedition.hold`, per-expedition tool state, the deep-refine 0-yield rule, the M8 split for blind/decoy/ink/phasing tool effects, and the real-E0 economy walk. M7's persisted-field list adds `materials` + the dock parts hold.

Verdict: **amendment required** — M5's dock UI/dispatch, refined-material
inventory, persistent craft parts, cosmetic-unlock gating, tool ownership, and
per-expedition tool charge are not covered by M4 or by the M5 plan's file list.

- **Dock action dispatch/messages are unowned.** M4 `dockStep` handles only
  `q/d/t`; `r/u/c/b` are deliberate no-ops (`nav.zig:63-69`) and `renderDock`
  prints `Refine, Upgrade, Craft, Buy: not yet (M5).` (`render_term.zig:422`).
  M5's Refine(material) / Upgrade(axis) / Craft(tool) / Buy(cosmetic) need key
  dispatch, selection sub-prompts, and result/refusal messages. Amend
  `2026-11-12-undersanded-m05-dock-economy-plan.md` File Structure and Task 2
  to add `nav.zig` + `render_term.zig` (with nav/screens test and golden
  updates); no M4 code change is needed because the stubs are intentional.
- **No persistent refined-material inventory.** M4 stores only loot parts in
  `Expedition.hold`, which is kept on return but zeroed at the next `depart`
  (`expedition.zig:299-305`), so M5 Refine output would vanish before the next
  dock use. Amend `examples/z98/undersanded/def.zig` §25.7 `World` with
  `materials: [MAX_MATERIALS]i32`, reset it in `game.zeroWorld`
  (`game.zig:16-53`), and consume it from M5 `economy.zig`/`dock.zig`. Add the
  field to the §25.7 layout row and the M5 plan File Structure/Task 2.
- **No persistent parts for Craft.** M5 Craft consumes parts (e.g. Sonar Ping
  = Glass Pane ×2 + Gland Sac ×1), but T1 tables never supply both in one
  expedition and `depart` zeroes `Expedition.hold` (`expedition.zig:299-305`).
  Amend the M5 plan File Structure/Task 2 to **stop zeroing `hold` at
  `depart`** (kept on return already, `expedition.zig:170-178`): the hold is
  already the §7 parts store, so this is simpler than a second inventory and
  needs no new World field. Adjust the M4 loop tests/goldens that assume a
  fresh hold.
- **Cosmetic gating reuses `World.cosmetics_unlocked`.** `World` already has
  `cosmetics_owned` / `cosmetics_unlocked: u32` (`def.zig:80`, persisted by
  M7); no new field is needed. Amend the M5 plan Task 2 to set the relevant
  `cosmetics_unlocked` bits on first arrival at Z1/Z2/Z3 (and boss-kill
  milestones) in the M5-owned depart/kill path, and consume that mask in Buy
  gating.
- **No persistent tool-ownership field.** M5 Task 2/3 craft owned-forever tools
  and equip one at depart, but `def.World` has no `tools_owned` (only
  `cosmetics_owned` / `cosmetics_unlocked`; `def.zig:80`) and nothing else
  persists ownership. Amend `examples/z98/undersanded/def.zig` §25.7 `World`
  with `tools_owned: u32` (7 tools fit `MAX_TOOLS=8`) and reset it in
  `game.zeroWorld` (`game.zig:16-53`); consume it from M5 `dock.zig`/
  `tools.zig`. Add the matching §25.7 layout row.
- **FightState tool/charge is fight-local, not per-expedition.**
  `startFightDef` zeroes `tool`, `tool_charge`, `tool_broken`, and
  `tool_active` on every fight (`fight.zig:136-139`), while M5 needs
  equip-at-depart, 1 activated charge per expedition, and broken clearing only
  at the next Depart. Amend the M5 plan File Structure (add `expedition.zig`)
  and Task 2/3 plus `def.Expedition` (or a documented World equivalent) to
  persist `tool`, `tool_charge`, and `tool_broken` across fights, initialized/
  cleared by the M5-owned `expedition.depart` hook (`expedition.zig:293-318`)
  and copied into `FightState` after `startFightDef` (as `hunt` already does
  for Hull/cond). `game.newGame` must clear them, and `game.startFight` also
  builds an `Expedition` literal (`game.zig:71-84`) so it must initialise any
  new fields too. M5 must own the `expedition.zig` depart hook rather than
  relying on the per-fight reset.
- **Save/load downstream.** `World.materials` (and the persistent parts store
  chosen above) must be on the M7 persisted-field list or refined materials
  vanish on save/load. Amend
  `2026-11-12-undersanded-m07-save-system-plan.md` Global Constraints and its
  Task 3 save-list bullets; M7 already lists expedition state + hold
  (`2026-11-12-undersanded-m07-save-system-plan.md:19,43`), so keep that hold
  entry if the hold is the chosen parts store.

- **Speed and Precision boat tables are dead.** The tier tables exist
  (`world.speedMax`, `world.precisionMargin`), but `fight.startFightDef`
  hardcodes `BASE_SPEED = 10` and `DEFAULT_MARGIN_PCT` (`fight.zig:125-126`)
  and `hunt` copies only Hull/cond into the fight (`expedition.zig`).
  M5 must copy `world.speedMax(&g.world)` and
  `world.precisionMargin(&g.world)` into `FightState.player_speed` /
  `margin_pct` at fight start; this is M5-owned, not an M4 change.
- **Five M2-era defs have blank §14.4 drop tables.** Mystic Eel, Mystic
  Electric Eel, Steel Tuna, Anemoniacus, and Freezing Perch have no authored
  drops; M8 Task 2 authors all drops when the content moves to `data.z98`.
  Until then a kill/subdue of those creatures legitimately shows
  `Secured: nothing` in M4 play. The loop golden's fight 2 is Anemoniacus,
  hence its empty kill line.

Checked, no amendment needed: `World` already carries `money`, `expertise[10]`,
`boat[5]` tier counts, `hull`, `cosmetics_owned`, and `cosmetics_unlocked`
(`def.zig:77-80`); part/keystone ids 1–9 exist (`creatures_t1.zig:39-47`); the
derived boat tables are in `world.zig:24-28,117-139`. `NO_FIGHT` lives in
`def.zig:116` and `newGame`/`zeroWorld` is the clean reset path
(`game.zig:16-69`). Dock Rest is already split correctly: public `restAtDock`
is +40 Hull, one phase, no RNG/condition (`expedition.zig:89-96`) vs node Rest
(+30, condition roll, `expedition.zig:349-363`).

### M5 preflight (2026-11-18)

**Spec §38 P22 rulings (binding):**
- Deep refine is legal at **0 yield** and still grants +1 expertise; never
  clamp and never refuse for a 0 yield. Deep loses 1 per part below E5.
- Tool scope split: M5 wires only post-M4 behaviors (Plate armor negation,
  Brine Net shell/restrain bypass, Coral Shield discharge negation, Pressure
  Hook flee prevention, Electric Gland stun). Blind/decoy/ink/phasing and
  Lure/Sonar reveals move to **M8**; M5 only stores/passes their flags.
- Sonar lookahead peeks on a **copied flat `FightState`**, discards it, and
  never mutates `GameState`, log, or world; M8 extends it with ink/decoy.
- `Expedition.hold` is the persistent dock parts store: `depart` must not
  zero it. Craft/keystones consume the hold; Refine consumes all of one type.
- Persistence: `World.materials`, `World.tools_owned`, `World.tool_selected`;
  `Expedition.tool/tool_charge/tool_broken` (tool selection is free at
  Depart; broken tools clear at the next Depart).
- Refusals (insufficient parts/materials/coins, failed E2/E4 gate) cost **no
  phase and no RNG**; every successful dock action costs exactly 1 phase.
- The M5 economy walk starts at **0 materials / E0** and asserts materials
  **spent** = 111 + Steel Fins ×2; full-run pacing stays M15.
- Rare-batch refine warning: Glow Polyp → Luminescence and Glass Pane → Glass
  need a second confirming press stating part count and yield (including
  `0 materials` below E5); commons refine on one press; keystones never refine.

**M5 files:** `economy.zig`, `dock.zig`, `tools.zig`; modify `def.zig`,
`game.zig`, `expedition.zig`, `fight.zig`, `nav.zig`, `render_term.zig`,
`tables_t1.zig`; tests `economy_test.zig`, `dock_test.zig`, `tools_test.zig`,
`tier_m5_dock.sh`, `fixtures/economy_full.md`; dock/sub-menu goldens.
Task 0 adds only `ToolRow`/`UpgradeRow`/`CosmeticRow` (+ local `CostSlot`) to
`tables_t1.zig`; `MaterialAmt` belongs to Task 1's `economy.zig`.

**§17 arithmetic (verified against the rows):**
- Hull: Chitin 3 + 6 + 10 = 19; Plate 2 + 4 = 6.
- Precision: Gland 2 + 4 + 8 = 14; Luminescence 1 + 2 + 2 = 5.
- Cargo: Brine 3 + 6 + 10 = 19; Coral 1 + 2 + 4 = 7.
- Oxygen: Coral 3 + 6 + 10 = 19; Brine 1 + 2 + 4 = 7.
- Speed: Glass 2 + 2 + 4 = 8; Gland 1 + 2 + 4 = 7; Steel Fins ×2.
- Totals: Chitin 19, Plate 6, Gland 21, Lum 5, Brine 26, Coral 26, Glass 8
  = **111** + Steel Fins ×2.
- Parts at E3 (deep yields 2, commons 3): Shell 19/3↑=7, Plate 6/3=2,
  Gland 21/3=7, Glow Polyp 5/2↑=3, Brine 26/3↑=9, Coral 26/3↑=9,
  Glass Pane 8/2=4 → **41 parts** + Steel Fins ×2.
- Cosmetics: 12 items summing 2,100 coins (150/175/200 ×4 categories).

**M4 baseline:** compiler `/tmp/seed151_build/zig1_5_clean` (md5
`a2fc81055dc1cb7a67099fe3934d22ee`); `ZIG=… OUT=/tmp/m5_t0 sh
tests/tier_m4_loop.sh` → `TIER_M4 PASS 47 passed / 0 failed` (1 Wine
evidence skip).

**Deliberate M4 edit (Task 2):** `depart` stops zeroing `hold`/`hold_n` so the
dock keeps its parts store. No current M4 test depends on a fresh hold; the
M4 tier above is the baseline to re-verify after that change.

### M5 Task 5 — real-E0 economy walk + dock tier

- **Walk driver:** `tests/economy_walk_test.zig` is the P22.7 walk. It starts
  from `game.newGame` (0 materials, E0, boat 0), does four one-part refines per
  material to reach E4, adds one measured E4 batch when the four refines are
  short of the §17 target, grants Steel Fins ×2, then buys every axis T1→T3.
  It asserts 111 materials **spent**, Steel Fins `hold[9] == 0`, every axis at
  T3, no negative material/hold count, and +1 `field_phases` per successful
  refine/upgrade. The gate is not bypassed: each purchase asserts
  `canBuyTier`, and the same Hull T2 cost is refused at E1 with no spend and
  no phase.
- **Walk result:** 34 refines + 15 upgrades = 49 phases; 117 materials
  produced, 111 spent, 6 left.

  | Mat | Target | Granted | Produced | Spent | Left | Exp |
  | :-- | --: | --: | --: | --: | --: | --: |
  | Chitin | 19 | 8 | 20 | 19 | 1 | 5 |
  | Steel Plate | 6 | 4 | 8 | 6 | 2 | 4 |
  | Gland | 21 | 9 | 23 | 21 | 2 | 5 |
  | Brine | 26 | 10 | 26 | 26 | 0 | 5 |
  | Coral | 26 | 10 | 26 | 26 | 0 | 5 |
  | Luminescence | 5 | 5 | 6 | 5 | 1 | 5 |
  | Glass | 8 | 6 | 8 | 8 | 0 | 5 |
  | **Total** | **111** | **52** | **117** | **111** | **6** | |

  Table self-check: 41 parts at E3, §17 target sum 111, cosmetics 2,100.
- **Fixture:** `tests/fixtures/economy_full.md` records the §17 table plus the
  §21.5 full-game projection: boat cost fixed at 111 + Steel Fins ×2 (global,
  not per-tier), T2–T4 sale bands (T2 20–80, T3 30–90, T4 40–100; envelope
  20–100), and deep Luminescence/Glass sources per band. Projection only; M13
  re-derives source rows and M15 measures pacing.
- **Tier:** `tests/tier_m5_dock.sh` is FAST/native only: `economy_test`,
  `dock_test`, `tools_test`, `grudge_test`, `economy_walk_test`, key case names
  and exact walk totals, the fixture existence/size/marker check, and a nested
  `tier_m4_loop.sh` (whose dock golden is byte-matched). Result:
  `TIER_M5 PASS 56 passed / 0 failed`.
- **§41 Q2 re-check:** Steel Plate is now **rigged/passive from fight start**
  (`rigged_active_at_fight_start_no_charge`), so M2's "spend a tempo turn to
  equip Plate" no longer exists. Tools still change how a fight is played via
  passive effects (Plate armour negation, Brine Net shell/restrain bypass,
  Pressure Hook flee prevention, Coral Shield discharge negation) and the
  activated Electric Gland stun — not just a damage number. The M2 answer's
  mechanism changes; the "equipment changes the action plan" conclusion still
  holds.
- **Pacing:** full-run pacing/day-count measurement stays **M15**; this task
  only closes the §17 arithmetic from a cold start.

### M6 amendment review (M5 Task 6)

Compared M6 plan Tasks 0–4 (Global capacities, the `Tables` contract, `[tools]`/`[upgrades]`/`[cosmetics]`, validation, and the frozen ID contract) against the M5 actuals: `tables_t1.zig` `ToolRow`/`UpgradeRow`/`CosmeticRow`/`CostSlot`, `economy.zig` `MAT_*`/`MaterialAmt`/`upgradeCost`, `def.zig` §25.1 capacities + `World`/`Expedition` fields, and `expedition.zig` unlock/tool wiring.

Verdict: **amendment required** — the §25.1 capacities already match and need no change, but M6's tool/upgrade/cosmetic row schema, validation, and ID contract must be pinned to the landed M5 shapes.

- **M6 Task 0/Task 2 (`[tools]`).** Freeze row keys as `id,kind,cost0_kind,cost0_amt,cost1_kind,cost1_amt,cost2_kind,cost2_amt`, loading directly into `tables_t1.ToolRow { id, kind, cost: [3]CostSlot }`. `id` is a tool id **1..7, unique** (= `MAX_TOOLS-1`, since `MAX_TOOLS=8`); never 0 and never 8. `tools_owned` is a bit per id 1..7. `kind` is 0 (`TOOL_KIND_ACTIVATED`) or 1 (`TOOL_KIND_RIGGED`); cost kinds are **part ids 1..9** (0 = unused), not material ids.
- **M6 Task 0/Task 2 (`[upgrades]`).** Freeze row keys as `axis,tier,cost0_kind,cost0_amt,cost1_kind,cost1_amt,cost2_kind,cost2_amt`, loading into `UpgradeRow { axis, tier, cost: [3]CostSlot }`. `axis` is the `World.boat` index 0..4 (`BOAT_HULL/SPEED/CARGO/OXYGEN/PRECISION`), `tier` is 1..3; require the full 5×3 grid (15 rows). Cost kinds: 0 unused, 1..7 material (`World.materials[kind]`), 8..9 keystone part (`Expedition.hold[kind]`; Speed T3 uses Steel Fins=9). Load via `CostSlot`; `economy.upgradeCost` is the only `CostSlot`→`MaterialAmt` conversion (both are `{kind,amt}`; do not add a second cost type/table).
- **M6 Task 0/Task 2 (`[cosmetics]`).** Freeze row keys as `name,price,unlock` matching `CosmeticRow`; row order is the cosmetic item index 0..11 (the `cosmetics_owned`/`cosmetics_unlocked` bits). `unlock` is a **condition id 1..4** (Z1/Z2/Z3/Derelict), not an item index; 12 rows. Names are ASCII (spaces allowed; no commas/`=` unless the row grammar gains quoting).
- **M6 Task 2 ID contract.** Extend the frozen append-only contract beyond creature `name`: tool ids 1..7 (bits in `tools_owned`), cosmetic row order 0..11, upgrade `(axis,tier)` keys, material ids 1..7 + keystone parts 8..9. `[encounter]` rows use the **dense `def_index`** (load order) as in `EncounterRow.def_index`, not `CreatureDef.id` (T1 `id` is not load order: e.g. the flex rows have ids 18/19 at indexes 3/4); M13 appends at the end. `[zones]` still maps to `ZONE_COST`/`ZONE_IS_BOSS` `[MAX_ZONES]`.
- **M6 Task 2 (`CreatureDef` schema).** The `CreatureDef` row schema itself needs no amendment; only the `EncounterRow.def_index` vs `CreatureDef.id` distinction above is new.
- **M6 Task 3 validation.** Add tool/upgrade/cosmetic checks: unique tool ids/order, kind ranges, the cost-kind ranges above, full 5×3 upgrades, 12 cosmetics with unlock 1..4, cosmetic prices >0. `MAX_MATERIALS=10` means `World.materials` is `[MAX_MATERIALS]i32` with indexes 0..9: materials use indexes 1..7; indexes 0 and 8..9 are unused (ids 8/9 keystones spend from `Expedition.hold` instead); there is no index 10. Reject kind ≥10 in upgrade costs. Tool cost part ids are 1..9 (future keystones are ids 10..12; `MAX_PARTS=14` leaves 13 as spare, and keystones are drop-only and never required by tools).
- **M6 Task 6 (M7 review).** When checking the save-section overlap, confirm M7's already-listed fields cover the M5 persisted state: `World.materials[10]`, `World.tools_owned`, `World.tool_selected`, `Expedition.hold[14]/hold_n`, `Expedition.tool/tool_charge/tool_broken`, plus `expertise`, `boat`, `money`, and `cosmetics_owned/unlocked` (all already named in the M7 plan); the `FightState` tool fields are transient. `Tables` stays content-only; no save state in `data.z98`.

Checked, no amendment needed: §25.1 capacities in M6 Global (56/12/4/8/14/10/96/24/12) match `def.zig` exactly; the `MAX_TEXT_KEYS=256`/48 KB `[text]` contract is unchanged (M5 adds no text keys), and no `[options]` section is required (`options.cfg` is M12, not `data.z98`); `CostSlot` and `MaterialAmt` are identical `{kind,amt}` layouts, so no extra conversion type is needed.

### M6 preflight

**Authorities:** spec §25.10 (`docs/superpowers/specs/2026-11-12-undersanded-design.md:1270`)
and ruling P23 (`:1831`); M6 milestone row (`:1759`). M6 ships the §25.10
loader plus spec-complete T1 content: 18 creature rows with §14.2 stats, names,
zone/phase masks and §14.4 drops (`:654`), 4 `owner=` rules, §10–§11
tools/upgrades/cosmetics, §13 Z1–Z3 encounters, empty Z4–Z8, manual page 1
text. Loaded tables must match the compiled-in fallback field-for-field, and
malformed rows are rejected with line numbers.

**Z98 override probe (controller-verified on seed v151; do not re-derive):**
the P23(1) mechanism is legal — module-level `pub var content_override:
?*Tables = null`, install `&g_tables`, read through `if (content_override) |p|`.
Probe saw the fallback value 7, then 42 after install, rc=0. Array-of-slices
struct fields (`[256][]const u8`) also compile and run (rc=0).

**M5 baseline** (re-run 2026-11-18 from the repo root; compiler
`/tmp/seed151_build/zig1_5_clean`, md5 `a2fc81055dc1cb7a67099fe3934d22ee`;
base HEAD `bea1bc50`):

```
ZIG=/tmp/seed151_build/zig1_5_clean OUT=/tmp/m6t0 sh examples/z98/undersanded/tests/tier_m5_dock.sh
...
== tier_m5_dock summary: 57 passed, 0 failed ==
TIER_M5 PASS 57 passed / 0 failed
```

Nested M4 result from the same run:

```
== tier_m4_loop summary: 47 passed, 0 failed, 1 evidence skips ==
TIER_M4 PASS 47 passed / 0 failed
```

**Goldens expected to move:** only
`examples/z98/undersanded/tests/fixtures/loop_golden.txt` — the five M2-era
defs (Mystic Eel, Mystic Electric Eel, Steel Tuna, Anemoniacus, Freezing Perch)
gain their §14.4 drops per P23(4), so loop fight 2 (Anemoniacus) adds kill
parts and the `hold ...` line changes. Grep for drivers that hardcode a blank
drop table: **none found**; the drivers derive expected drops from the
compiled-in defs, and the `dump_grid_*`/replay goldens carry no drop text.

**Recorded follow-ups:**
- (a) Derelict kill drops are 5 lines but `MAX_DROP_LINES = 4`; recorded as
  §39 TBD (`:1937`), resolve at M8/M11 (raise the cap to 6 or merge two lines).
- (b) At the M7 Task 7 review, reconcile M8 plan Task 1/2 wording: M6 now
  authors the rows/names/masks/drops, so M8 must not re-author them or assume
  the old blank tables.
