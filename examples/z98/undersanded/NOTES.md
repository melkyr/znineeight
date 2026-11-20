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

### M6 Task 3 loader

`data.loadFile(arena, path, tables) LoadErr!void` reads the whole file with
`std_file.readAll(arena, path)` and commits `tables.*` only after the whole
parse succeeds. `data.err_line` is the 1-based line for
`DamagedLine`/`BadRef`/`Overflow`/`TooMany` failures. All `std_file` errors
(`OpenFailed`, `ReadFailed`, `SizeFailed`, `OutOfMemory`, ...) are
`catch`-mapped to `LoadErr.Io`; `Missing` remains in the set for the Task 5
startup path. Unknown sections are `sectionId == -1`; unknown/duplicate/missing
row keys reject at the row line; the header is compared raw (no surrounding
spaces). `[text]` values are compacted in place and stored as slices of the
arena file buffer; `manual.1` is required. `[rules]` packs by owner
first-appearance order and writes each creature's `rule_start/rule_count`.
`dumpDefs` is field-by-field text (never struct bytes); its committed golden is
`tests/fixtures/defs_golden.txt`.

### M7 amendment review (M6 Task 7)

Read the whole M7 plan, spec §25.10, §32, §38 P23/P24, and the landed M6 shapes
(`def.Tables`, `data.loadFile/buildFallback/install`, `validate.validateAll`,
`creatures.defAt/defCount/rules`, `tables.rows/tools/upgrades/cosmetics/
zoneCost/zoneIsBoss`).

Verdict: **amendment required** — the M7 design is sound, but Task 1's "M6
parsers" is too broad, the persisted-field list does not stand as written (no
Field Record / Last Run / release-count fields exist), the `data_version` source
and the `manual.1` lookup are not pinned, and `BadId` must be a load-order check.
The amendments below are clarifications, not a redesign; the M7 plan itself is
not edited here.

#### 1. Parser reuse (save grammar vs §25.10)

The save is **not** a §25.10 file. §25.10 rows are comma-separated
`key=value` fields (many keys per line) with a mandatory `format=2` header and
the fixed `[creatures]`…`[text]` vocabulary. The M7 save is a `version=` /
`data_version=` header followed by save-local sections (`[world]`, `[boat]`,
`[cooldowns]`, `[journal]`, `[score]`, reserved `[options]`) with **one
scalar `key=value` per line** and arrays written as `name=i,i,i`; `[crc32]` is
last.

May reuse:

- `data.parseI32` for every i32 scalar and every array element (thin wrapper
  over `std_parse.parseInt`).
- `data.parseRowKV` **only** for a comma-free, non-empty scalar line (one
  `key=value`, no comma in the value). It trims surrounding spaces, strips a
  trailing `\r`, and rejects an empty key/value or a duplicate key. Because it
  splits on **every** comma, a value containing a comma (or an empty value) is
  not save-compatible; do not use it for arrays or any value that may contain a
  comma. It may not validate save keys; M7 keeps its own section/key schema.
- The line-splitting/CRLF contract: split on `\n`, strip one trailing `\r`.
  M6 has **no exported splitter** (`stripCR` is private and `classifyLine`
  wraps it), so M7 must reproduce the same short scan (or M6 could export
  `stripCR` as a follow-up; not required).
- For `u32` fields (`rng_state`, `seen_mask`/`journal_mask`/`wary_mask` words,
  `tools_owned`, `cosmetics_*`, `boss_variants_seen`) use
  `std_parse.parseUint`, not `parseI32`; M6 exposes no `parseUint` wrapper.
  Parse `[crc32] hash=0xXXXXXXXX` as hex, not `parseI32`.

Must **not** reuse:

- `data.sectionId` — it is the §25.10 vocabulary and returns `-1` for every save
  section (`world`, `boat`, `cooldowns`, `journal`, `score`, `crc32`, `options`).
- `data.classifyLine` as the header/section classifier — it treats `format=2` as
  the only valid header (save starts with `version=`/`data_version=`) and its
  section/comment rules are data-file rules.
- `beginTextEntry`/`finishTextValue` and the `[text]` continuation rules
  (one-space paragraph lines, comments inside prose). Saves have no prose
  payload; `[options]` is an ordinary KV section.
- `validate.validateAll`, `data.buildFallback`, and `data.textKeyKnown` — all
  content-schema, not save-code, concerns.
- `parseRowKV` for arrays: `name=i,i,i` splits at each comma into fields with no
  `=`, so it fails. Split the value at `=` first, then at commas, and run
  `parseI32` per element (M7-local helper).

**Exact amendment text (M7 Task 1, replace "Implement `persist.zig` with M6
parsers"):**

> Implement `persist.zig` reusing only `data.parseI32` for i32 scalars/array
> elements and `data.parseRowKV` for comma-free, non-empty scalar lines (never
> for arrays or comma-bearing values); use
> `std_parse.parseUint` for every `u32` field and a hex parser for `[crc32]
> hash=0xXXXXXXXX`. Write a save-local line scanner (`\n`, strip one trailing
> `\r`), a save-local array parser (`name=v[,v...]`), and the save section
> vocabulary (`version`, `data_version`, `[world]`, `[boat]`, `[cooldowns]`,
> `[journal]`, `[score]`, reserved `[options]`, `[crc32]` last). Do not use
> `data.sectionId`, `data.classifyLine`'s `format=2` header rule, the `[text]`
> continuation logic, `validateAll`, or `buildFallback`.

#### 2. `data_version` ↔ `content_version`

`loadFile` publishes `format=2` as `Tables.content_version = 2`; `buildFallback`
also sets 2. §25.10 requires the save's `data_version` to equal
`content_version`, so the comparison source is the **installed P23(1) tables**,
not a literal:

```
const cv = if (def.content_override) |t| t.content_version else 2;
```

The game installs `data.g_tables` via `content_boot.loadFromDir` →
`data.install` before any save read; the tool fallback path leaves
`content_override == null` and uses 2. There is no `data.contentVersion()`
wrapper. Place the check in `saveRead`'s §32 load-check block, after parsing
`version`/`data_version` and in §32 order (version → data_version → CRC → IDs),
returning `BadDataVersion` on mismatch; no migration.

**Exact amendment text (M7 Task 1, add after the error/test sentence):**

> Compare the save's `data_version` with the installed content version, not the
> literal 2: `const cv = if (def.content_override) |t| t.content_version else 2;`
> In `saveRead`, perform the comparison after the `version` check and before
> accepting the save, in §32 order (`version` → `data_version` → CRC → IDs).
> Mismatch returns `BadDataVersion`; never migrate.

#### 3. `[text]` page-1 handoff

Confirm all four points:

- **Key:** `manual.1` (exactly). `data.z98` line 130 carries it.
- **Non-empty rule:** `validate.validateAll` requires `manual.1` to be present
  and non-empty whenever `text_count > 0`; the compiled-in fallback is
  tables-only (`text_count = 0`) and is exempt (P24(1)). The game always loads
  the shipped file, so first-run must read the loaded value, never the fallback.
- **API:** M6 has **no production text-value getter**; only `text_key[]` /
  `text_val[]` on `def.Tables` (public) and `data.textKeyKnown` (validation
  only). Read through the installed tables
  (`def.content_override.?.text_key`/`text_val`) with a linear scan for
  `manual.1`, or add a tiny M7-local `textGet(t, key) ?[]const u8`. The test-only
  `textFind` helpers in `data_load_test.zig` and `data_content_test.zig` are not
  production code.
- **Paragraph breaks:** P24(2)/§25.10 store a one-space continuation line as a
  retained blank line, so the arena value uses literal `\n` line breaks and
  `\n\n` between paragraphs; `\r` is stripped. A `#` after the leading space is
  prose, not a comment. Render/emit those `\n`s; do not re-trim or rewrap.

**Exact amendment text (M7 Task 3, replace "embedded `[text]` from data.z98"):**

> Read page 1 from the installed tables with a local lookup for key `manual.1`
> (`def.content_override.?.text_key`/`text_val`; M6 has no value getter). Treat
> the stored value as literal text: `\n` is a line break and `\n\n` is a
> paragraph break (P24). Show it only when the loaded value is present and
> non-empty; the tables-only fallback is not a content source. M7 consumes
> `manual.1`; it does not author it (M6 ships it in `data.z98`).

#### 4. Persisted-field list vs M6 shapes

Verified: `git diff bea1bc50..HEAD -- examples/z98/undersanded/def.zig` adds
`MAX_NAME_LEN`/`MAX_TEXT_KEYS`/`MAX_TEXT_BYTES`, `CreatureDef.name`/`name_len`,
the content row types, `Tables`, and `content_override`; **`World` and
`Expedition` are unchanged** (no new fields), and `world.zig` has no M6 diff.

However, the landed `World`/`Expedition` (`def.zig:130-157`) contain **no**
Field Record or Last Run structs and **no** "release count" field, while M7's
Global Constraints list "score stats, Field Record + Last Run" and "release
counts + bonuses + wary flags", and `saveWrite(path, w, exp)` accepts only
`World` + `Expedition`. **M7's list does not stand as written:** M7 Task 0 must
define those persisted fields (or explicitly defer the Field Record / Last Run /
score payload and release counts to M11) before freezing the save grammar and
before Task 1's `saveWrite` interface.

M6 changes that touch saves are content-only or index-contract facts:

- Creature `name`/`name_len`, zone/phase masks, stats, drops, and rules are
  content, not save state. `CreatureDef.id` is the content id; it is **not** the
  array index used by saves.
- `World.ready[zone*MAX_CREATURES + def_index]`, `seen_mask`, `journal_mask`,
  and `wary_mask` are indexed by **load-order `def_index`** (`0..defCount-1`).
  M7's "unknown creature id in cooldowns → BadId" must validate against
  `creatures.defCount()` (installed count), not `CreatureDef.id`. T1 row order
  is unchanged/append-only; `data_version` guards future content changes.
- `tooltip_shown` and `field_phases` already existed before M6; M7 Task 3
  already lists them. `World.rng_state` is a pre-existing §25.7 field absent
  from M7's list; it is not an M6 change, but M7 should decide whether reload
  determinism requires persisting it (if so, add it to the Task 0 checklist).

**Exact amendment text (M7 Task 0, add to the persisted-field checklist):**

> The landed `World`/`Expedition` (`def.zig:130-157`) have no embedded Field
> Record or Last Run structs and no release-count field. Before freezing the
> save grammar, either (a) add the flat persisted structs/fields (and extend
> `saveWrite`/`saveRead` beyond `World` + `Expedition` if they live outside
> those structs), or (b) explicitly defer the Field Record, Last Run, score
> stats, and release counts to M11 and remove them from the frozen list. Also
> decide whether `World.rng_state` must persist for reload determinism.

#### 5. Cross-plan follow-up for M8

Recorded for the **M7 Task 7 review** in the M6 preflight: M8's plan still says
rows move from `tables_t1.zig` fixtures to `data.z98` and that Task 1 "Implement
rows" / Task 2 "M5 fixtures → real file". **M6 already authors `data.z98`**: 18 non-boss creature rows with
names/stats/zone-phase masks/§14.4 drops, 4 M2-era `[rules]`, 7 tools, 15
upgrades, 12 cosmetics, Z1–Z3 encounters, the zone ladder incl. boss zone D, and
`manual.1`. Reconcile at that review:

- M8 Task 1 adds the Derelict **boss sentinel row** (the 19th row) and reconciles
  the remaining §14.3 behavior encoding (which effects are already M6 named
  fields vs. still need `[rules]` rows); it must not re-author the 18 M6 rows,
  names, masks, or drops.
- M8 Task 2 does not re-author tools/upgrades/cosmetics/encounters/zone D; it
  keeps/verifies them and only adds content M6 did not ship.
- M8 Task 3 authors `manual.2..8`, journal entries, legends, zone flavor, and
  error copy; it must not re-author `manual.1` (M6 ships it; M7 consumes it).
- Align M8's "19 rows" goal wording with the split: M6 ships 18 (all non-boss);
  M8 adds the boss row.

### M7 kickoff rulings (P25)

User-authorized R1–R4 ("lets do the ammendments, R1. yes. R2. yes R3. yes R4. Yes."),
applied to spec §20/§25.7/§32/§38 P25 and the M7 plan:

- **R1** — `canSave` blocks mid-fight **and** while a subdue Release/Sell choice
  is pending; spec §32 amended. Nothing is lost: no other action is legal in
  that state.
- **R2** — `FieldRecord`, `LastRun` and lifetime
  `score_subdued/score_killed/score_overkilled/score_money_earned` are added to
  `World` **now** (flat scalars, zeroed by `zeroWorld`); M11 populates them and
  the save stays `version=2` with no format bump.
- **R3** — fresh install follows §20 exactly (page 1 → world init → dock, no
  menu); the start menu appears only on a boot where a save exists.
- **R4** — `New Game` on an existing save asks `Erase this save? [Y] [N]`, then
  re-inits the world without repeating page 1.

Controller calls (not user-facing) folded into the same amendments:

- `pending_cond` moves from `GameState` to `Expedition` (cleared at `depart`,
  set by rough-sleep Rest, read+cleared at fight start) and is persisted in
  `[expedition]`; all call sites update.
- Save-local scanner and section vocabulary (`version`/`data_version`,
  `[world] … [crc32]`), never the §25.10 parser; `std_crypto.crc32`;
  `data_version` compares to installed `Tables.content_version`.
- `manual.1` is authored by M6 and only consumed by M7; M7 authors the
  save/crash error copy.
- `options.cfg` holds `save_slot` only; M7 adds a read-only reader (default 0),
  M12 owns writing it.
- Save lines 8192 B, file cap 64 KiB, arrays one line each, `[crc32]` last with
  nothing after it; unknown keys strict except inside `[options]`.
- Two error surfaces: §33 fatal screen (`[Enter] Quit`) for content/crash; a
  save-error screen (`[F]resh [B]ackup slot [Q]uit`) for load checks.
- Load is all-or-nothing into a zeroed temp `World`/`Expedition`; range checks
  beyond ID resolution (hull ≤ boat max, phase 0/1, boat tiers 0..3, expertise
  0..5, masks < `defCount()`).
- `errors.log` append helper (recovery/warning lines) and startup recovery runs
  before any fresh-install decision.
- `tier_m7_save.sh` nests `tier_m6_data.sh`.
- D18: nested array-field writes (`w.field_record.boat[i]`, `.expertise[i]`) must use a
  pointer or a whole-struct assignment; plain nested indexed writes silently
  miscompile.

### M7 Task 0 preflight (frozen)

**Save grammar (spec §32, frozen for Tasks 1–4).**

- Header: `version=2`, then `data_version=2`.
- Save-local section order: `[world]`, `[boat]`, `[cooldowns]`, `[journal]`,
  `[expedition]`, `[score]`, reserved `[options]`, `[crc32]`.
- **One scalar `key=value` per line**; arrays are **one line each** as
  `name=i,i,i`; no multi-key lines, no prose/continuation lines.
- `[crc32] hash=0xXXXXXXXX` is last; **nothing may follow it**. The CRC covers
  the file start through the newline immediately before the `[crc32]` section
  line; nothing after `hash=` is covered.
- Unknown key = `Damaged`, except inside the reserved `[options]` section
  (skipped; M12 fills it).
- Line buffer **8192 B** (worst-case `ready[672]`); whole-file cap **64 KiB**.
- Save-local line scanner (`\n`, strip one trailing `\r`) and save-local array
  parser (`name=v[,v...]`); never `data.zig`'s §25.10 parser.
- **`save_slot` lives only in `options.cfg`** beside the saves, read at boot
  before any save; M7 adds a read-only parser (`save_slot=0|1`, default 0 when
  absent/damaged), M12 owns writing it.
- Load check order: `version` → `data_version` → CRC → IDs; no auto-migration.

**Persisted-field checklist (Task 1 must cover every item).**

World (P25/R2 structs are flat scalars, zeroed by `zeroWorld`):

- [ ] `cycle`, `phase`
- [ ] `ready[672]`
- [ ] `seen_mask[2]`
- [ ] `journal_mask[2]`
- [ ] `tooltip_shown`
- [ ] `field_phases`
- [ ] `hull`
- [ ] `release_bonus[12]`
- [ ] `lockout_until[12]`
- [ ] `family_overkill_mask`
- [ ] `wary_mask[2]`
- [ ] `rng_state`
- [ ] `boat[5]`
- [ ] `money`
- [ ] `expertise[10]`
- [ ] `materials[10]`
- [ ] `tools_owned`, `tool_selected`
- [ ] `cosmetics_owned`, `cosmetics_unlocked`
- [ ] `field_record_written`
- [ ] `boss_variants_seen`, `boss_kills`
- [ ] P25 `FieldRecord`: `cycles`, `field_phases`, `creatures_seen`,
      `rares_seen`, `bosses_killed`, `final_phase2`, `subdued`, `killed`,
      `overkilled`, `expertise[10]`, `money_earned`, `cosmetics`, `boat[5]`
- [ ] P25 `LastRun`: `cycles`, `phase2`, `outcome`, `actions`, `hull_spent`,
      `boss_kills`
- [ ] P25 lifetime `score_*`: `score_subdued`, `score_killed`,
      `score_overkilled`, `score_money_earned`

Expedition:

- [ ] `active`, `zone`, `fight_index`, `seed`
- [ ] `hold[14]`, `hold_n`
- [ ] `tool`, `tool_charge`, `tool_broken`
- [ ] `pending_cond`

**P25 rulings (verbatim).**

- **R1** — `canSave` blocks mid-fight **AND** while a subdue Release/Sell
  choice is pending.
- **R2** — `FieldRecord`/`LastRun`/`score_*` counters added to `World` now,
  zeroed by `zeroWorld`, persisted, save stays `version=2`, M11 populates only.
- **R3** — fresh install follows spec §20 (page 1 → world init → dock, no
  menu), start menu only when a save exists.
- **R4** — New Game asks `Erase this save? [Y] [N]` then re-inits without
  page 1.

**M6 handoff facts.**

- Load-order `def_index` order:
  `[1,2,4,18,19,5,7,8,9,10,3,6,11,12,13,14,15,16]`.
- M8's Derelict appends at index 18.
- `BadId` validates against `creatures.defCount()`, never `CreatureDef.id`.
- `manual.1` is authored by M6 and only **consumed** here.
- `data_version` compares to the installed `Tables.content_version`
  (`def.content_override` else 2).

**Controller calls (binding).**

- NAV ids: `NAV_LORE=19`, `NAV_MENU=20`, `NAV_SAVE_ERR=21`.
- Files: `save0.dat`/`save1.dat`/`save.bak`/`save.tmp` in
  `dataDirOrFallback`; `options.cfg` in the same dir with read-only
  `save_slot=0|1` (`save1.dat` is manual only, never auto-written).
- CRC range: file start through the newline immediately before the `[crc32]`
  section; nothing after `hash=` is covered.
- Menu keys `[C]ontinue [N]ew [O]ptions [Q]uit`; New Game confirm
  `Erase this save? [Y] [N]`; Options greyed until M12.
- `SaveErr.Io` catch-maps `FileError` via the shared M6 mapping.
- Fault-injection seam: module-level plain fn fields `fs_rename`/`fs_remove`
  (defaults `std_file`; no `?fn` call-throughs).
- D18: nested-array writes must go through a pointer or whole-struct
  assignment.

**Error surfaces + log helper.**

- §33 fatal screen: full-screen text, `[Enter] Quit`, for content/crash
  failures.
- Save-error screen: `[F]resh  [B]ackup slot  [Q]uit`, for load-check failures
  (exists / `version` / `data_version` / CRC / IDs).
- `errors.log` append helper writes recovery/warning lines to the writable dir
  (`dataDirOrFallback`, beside the saves).

**Baseline + files.**

- Compiler: `/tmp/seed151_build/zig1_5_clean` (seed v151, md5
  `a2fc81055dc1cb7a67099fe3934d22ee`).
- `ZIG=/tmp/seed151_build/zig1_5_clean OUT=/tmp/m7_t0/baseline sh
  examples/z98/undersanded/tests/tier_m6_data.sh` → **`TIER_M6 PASS 90 passed /
  0 failed`** (nests M5 57/0, M4 47/0, M3 65/0); `TIER_M1 PASS 41/0`.
- M7 files: `def.zig`, `expedition.zig`, `persist.zig`, `save_ux.zig`,
  `nav.zig`, `render_term.zig`, `undtool.zig`, `app.zig`, `game.zig`,
  `paths.zig`; tests `tests/persist_test.zig`, `tests/bind_test.zig`,
  `tests/tier_m7_save.sh`, `tests/fixtures/save_v1_bad.sav`; docs `NOTES.md`.
  No other files.

**D18 hazard.** `FieldRecord.boat[i]` / `FieldRecord.expertise[i]` and other
nested array-field writes must go through a pointer (for example
`var fr: *FieldRecord = &w.field_record; fr.boat[i] = v;`) or a whole-struct
assignment; plain nested indexed writes silently miscompile (D18).

### M8 amendment review (M7 Task 5)

Read `2026-11-12-undersanded-m08-t1-content-plan.md` against the landed M6
content and the M7 save/UI surfaces. Verdict: **amendment required** — the M8
design is still sound, but its Task 1/2/3 wording re-authors content M6 already
ships, its Derelict row cannot load under the current validator and
`MAX_DROP_LINES`, and the journal/help/message/error-copy wiring is stale.

**(a) `[text]` capacity — no amendment needed.**

- Keys: `manual.1..8` (8) + `journal.1..19` (19) + `legend.1..2` (2) +
  `error.1..6` (6) = **35** vs `MAX_TEXT_KEYS=256` (`def.zig:20`;
  spec:1089). Zone-flavor keys, if added, still leave ~215 free.
- Bytes: the whole T1 prose set is roughly 8–14 KB worst case (19 journal
  paragraphs, 7 manual pages, 2 legends, 4 zone paragraphs, 6 short errors)
  vs `MAX_TEXT_BYTES=48 KiB` (`def.zig:21`; spec:1090; the loader counts
  `text_val` bytes, `validate.zig:331-341`). `data.z98` currently carries one
  text value (`manual.1`, `data.z98:130`). No capacity amendment.

**(b) Task 1/2/3 wording is stale — amendment required.**

- M6 already ships **18** creature rows with names/stats/masks/§14.4 drops
  (`data.z98:6-23`), 4 `[rules]` (`data.z98:25-29`), 7 tools
  (`data.z98:31-38`), 15 upgrades (`data.z98:40-55`), 12 cosmetics
  (`data.z98:57-69`), Z1–Z3 encounters (`data.z98:71-113`), the full zone
  ladder including boss zone D (`data.z98:115-127`, D at `:124`), and
  `manual.1` (`data.z98:129-132`). The M6 preflight records the same split.
- Task 1 must not "move rows from `tables_t1.zig`" or re-author those 18
  rows: it appends **one** Derelict row at load-order index **18** (`id=17`;
  current def_indexes 0..17) and completes only the remaining §14.3 behavior
  encoding. Task 2 verifies the already-shipped drops/tools/upgrades/
  cosmetics/encounters/zone D and adds only Derelict drop rows/content M6 did
  not ship; gate/telegraph are code constants, not `[zones]` rows. Task 3
  must not re-author `manual.1`; pages 2..8 only. The plan goal/manual line
  "17 rows + 2 flex" and "page 1 at M7" (`m08 plan:5`) are stale.

**(c) Derelict drops and row validity — amendment required.**

- §14.4 gives the Derelict **5** kill-drop lines (Plate ×5, Gland ×3, Glow ×3,
  Glass ×2, Coral ×2) but `MAX_DROP_LINES=4` (`def.zig:10`; spec:1079; §39
  says M8/M11). The loader's drop key tables are 4-wide
  (`data.zig:540-545`) and the fallback rows are 4-wide, so "raise to 6"
  means `def.zig` + `data.zig` + `creatures_t1.zig` + dump goldens; merging
  lines changes §14.4. Resolve before appending the boss row (or defer the
  row to M11 explicitly).
- The boss row also trips current validation even before drops: `role`
  "boss" = 4 (`render_term.zig:357`) exceeds `ROLE_MAX=3`
  (`validate.zig:12-13,89-92`); `family` must be 1..12
  (`validate.zig:14-15,85-88`) and no boss family id is defined; `sale<=0`
  is rejected (`validate.zig:119-122`) although §14.2 shows "—"; `resolve`
  is a required data key (`data.zig:622`) but `resolve=0` is not rejected by
  validation, so §14.2's "—" still needs a numeric row value; and
  `subdue_chance=-1` must pair with `flags&F_BOSS` (`validate.zig:108-117`).
  Pin role/family/sale/resolve (or add boss exemptions) at M8.

**(d) Ownership — amendment required to Task 3 wording.**

- `manual.1` stays **M6-author / M7-consume** (`data.z98:130`;
  `save_ux.zig:171-179`; NOTES P25). M8 authors `manual.2..8` only.
- M7 already owns and shipped the save/crash copy as code constants
  (`content_boot.zig:15-17`; `save_ux.zig:155-162`). `[text]` accepts
  `error.1..6` (`data.zig:799-802`) but **no code reads them**. Task 3's
  "error copy 6 messages … M7 consumes the keys" (`m08 plan:56`) is stale:
  either keep M7 ownership and drop error copy from M8, or name the exact
  remaining messages and add a reader; do not ship dead `error.*` keys.

**Other concrete amendments M8 needs.**

1. **H4 uses `journal_mask`, not `spd_revealed`.** The plan names a
   `spd_revealed` bit (`m08 plan:56`) that does not exist. `World.journal_mask`
   is the persisted per-def bit set (`def.zig:151`; `persist.zig:326-327`),
   and `render_term.effectiveSpeed` currently always prints Speed
   (`render_term.zig:139,340`; `:339` is the SPD label). Key the reveal off
   the journal bit for `def_index`; seen (`seen_mask`, fight start, §8.8) is
   separate from journal
   (first fight end, §18).
2. **Message table completion.** M8's blind/ink/decoy/phase/Lure/Sonar logs
   have no ids/text; `def.MESSAGES` has three rows (`def.zig:252-265`) and
   `msgLine` lacks these cases (`render_term.zig:235-260`), so new logs would
   render "Log N.". Add msg ids, `MESSAGES` rows and/or switch copy with the
   fight wiring.
3. **Unwired M8 fight behaviors + Lure/Sonar constants.** The flags/fields
   exist but no behavior is wired: `F_PHASING`/`F_INK`/`F_DECOY` and
   `blind_chance` (`def.zig:35,230-232`), `pending_blind`/`pending_ink` are
   only initialized/set (`fight.zig:160-161,391-400`), and neither the strike
   path nor `peekCreatureAction` consumes them (`fight.zig:65,296`). Also
   `TOOL_LURE` (4) and `TOOL_SONAR` (6) exist in content
   (`data.z98:35,37`) and names (`render_term.zig:448,450`) but not in
   `fight.zig` (only 1/2/3/5/7 at `fight.zig:57-61`). Add the constants and
   wire phasing/ink/decoy/blind plus the counters/reveals; `peekCreatureAction`
   still says M5-only.
4. **Journal/help need UI wiring.** `journal.zig`/`help.zig` do not exist and
   the M8 file list omits `nav.zig`/`render_term.zig` (`m08 plan:22-26`).
   `?` manual, the Esc-menu Journal/"New entry" indicator, and hidden Speed
   all need new screen/key handling; `nav.zig` already has
   dock/map/node/settle/refine/upgrade/craft/buy/tools/lore/menu/save-error
   screens (`nav.zig:26-38,280-309`; spec:1447-1456) but lacks the M8
   journal/help screens. Add those screens to the M8 structure and pin their
   ids/keys; do not rebuild the existing navigation. The indicator also needs
   a viewed marker (journal_mask only records unlocks).
5. **Zone flavor has no text vocabulary.** `textKeyKnown` accepts only
   `manual.*`, `journal.*`, `legend.*`, `error.*` (`data.zig:786-804`;
   spec:1307), so the four zone paragraphs cannot be authored as planned
   without extending the key vocabulary/validation (and spec §25.10) or
   deferring/deleting that item. No renderer reads zone flavor today.
6. **Boss journal trigger timing.** M8 authors all 19 entries, but the boss
   fight is M11; only `journalOnBossKill`/its trigger test can ship in M8.
   Do not claim an end-to-end boss-kill journal test in M8.

## M8 preflight (P26 amendments applied)

User rulings applied to the spec (§25.1/§25.2/§25.10/§32/§38 P26) and the M8
plan before implementation. Baseline at commit `139aebdf`: `TIER_M7 PASS
126/0` (nested M6 90/0), seed v151.

**Scope is verification + one new row, not re-authoring.** M6 already ships
18 creature rows, all §14.3 named-field encodings, §14.4 drops, 7 tools, 15
upgrades, 12 cosmetics, Z1–Z3 encounters, zone D and `manual.1`. M8 adds the
Derelict row (load-order index 18), wires blind/ink/decoy/phasing + Lure/Sonar,
and authors journal/manual 2–8/legends/zone text.

**Rulings (P26):** (C1) boss row this milestone; `MAX_DROP_LINES` 4→6;
`ROLE_BOSS=4`, `FAMILY_BOSS=13`; boss exemptions `sale=0`/`resolve=0`;
`subdue_chance=-1` + `F_BOSS`. (C2) "New entry" = persisted `journal_viewed`
mask as an **additive optional save key** (absent ⇒ 0), §32. (C3) keep M7's
Esc-at-dock = Save / `q` = Quit; add `J` + dock "New entry"; no Esc menu this
milestone. (C4) zone flavour authored now: `[text]` gains `zone.1..9`;
T1 authors `zone.1/2/3/9`.

**Behaviour drivers (binding, §25.2):** coupling = regen fields; discharge =
`[rules]` one-shot (`discharge_*` pin); armor/speed-below/atk-below/flee-on-hit/
grudge/resist = named fields; Rust flee = `[rules]` `SET_FLEE` `HP_BELOW 24`;
blind = `[rules]` `SET_BLIND` (`RES_BELOW 65`, `effect_b=50`, persistent);
ink = `[rules]` `SET_INK` (`ROUND_MOD` 3/0, persistent); decoy = `[rules]`
`MISS_STRIKE` (`FIRST_ROUND`, one-shot); **phasing is the sole VM exception**
(`F_PHASING` + §25.8 algorithm, no phase op). Every §25.6 effect op executes
(`MISS_STRIKE`, `ADD_SPEED`, `MULT_ATK` are implemented, not no-ops).
Thresholds are absolute integers (50% of 130 = 65), never percentages.

**VM correction (supersedes the first M8 draft):** ink and decoy are *rule
rows*, not flag+logic. `applyRules` runs once per round, so `SET_INK` +
`ROUND_MOD` fires once per matching round and the consumer randomises the
next action; `MISS_STRIKE` + `FIRST_ROUND`+one-shot fires round 1 only. The
landed `applyEffect` already sets `pending_ink`; the missing pieces are the
MISS_STRIKE implementation and the latch consumers. Phasing stays
algorithmic because the vocabulary has no phase op.

**Derelict row:** `id=17`, `family=13`, `role=4`, `zone_mask=256`,
`phase_mask=3`, `hp=300`, `resolve=0`, `speed=7`, `attack=10`, `subdue=-1`,
`flags=1`, `sale=0`, `respawn 20/20/40`, `counter_tool=1`; kill =
Plate×5/Gland×3/Glow×3/Glass×2/Coral×2; over = Plate×2/Gland×1.

**Corrections applied to the plan:** manual page 1 is M6-authored/M7-consumed
(pages 2–8 here); `error.*` is not authored (M7 owns the copy); journal key =
`journal.<def_index+1>` (boss = 19); H4 uses `journal_mask`, not a
`spd_revealed` field; zone flavour vocabulary added.

**Baseline (`0a0f8b9b`):** measured at this HEAD with seed v151
(`/tmp/seed151_build/zig1_5_clean`, md5 `a2fc81055dc1cb7a67099fe3934d22ee`):

```
ZIG=/tmp/seed151_build/zig1_5_clean OUT=/tmp/m8_t0 sh examples/z98/undersanded/tests/tier_m7_save.sh
```

`TIER_M7 PASS 126 passed / 0 failed`. M7 nests M1–M6, so `tier_m1_std.sh`
was not run separately. Nested: `TIER_M6 PASS 90 passed / 0 failed`;
`TIER_M5 PASS 57 passed / 0 failed`; `TIER_M4 PASS 47 passed / 0 failed`
(47/0, 1 evidence skip); `TIER_M3 PASS 65 passed / 0 failed` (65/0, 1
evidence skip); `TIER_M2 PASS 29 passed / 0 failed`; `TIER_M1 PASS`
(41/0, 0 evidence skips; the M1 line itself carries no counts).

### M9 amendment review (M8 Task 5)

Read `2026-11-12-undersanded-m09-pixel-tier-plan.md` against the landed M8
fight surface (`render_term.zig:112-401`, `nav.zig:261-388`,
`data.z98:133-182`) and spec §8.8/§26/§27/§36. Verdict: **amendment required**
— M9 is still fight-only (spec §36; plan Goal/Task 4), so the M8
dock/map/node/journal/help screens, zone flavour, and boss telegraph remain
terminal and need no art layout now. But the art fight screen must render six
M8 fight-surface facts the plan does not pin.

- **Hidden Speed / Sonar reveal.** M8 prints `SPD ??` unless
  `render_term.speedRevealed` is true (`render_term.zig:120-123`, `:385-390`):
  the `World.journal_mask` bit for `fight.def_index`, or
  `tool_active && tool == fight.TOOL_SONAR`. Amend M9 `layoutFight`/stats to
  carry the same state and reveal paths, with unit checks for hidden,
  journal-revealed, and Sonar-revealed Speed (only call/display
  `effectiveSpeed` when revealed). Otherwise §8.8/H4 regress in art mode.
- **Tool status line.** The terminal fight draws
  `TOOL <name> <kind> charge N broken yes/no active yes/no`
  (`render_term.zig:347-370`); the longest live form is 69 chars
  (`Bioluminescent Lure`, activated, charge 1). The §27 art layout names only
  a generic HUD `tool`; pin the full status in the layout (or state where it
  is dropped) and keep it within the 640 px / 8 px glyph = 80-column width.
- **Mid-fight help overlay.** M8 makes `?` work on every screen, including
  mid-fight (`nav.zig:289-298`), rendering `journal.helpPage(g.screen)`
  (`nav.zig:361-365`, `render_term.zig:1016-1021`). M9 must either draw the
  same overlay over the art fight or explicitly fall back to terminal; the
  current plan says only "wire art fight screen".
- **Zero-max Resolve bar (boss row).** M8 ships the Derelict with
  `resolve=0` (`data.z98:24`), and the terminal bar helper guards `max <= 0`
  before `value * width / max` (`render_term.zig:125-133`). M9 Task 3's
  fill/red-zone formulas and hp 0/half/max tests omit `max_res == 0`; add the
  guard and a boss-row bar case so the art Resolve bar cannot divide by zero.
- **Art subdue modal.** The fight surface early-returns into `renderModal` for
  `SCREEN_SUBDUE`/`SCREEN_SUBDUE_POST` (`render_term.zig:375-377`, copy/actions
  at `:323-345`). M9 Task 4 says only "wire art fight screen" and Task 3 only
  defines `layoutFight`; nothing pins an art modal layout or a terminal
  fallback. M9 must pin an art modal layout (or explicitly reuse the terminal
  modal) and test it.
- **`msgLine` sharing.** `msgLine` is private (`render_term.zig:174`), so the
  art renderer cannot call the terminal formatter directly. M9 must
  export/share the message text or duplicate the copy mapping
  deterministically, with a parity test/golden against `render_term`.

Checked, no amendment needed:

- **Fight log line lengths.** M9's 8 lines at 8×16 = 128 px inside the 140 px
  log band; 640 px = 80 glyph columns. All authored/dynamic M8 fight lines fit
  (longest fixed line 57 chars: Lure true-target; longest dynamic subdue line
  52; Ink 53), so the art log needs no wrapping or taller band once the
  message text is shared/duplicated (see `msgLine` sharing above).
- **Dock/map/node/journal/help geometry and zone flavour.** These M8 screens
  stay terminal in M9, and Task 5's M8 byte-identical `--dump-grid` goldens
  protect them. M9 implies no art dimensions for them; no layout change is
  needed now. If a later milestone adds art screens, it must reserve the
  journal text block/help page area then.
- **Boss telegraph / role.** "Hull 150+ recommended." is a node-screen string
  (`render_term.zig:799-801`) and boss fight UI/telegraph behavior is M11;
  M9 only needs the boss row's zero-Resolve guard, and `ROLE_BOSS=4` already
  renders as `boss` through `roleName` (`render_term.zig:164-172`).
- **Sonar / Lure / blind / ink / decoy / phase copy.** These M8 messages are
  already encoded in `MSG_*`/`msgLine` (`render_term.zig:253-295`), so no
  art-only text or width is required.

### M9 preflight (P27 amendments applied)

Kickoff rulings (spec §38 P27; user-authorized "3. A"):

- **PAL base = `std_gfx_pal` window/pump** (spec §23.1 is literal). px owns its
  own opaque `Gfx`, a 16bpp 565 `DDSCAPS_SYSTEMMEMORY` offscreen and a px-only
  GDI `StretchDIBits` fallback. `std_ddraw_pal.zig:199-301` is the typed
  signature source only; `std_gfx_pal` `Lock`/`Unlock`/`BltFast` placeholders
  (`:455`/`:462`/`:437`) get typed. `GetPixelFormat` is typed and 565/555 is
  queried at open.
- **Native gate split.** `sf/src/std_gfx_px_core.zig` is pure (no Windows
  includes): Surface/fill/blit/LUT/clip/dirty merge/bar math/framebuffer dump.
  `sf/src/std_gfx_px.zig` is the thin `std_gfx_pal` wrapper. Art goldens are
  core dumps; `<windows.h>` never enters a native TU (M3 proved the PAL is
  unlinkable with `-osl`).
- **`under.exe` becomes playable (option A).** One window. Dock/map/node/
  journal/help keep the existing 80×30 `render_term` Screens and are
  cell-blitted via `std_gfx`; the fight presents the px surface on the same
  window; switching happens only at fight boundaries. `std_gfx` gains
  `gfxNativeState` and px gains `gfxPxAttach` so the cell window/clipper/pump
  is shared (no second window). New `input.keyFromEvent`,
  `render_term.blitToGfx`, `nav.navRunGfx`. Desktop <16bpp → all-cell fallback
  (logged).
- **G7 folded into `gfxPxOpen`** (fixed 640×480 client, no resize/scale);
  **G8 = `gfxPxPresent`**. Spec §23.1 adds `gfxPxOpenMemory`,
  `gfxPxDump`, `gfxPxPollEvent/WaitEvent`.
- **`under.exe --perf`** writes frame-timing percentiles to `errors.log` (M16
  evidence; never a gate).
- **M8's six art facts are binding in M9:** hidden `SPD ??` unless journal bit
  or active Sonar (shared reveal helper), full tool status line, mid-fight `?`
  help overlay (or documented terminal fallback), zero-max boss Resolve guard,
  art subdue modal, exported `msgLine` + parity test.
- **Allowlist delta only what is used** (`StretchDIBits`; `SetWindowLongA` only
  if the fixed-size path needs it) — recorded here when implemented and gated
  by `check_win9x_imports.sh`. **Recorded M9 Task 2 delta:** GDI32 adds
  `StretchDIBits` (24-bit DIB px fallback), USER32 adds `SetWindowLongA`
  (standalone px fixed-size frame) and `IsWindowVisible` (probe visibility
  evidence). No `CreateDIBSection` was needed: the DIB pixels are a fixed
  module buffer passed to `StretchDIBits`. The typed surface `GetSurfaceDesc`
  query is a COM vtable slot, not a PE import.
- **D24/D25:** new atlas/table data uses explicit `[N]T{...}` literals; no
  array-returning APIs. (`examples/torrent_example_defects.md` D24/D25).
- **Tier split:** native core/art/loop tests + `tier_edit.sh` (byte-identical)
  = gate; px probe, `tier_edit_gui.sh`, Wine runs = SLOW evidence, loud skip.

Task 0 records the M8/`tier_edit` baseline at the amended HEAD before code.

### M9 quality cut (P28)

The final two M9 tasks are the tech-debt cut before M10/M13 (user-authorized):

- **Task 8 — smell removal (mechanical):** ids only in `def.zig`; `items.zig`
  owns tool/material ownership/kind; `paths.join` + `text_scan.zig` own the
  path/text primitives; dead/alias layers removed; `tests/quality_smells.sh`
  (grep + LOC) runs in the tier. Golden-identical.
- **Task 9 — structural refactor:** compiled content fallback generated from
  `data.z98` (`undtool --emit-fallback` + byte-equal diff gate; M13 authors
  once); `render_text`/`fight_rules`/`fight_tools`/`data_scan`/`data_load`/
  `save_scan`/`save_io` splits; renderers stop importing
  dock/economy/save_ux/journal/data and consume a prepared view struct.
  Golden-identical; any golden drift = STOP.
- Deferred: test-harness consolidation; PAL de-duplication.
- Task 5 fix round (review Important): share `input.filterKey` with
  `loop_gfx` (10/13/space parity; raw for lore) and update the obsolete
  `tests/tier_m1_std.sh` SLOW `under.exe` evidence to launch → window check →
  kill (loud skip without Wine/Xvfb).

#### Baseline + facts

Baseline at HEAD `32e85ba4c05695d20f14ad9b01d5ac2ff2d5b71c` (branch
`undersanded/m9`), seed v151 compiler `/tmp/seed151_build/zig1_5_clean`
md5 `a2fc81055dc1cb7a67099fe3934d22ee`:

```
ZIG=/tmp/seed151_build/zig1_5_clean OUT=/tmp/m9_t0_m8 sh examples/z98/undersanded/tests/tier_m8_content.sh
-> TIER_M8 PASS 52 passed / 0 failed
ZIG=/tmp/seed151_build/zig1_5_clean OUT=/tmp/m9_t0_edit sh examples/z98/z9edit/tests/tier_edit.sh
-> TIER_EDIT PASS (== tier_edit summary: 38 passed, 0 failed ==)
   lexer md5 3x: dcc81009e9a36c86e4d90e104c439871 (run1 = run2 = run3)
   compile max RSS: 5848 KiB
```

Facts verified in this tree:

- **Opaque `Gfx`.** `std_gfx.zig:17-18` states the opaque contract; private
  `GfxState` at `:69-79`, public `Gfx = struct { opaque: *GfxState }` at `:81`.
  No cell buffer or raw COM pointer is app-reachable.
- **PAL surface placeholders.** In `std_gfx_pal.zig` the vtbl slots are still
  `extern "stdcall" fn() void` for `BltFast` (`:442`), `GetPixelFormat`
  (`:456`, placeholder), `Lock` (`:460`), `Unlock` (`:467`). Typed already:
  `Blt` (`:440`, returns `u32`) and `Restore` (`:462`,
  `fn(iface: *void) u32`). Public: `State` (`:564`), `open` (`:1078`),
  `waitEvent` (`:1663`), `pollEvent` (`:1694`).
- **No px format today.** `makeSurface` (`std_gfx_pal.zig:779-795`) sets only
  `DDSD_CAPS` for the primary (`:782-783`) and
  `DDSD_CAPS|DDSD_WIDTH|DDSD_HEIGHT` + `DDSCAPS_OFFSCREENPLAIN` for the
  offscreen (`:785-786`); the calls are `:1059-1061`. Format fields exist in
  `DdSurfaceDesc2` (`:333-340`) but `zeroDesc` leaves them zero (`:365-372`),
  and the constants cover only `DDSCAPS_PRIMARYSURFACE`/`OFFSCREENPLAIN`/
  `DDSD_CAPS|HEIGHT|WIDTH` (`:64-68`). The surface is 32-bit
  (`std_gfx.zig:8`; `std_gfx_pal.zig:6-8`). px needs its own 16bpp 565
  offscreen created with `DDSD_PIXELFORMAT` + `DDSCAPS_SYSTEMMEMORY`, plus a
  typed `GetPixelFormat` query at open.
- **Allowlist delta is exactly the used symbols.**
  `scripts/win32_cross/check_win9x_imports.sh:34` GDI32 ends
  `... SelectObject SetBkMode SetTextColor TextOutA`; `:35` USER32 ends
  `... SetWindowTextA ShowWindow TranslateMessage UnregisterClassA UpdateWindow`.
  Neither list contains `StretchDIBits` or `SetWindowLongA`; add each only
  when the px code actually imports it, and keep the script green.
- **`render_term` art facts** (art rendering must match):
  - Hidden Speed: `speedRevealed` (`render_term.zig:120-123`) is the journal
    bit for `fight.def_index` or active Sonar; the `SPD ??` branch
    (`:385-390`) prints `??` when false and calls `effectiveSpeed` only when
    revealed.
  - Full tool status: `renderToolStatus` (`:347-370`) draws
    `TOOL <name> <kind> charge N broken yes/no active yes/no`; called on row 6
    (`:396`).
  - Subdue modal: `renderFrame` early-returns to `renderModal` for
    `SCREEN_SUBDUE`/`SCREEN_SUBDUE_POST` (`:375-378`); copy/actions at
    `:323-336` (`SUBDUE ATTEMPT`, chance row, Last Surge copy,
    `[A]ttempt   [F] Fight on   [Esc] Cancel`).
  - Zero-max bar guard: `barFill` returns 0 when `max <= 0 or width <= 0`
    before dividing (`:125-133`, guard `:126`); keeps the boss `max_res = 0`
    case safe.
  - `msgLine` is private (`render_term.zig:174`); M9 must export/share it (or
    duplicate it byte-identically) for the art log and a parity test.
  - Mid-fight help overlay: `nav.zig:289-298` handles `?` on every screen
    (including mid-fight) and any key dismisses it; `drawCurrent` renders the
    page first (`:361-365`). Art mode draws the same overlay or documents the
    terminal fallback.
- **D24/D25 guard.** New atlas/table data uses explicit `[N]T{...}` literals;
  no array-returning APIs. Reference: `examples/torrent_example_defects.md`
  (D24/D25).
- **Art font:** `font8x16.zig` is the public-domain IBM VGA/MCGA ROM 8x16 font `VGA8.F16` (source URL and sha256 in the file header).

### M10 amendment review (M9 Task 7)

Read `2026-11-12-undersanded-m10-assets-pipeline-plan.md` against the landed
M9 interfaces (`sf/src/std_gfx_px_core.zig:21-27` `Sprite`, `:134-201`
`pxCoreBlit/BlitPart`, `:318-329` memory `gfxPxBlit/BlitPart`;
`render_art.zig`; `tests/px_test.zig:35` art golden; `tests/tier_m9_px.sh`)
and spec §23.1/§30/§35. Verdict: **amendment required**. The `.ZSP` header
already fits `Sprite` (`w/h u16 LE` widen to `u32`, `key u8`, one `ramp u8`)
and `pxCoreBlitPart` already does indexed→565 via `lut[]` with key skip, so M9
needs no code change. But M10 does not yet pin recolor derivation, the
manifest/recolor ledger, canonical-RLE re-encoding, the missing
`--validate-assets` hook, or the art-golden re-pin.

**1. Pin the recolor LUT API and ledger (blocking).** M10 says "ramp
assignment" but the decoder contract has no recolor path. Add to `zsp.zig`:

```zig
pub fn zspRecolorLut(out: *[256]u16, base: *const [256]u16,
                     from_ramp: u8, to_ramp: u8) void
```

Exact rule: copy `base` to `out`; require `from_ramp <= 15`, `to_ramp <= 15`,
`from_ramp != to_ramp`, and reject `from_ramp == 0` for creature recolors
(ramp 0 is the outline/UI ramp); for every `i < 255` with
`i >> 4 == from_ramp`, set `shade = i & 15` and
`out[i] = base[to_ramp * 16 + shade]`; when `to_ramp == 15 and shade == 15`
use `base[254]` because index 255 is the key (ramp 15 has only 15 usable
shades); always leave `out[255] = base[255]`. Recolor uses the same base
pixels: `Sprite{ .idx = base.idx, .lut = out, .w = base.w, .h = base.h,
.key = base.key }`, with one 512-byte LUT per loaded variant. No new `.ZSP`
per recolor.

`assets.man` must carry both asset and variant records (exact line forms):
`A <name8.3> <kind> <w> <h> <encoded_bytes> <allowed_ramps_csv>` and
`V <variant_id> <base8.3> <from_ramp> <to_ramp>`. `A.name8.3`, `V.base8.3`,
and the `F` name are checked as lowercase 8.3 (≤8-char base, ≤3-char
extension, no spaces); the full `A` list is exactly the 26 files `eel00
tuna00 crab00 jelly00 barn00 anem00 ray00 squid00 angler00 wrasse00 boss00
bg_a bg_b bg_c bg_d bg_dock boat00 fig_merm fig_angl fig_krak flag_pen
flag_ref flag_trn dec_barn dec_sqid dec_boss`, plus `F font8x16 95 16`.
`V.variant_id` is a symbolic id, not a filename. The validator must require
every `V.base8.3` to be an `A` row, `from_ramp` to equal that row's `.ZSP`
header ramp, every demo def to have exactly one mapping (base defs map to
their `A` row, recolors to their `V` row), and no orphan/duplicate variants.

Pin the actual mapping (def id -> base, from -> to); base defs are identity
rows and get no `V`: id1->eel00, id4->tuna00, id7->crab00, id8->jelly00,
id9->barn00, id10->anem00, id13->ray00, id14->squid00, id15->angler00,
id16->wrasse00, id17->boss00 (Armor, see below). The six non-flex recolors:
id2 eel00 6->1 (Mystic Electric Eel), id3 eel00 6->5 (Mileel), id5 tuna00
7->14 (Rust Tuna), id6 tuna00 7->10 (Tunisteel), id11 crab00 8->11 (Coral
Crab), id12 jelly00 9->5 (Abyssal Lantern-Jelly). Flex recolors: id18 anem00
11->5 (Anemoniacus), id19 tuna00 7->1 (Freezing Perch, icy). Base ramps from
§30: eel00=6, tuna00=7, crab00=8, jelly00=9, barn00=10, anem00=11, ray00=12,
squid00=13, angler00=14, wrasse00=15.

Boss identity contract (option A: Armor = base, no `V` row). `boss00`
header.ramp = 10 (Armor); `id=17` maps directly to `A boss00` and has no `V`
row. Four non-identity boss `V` rows use `base8.3=boss00`, `from_ramp=10`:
`boss00:sliver 10->2`, `boss00:hoard 10->4`, `boss00:drown 10->13`,
`boss00:blur 10->5`. Thus the boss has five identities (base/Armor + four
`V` rows), all `from_ramp != to_ramp`; the validator must not create an
identity `V` row for id=17 or Armor.

Boat paint uses the same helper, not a new asset: re-blit `boat00.idx` with a
paint LUT (`from_ramp` = hull ramp, `to_ramp` = cosmetic paint ramp) clipped
to the authored hull rect via `pxCoreBlitPart`/`gfxPxBlitPart`; record the
hull rect in NOTES. M11's `base → paint → decal → figurehead → flag` order
then needs no new pixel data.

**2. Make canonical RLE an actual check.** M10 Task 1 currently checks only
"counts 1–255 within bounds"; that accepts non-canonical runs and lets
byte-exact goldens drift. Add `zspCanonicalEncode(pix, w, h, out) usize` (one
run per maximal stretch; for a stretch >255 emit greedy 255-byte runs, then
the remainder 1..255) and have `validateAsset` re-encode the decoded pixels
and byte-compare the data section. The decoder golden and regeneration recipe
then share one canonical rule.

**3. Fix decoder/validator sequencing and pin the output contract.** The
decode golden belongs to Task 2's `zsp.zig` unit test; File Structure line 23
also gives `validate_assets.zig` a "decode golden compare", but Task 1
precedes Task 2. Move `zsp.zig` before `validate_assets.zig` or move that
check to Task 2; `validate_assets.zig` must import the one decoder, never
duplicate it. Pin: success sets `sprite.w/h` from the header, `sprite.idx = pix.ptr`,
`sprite.lut = out_lut.ptr`, `sprite.key = header.key`,
`pix_len.* = w*h`; requires `pix.len >= w*h`; fills all 256 `u16` from the
512-byte embedded palette (`flags == 0`, `reserved == 0`); on any failure
returns false without writing outside `pix`. Caller/arena owns both `pix` and
`out_lut`; the decoder never allocates.

**4. Add the missing `--validate-assets` hook; no `--emit-*` now.** This tree
has no such dispatcher case (`undtool.zig:416-` parses only
`--sim/--replay/--test-rules/--dump-grid/--dump-defs/--save-roundtrip/
--play/--fight/--screen/--creature/--seed/--hull`). M10 must add
`--validate-assets <manifest> [assets_dir]` to `undtool.zig` (exit 0 valid,
2 usage/invalid as existing `fail`) and list `undtool.zig` in the M10 file
structure; `undtool_native.zig` already forwards. No `--emit-*` is needed by
M10: `--emit-fallback` is the unlanded M9 Task 9 content hook, not assets.

**5. Re-pin the art golden once.** `art_fight.golden` is the M9 stand-in
checksum (`px_test.zig:35`), so M10 Task 4's sprite wiring necessarily changes
it. Regenerate it exactly once with the same `goldenFight` fixture (seed 98,
def 0) in that commit, update the `tier_m9_px.sh:12/:287` "never regenerated"
comments to say M10 re-pinned it, and have M10 Task 5 assert the art golden
plus M8/M9 terminal `--dump-grid` goldens byte-identical. Otherwise M10 turns
the M9 tier red. Keep `render_art` pure: load `assets/out/*.zsp` through a
small file/arena loader (new `assets.zig`, or equivalent) and pass decoded
`Sprite`s in; no file I/O in `render_art`.

**6. Manifest/font and budget accounting.** `font8x16` is landed compiled code
(`font8x16.zig`, 95×16 = 1,520 bytes), not a `.ZSP`; either drop it from
`assets.man` or add an explicit non-`.ZSP` `F font8x16 95 16` record and
never expect `font8x16.zsp`. Compute the gate from the manifest: indexed
bytes = sum of `w*h` over distinct `A` `.ZSP` rows (recolors and boss ramps
must not multiply base pixels), LUT bytes = 512 × `A` rows + 512 × `V` rows.
Gates: indexed ≤1.35 MB; indexed + LUTs ≤2 MB sprite arena (§35); each
background encoded ≤120 KB; demo RLE disk ≤400 KB (spec §35's 300–400 KB
range, not the plan's "≈300 KB").

### M9 Task 8 ownership map (P28)

Mechanical smell cut; all M1–M9 goldens stay byte-identical.

- **IDs:** `NAV_*`, `SCREEN_*` (including `SCREEN_W/H`), `MSG_*`, `OUT_*`,
  `TOOL_*` (ids and kinds), `UNLOCK_*`, `NO_FIGHT` live only in `def.zig`.
  Consumers spell `def.<ID>`; no aliases or duplicates remain.
- **Tools:** `items.zig` owns `toolKind`, `isRigged`, `isActivated`,
  `toolOwned` (owned-bit keyed by tool id). `tools.zig` keeps its public API
  and delegates; `dock.zig`, `expedition.zig`, `render_term.zig`, and tests
  consume `items`.
- **Paths/text:** `paths.join(dir,name,out)` is the one platform-separator
  join for saves/config (`persist.zig`, `save_ux.zig`); `paths.pathJoin83`
  stays for 8.3 asset names. `text_scan.zig` owns `stripCR`, `trimSpaces`,
  `findEq`, `appendText`, `appendInt`, `appendUint`; `data.zig`,
  `persist.zig` (Buf wrappers only format digits via `text_scan`),
  `save_ux.zig`, `nav.zig`, `perf.zig`, and `undtool.zig` consume them.
- **Allowed dependency direction:** domain/logic modules (def, world, fight,
  expedition, dock, items, tools, data, persist, text_scan, paths) never
  import render modules. Renderers (`render_term`, `render_art`, `loop_gfx`)
  may import domain modules. IDs flow one way from `def`.
- **Content source:** `data.z98` remains the authored content source; Task 9
  owns generating the compiled-in fallback and any split/decoupling.
- **Gate:** `tests/quality_smells.sh` (grep + LOC, shell only) runs as a
  required case in `tests/tier_m9_px.sh`.

### M9 Task 9 phase 1: generated fallback + module splits

Behaviour-preserving structural cut; all M1–M9 goldens stay byte-identical.

- **Content single source:** `undtool --emit-fallback <outdir>` loads
  `data.z98` and writes `<outdir>/fallback_rows.zig` (deterministic; no
  timestamps). The checked-in `fallback_rows.zig` is that output;
  `creatures_t1.zig` and `tables_t1.zig` consume it and keep their public API
  (`DEFS`, `defAt`, `defCount`, `rules`, `rows`, `tools`, `upgrades`,
  `cosmetics`, `zoneCost`, `zoneIsBoss`, override behavior). `tests/tier_m9_px.sh`
  regenerates twice, proves determinism, and `cmp`s against the checked-in file.
- **Splits:** `render_text.zig` owns the cell canvas + log/tool/modal/help copy
  (render_term and render_art import it); `fight_rules.zig` + `fight_tools.zig`
  own derived-stat/effect math and equipped-tool predicates; `data_scan.zig` +
  `data_load.zig` split the scanner and loader (`data.zig` is the hub);
  `save_scan.zig` + `save_io.zig` split the read path and image builder
  (`persist.zig` is the hub and keeps the `fs_*` seams).
- **Z98 note:** aliases to functions (`pub const f = sub.f`) emit invalid C
  globals in this compiler, so hubs use thin forwarding wrappers; constants and
  array values still alias directly. Array sizes in `data_scan` use `ROW_MAX`
  (D27); this compiler is import-order sensitive, so keep nav's `data` import
  before `render_term`.

## M10 preflight (P29 rulings applied)

- **Palette contract:** anchors at shade indices **0/5/10/15**; linear 8-bit
  interpolation with integer round-to-nearest; RGB565 round-to-nearest. Index
  255 is the key, so ramp 15 has 15 usable shades; recolor `15/15` uses
  `base[254]`.
- **Boss:** `boss00` is re-authored at **96×96** with header ramp **10**
  (Armor). `id=17` maps to `A boss00` with no V row; four boss V rows are
  `10→2` (sliver), `10→4` (hoard), `10→13` (drown), `10→5` (blur). The
  available 160×160 ramp-14 boss SVG is not the M10 source; do not copy it.
- **Manifest:** exactly 26 A files + 12 V rows + `F font8x16 95 16`; A is the
  only indexed-byte source, V adds a 512-byte LUT. The exact A/V ledger and
  allowed ramps are in the M10 plan Global Constraints.
- **Scope:** M10 wires creature sprites + one resident zone background into the
  art fight and re-pins `art_fight.golden` once. Boat render, overlays, and the
  score screen stay M11. `font8x16.zig` already exists (M9); verify provenance,
  do not re-import.
- **Order:** `zsp.zig` (decoder + `zspRecolorLut` + `zspCanonicalEncode`)
  lands before `validate_assets.zig`; the validator re-encodes and byte-compares,
  checks embedded palette equality, exact A/V/F ledger, per-asset allowed
  ramps, and def→base/V coverage.
- **Budget:** indexed (distinct A rows) ≤1.35 MB; indexed+LUTs ≤2 MB; each
  background encoded ≤120 KB; demo RLE disk ≤400 KB.

### M10 Task 0 preflight — expected A table, ledger, budgets

Baseline at `7c2d6901` (branch `undersanded/m10`): `TIER_M9 PASS 67/0`
(1 Wine evidence skip), log `/tmp/m10_base.log`. Task 0 changes only this file
and creates the empty `assets/` + `assets/out/` skeletons; no product code, no
plan/spec edit, no side fix.

**Palette contract (P29, unchanged).** Each ramp anchors at shade indices
**0/5/10/15** (Dark/Mid/Light/Hi). Intermediate shades are 8-bit linear
interpolation with integer round-to-nearest:
`c(i) = (c0*(a1-i) + c1*(i-a0) + (a1-a0)/2) / (a1-a0)`. RGB565 uses
round-to-nearest: `r5=(r*31+127)/255`, `g6=(g*63+127)/255`,
`b5=(b*31+127)/255`. Index **255 is the transparent key**, not ramp-15
shade-15; ramp 15 has 15 usable shades, recolor `to_ramp==15 && shade==15`
uses `base[254]`, and `out[255] = base[255]` always.

**Boss contract.** `boss00` is **96×96** with header ramp **10** (Armor);
`id=17` maps directly to `A boss00` with **no** V row. Four boss V rows use
`base8.3=boss00`, `from_ramp=10`: `boss00:sliver 10->2`,
`boss00:hoard 10->4`, `boss00:drown 10->13`, `boss00:blur 10->5`. There is no
identity boss V row. The available 160×160 ramp-14 boss SVG is **not** the M10
source and must not be copied.

**Expected A table (validator `AssetSpec`).** These values are hardcoded in
`validate_assets.zig`; the manifest is never trusted for them. `kind` tokens
pinned for Tasks 2/3 are `creature`, `bg`, `boat`, `overlay`.
`allowed_ramps_csv` is decimal ramp indices, comma-separated, no spaces; it is
the union of ramps used by the source fills plus the mandatory stage-5
ramp-0/shade-0 outline for alpha sprites (backgrounds are opaque and get no
outline). Source fills came from the read-only ignored document
`/workspace/znineeight/examples/undersanded_assets.txt` (not added or committed).

| A name | kind | w | h | allowed_ramps_csv |
| :--- | :--- | --: | --: | :--- |
| `eel00` | creature | 96 | 96 | `0,6` |
| `tuna00` | creature | 96 | 96 | `0,7` |
| `crab00` | creature | 96 | 96 | `0,5,8` |
| `jelly00` | creature | 96 | 96 | `0,5,9` |
| `barn00` | creature | 96 | 96 | `0,10` |
| `anem00` | creature | 96 | 96 | `0,4,11` |
| `ray00` | creature | 96 | 96 | `0,3,12` |
| `squid00` | creature | 96 | 96 | `0,13` |
| `angler00` | creature | 96 | 96 | `0,4,9,14` |
| `wrasse00` | creature | 96 | 96 | `0,15` |
| `boss00` | creature | 96 | 96 | `0,2,4,10` |
| `bg_a` | bg | 640 | 300 | `0,1,14` |
| `bg_b` | bg | 640 | 300 | `0,1,6,8,14` |
| `bg_c` | bg | 640 | 300 | `0,1,3,5,6,10,15` |
| `bg_d` | bg | 640 | 300 | `2,4,10,14` |
| `bg_dock` | bg | 640 | 300 | `0,1,2,4,10,14` |
| `boat00` | boat | 200 | 150 | `0,1,10` |
| `fig_merm` | overlay | 64 | 64 | `0,14` |
| `fig_angl` | overlay | 64 | 64 | `0,4,14` |
| `fig_krak` | overlay | 64 | 64 | `0,4` |
| `flag_pen` | overlay | 64 | 64 | `0,9,14` |
| `flag_ref` | overlay | 64 | 64 | `0,5,8,14` |
| `flag_trn` | overlay | 64 | 64 | `0,6,10` |
| `dec_barn` | overlay | 64 | 64 | `0,10` |
| `dec_sqid` | overlay | 64 | 64 | `0,13` |
| `dec_boss` | overlay | 64 | 64 | `0,2,14` |

Notes on the derivation (Task 3 must author/verify per §30; Task 0 does not
change source art):

- `boss00` is the required 96×96 ramp-10 re-authoring: the ramp-14 body fills
  become ramp 10, the sensor eye stays ramp 2, the amber lamps stay ramp 4, and
  outline stays ramp 0. Do not carry ramp 14 into the asset.
- `dec_barn` (`#A8B2BA`, `#3A4248`) and `dec_sqid` (`#CCE4F4`, `#44607A`) have
  no source stroke; ramp 0 is allowed for the uniform stage-5 outline.
- `bg_d` uses only ramps 2/4/10/14; it has no ramp-0 fill, so ramp 0 is not in
  its allowed set.
- Source-vs-plan deviations to resolve in Task 3 (recorded, not fixed here):
  `bg_dock.svg` is authored 640×480 with 17 unique colours while the plan/spec
  require 640×300 / ≤8 colours; `bg_b.svg` has 10 colours and `bg_c.svg` has 9
  (both must drop to ≤8); `boat00.svg` uses `#D8E2EA`, which is not a locked
  palette hex (ramp-0 hi is `#9AAABA`), so it must snap to a locked ramp-0
  shade; `boat00.svg` portholes are `<circle>` and must become 16/12/8-sided
  polygons. The allowed sets above are safe supersets for those corrections.
- **Source key-colour collision (must fix in Task 3).** `wrasse00` source
  fills/eyes and the `bg_c` glow rectangles use `#6AE0C0`, which is ramp-15 Hi
  = shade 15 = index 255 = the transparency key. The validator's "allowed
  ramps ∪ key" rule cannot catch an opaque key-coloured source fill. Remap or
  re-author those pixels to a non-key shade (shade <=14; recolor `15/15` uses
  `base[254]`). The allowed ramp sets are unchanged.

**A/V/F ledger (binding).**

- A rows: exactly the 26 names in the table above (11 creature bases, 5 demo
  backgrounds, `boat00`, 9 cosmetic overlays).
- V rows: exactly 12. Non-flex: `id2 eel00 6->1`, `id3 eel00 6->5`,
  `id5 tuna00 7->14`, `id6 tuna00 7->10`, `id11 crab00 8->11`,
  `id12 jelly00 9->5`. Flex: `id18 anem00 11->5`, `id19 tuna00 7->1`.
  Boss: `boss00:sliver 10->2`, `boss00:hoard 10->4`, `boss00:drown 10->13`,
  `boss00:blur 10->5`.
- F row: `F font8x16 95 16` (not a `.ZSP`; never expect `font8x16.zsp`).
- Base identity rows (no V): `id1->eel00`, `id4->tuna00`, `id7->crab00`,
  `id8->jelly00`, `id9->barn00`, `id10->anem00`, `id13->ray00`,
  `id14->squid00`, `id15->angler00`, `id16->wrasse00`, `id17->boss00`.
- Every demo def has exactly one mapping (identity A or one V); every V base is
  an A row; `from_ramp` equals the base `.ZSP` header ramp; no orphan or
  duplicate V. `A` is the only indexed-byte source; each `V` adds only a
  512-byte LUT.

**Budgets (binding).** Indexed bytes = `sum(w*h)` over distinct A rows
(recolors/boss V rows never multiply base pixels). With the table dimensions:
11×96×96 = 101,376; 5×640×300 = 960,000; 200×150 = 30,000; 9×64×64 = 36,864;
total **1,128,240 B (~1.08 MiB) ≤ 1.35 MB**. LUT bytes = 512×(26 A + 12 V) =
**19,456 B**; indexed + LUTs = **1,147,696 B (~1.09 MiB) ≤ 2 MB** sprite
arena. Each background encoded ≤120 KB; demo RLE disk ≤400 KB; both measured
after Task 3 conversion. (For reference, §35's roll-up adds font 12 KB and UI
chrome 60 KB to reach ~1.2 MB indexed + ~6 KB of V LUTs.)

**P19 — no committed tooling outside Z98 + shell.** The SVG→`.ZSP` converter is
transitory and uncommitted; it never enters the repo and is never a build/test
dependency. Artifacts of record are the SVG sources, the `.ZSP` files, and
`assets.man`; CI's only asset gate is the committed Z98
`undtool --validate-assets`.

**Regeneration recipe (stub; one paragraph, incl. canonical RLE rule).**
Rasterize each SVG at its declared target size 1:1 with `rsvg-convert` (no
resampling), composite on ramp-0 shade-0 and map `alpha<128` to index 255,
enforce the 1px ramp-0/shade-0 outline around the alpha mask, assert every
pixel is inside the asset's allowed ramps ∪ key, then encode canonical RLE —
one run per maximal stretch, count 1..255, greedy 255 split for longer
stretches — into the `.ZSP` header (`ZSP1`, w/h u16 LE, key u8, ramp u8,
flags=0, reserved=0) + 512-byte RGB565 palette + data runs. The converter is a
throwaway host script; `undtool --validate-assets` re-decodes, re-encodes and
byte-compares the data section, so the canonical rule is the single contract.

**Font verification (do not re-import).** `font8x16.zig` is landed and
verified: `GLYPH_COUNT = 95`, `GLYPHS = [95][16]u8` (95 glyph rows, each
exactly 16 bytes), ASCII 32..126, 8×16, MSB-left. Provenance recorded in its
header: IBM VGA/MCGA ROM 8×16 font, file `VGA8.F16` from VileR's public-domain
VGA text-mode font collection (`FONTS/PC-IBM/VGA8.F16`), URL
`https://raw.githubusercontent.com/viler-int10h/vga-text-mode-fonts/master/FONTS/PC-IBM/VGA8.F16`,
sha256 `a8bad6fd78475a6bc2a05438c19207a9bb8c0f4f4099f60384e158cdc3eba580`.
No font was generated or re-imported in M10.

**Scope.** M10 wires creature sprites + one resident zone background into the
art fight (backgrounds are wired in M10). Boat render, cosmetic overlays, and
the score screen stay **M11**; `boat00` is authored/validated in M10 but not
rendered. `render_art` stays pure (no file I/O). `art_fight.golden` is re-pinned
exactly once in Task 4 and the M9 tier comment is updated to say M10 re-pinned
it; terminal/M8/M9 `--dump-grid` goldens stay byte-identical.

**Skeletons.** `assets/` (SVG sources) and `assets/out/` (`.ZSP` outputs) are
created empty in this task; contents land in Task 3.

### M10 Task 3 — demo art set, corrections, style sign-off

**Artifacts.** `assets/` now holds all 26 authored SVG sources; `assets/out/`
holds the 26 matching `.zsp` files; `assets/assets.man` is the exact 26 A +
12 V + `F font8x16 95 16` ledger. No converter, script, or `.py` file is
committed (P19).

**Conversion provenance (transitory, uncommitted).** `rsvg-convert` was not
available, so the host used ImageMagick 6 `convert -background none +antialias`
with raw RGBA output at each SVG's declared 1:1 size (no resampling). The
throwaway script lived only in `/tmp`; it mapped `alpha<128` to index 255,
enforced the 1px ramp-0/shade-0 outline on every alpha sprite's mask, asserted
every non-key pixel was inside that asset's allowed ramps, and wrote canonical
RLE (one run per maximal stretch, 1..255, greedy 255 split) into `ZSP1` +
16-byte header + 512-byte RGB565 palette + runs. `+antialias` produced only
exact palette colours (binary alpha), so no blend/fringe pixels reached the
encoder. `undtool --validate-assets` re-decoded, re-encoded and byte-compared
the result: exit 0.

**Source corrections applied.** `boss00` is a fresh 96×96 ramp-10 re-authoring
(outline 0, body 10, sensor eye 2, lamps 4; the 160×160 ramp-14 source was not
used). `bg_dock` is re-authored at 640×300 with 7 colours. `bg_b` drops to 8
colours (the extra ramp-6 band merges into ramp 1; ramp-8 highlights replace
the ramp-8 Hi speckles). `bg_c` drops to 8 colours and its `#6AE0C0` glow
rectangles become `#5DD5B5` (ramp-15 shade 14, non-key). `wrasse00`
fills/eyes likewise move from key `#6AE0C0` to `#5DD5B5`. `boat00` snaps the
off-palette `#D8E2EA` highlight to ramp-0 Hi `#9AAABA` and replaces the three
porthole circles with 16/12/8-sided polygons.

**Side-by-side style sign-off.** The 11 bases were reviewed together as one
set (decoded `.zsp` pixels, six per row): eel00, tuna00, crab00, jelly00,
barn00, anem00, then ray00, squid00, angler00, wrasse00, boss00. They share the
same 1px ramp-0 silhouette weight, flat banded shading, centred 96×96 mass,
and a consistent eye/feature scale; the gray ramp-10 Armor boss reads as the
same set while staying distinct from the ten coloured bases. No base was
regenerated; style set **signed off**.

**Budgets (measured after conversion).** Indexed = 1,128,240 B; LUTs =
512×(26+12) = 19,456 B; indexed + LUTs = 1,147,696 B ≤ 2 MB. Each background
encoded ≤ 6,044 B (bg_d) ≤ 120 KB. All 26 A files total 62,956 B encoded
≤ 400 KB. Validator rc 0 on the real manifest + `assets/out`.

### M11 amendment review (M10 Task 6)

Reviewed `2026-11-12-undersanded-m11-boss-score-plan.md` at `4e2c6a4a`
against the M10 artifacts and spec §15/§19/§30. Verdict: **no design
amendment needed**; the plan's boss/boat/score ownership matches the landed
M10 split. The plan-text clarifications are recorded below.

**Boss contract confirmed.** `assets/out/boss00.zsp` header is **96×96**,
key 255, ramp **10**; `assets/assets.man` has
`A boss00 creature 96 96 2250 0,2,4,10`, and exactly four boss V rows:
`boss00:sliver 10->2`, `boss00:hoard 10->4`, `boss00:drown 10->13`,
`boss00:blur 10->5`. There is no boss identity V row: `id17` maps to
`A boss00` (Armor) directly. The five identities are therefore base/Armor
plus the four V recolors, not five V rows. `validate_assets.zig` pins the
same ledger, and `assets.zig` decodes the base plus all four boss LUTs into
the asset arena.

**A/V manifest availability.** `assets.man` is committed with the exact
26 A + 12 V + `F font8x16 95 16` ledger. All M11-consumed names/ramps are
present: `boss00` (ramp 10), its four V rows, `boat00` (200×150, header
ramp 1, allowed `0,1,10`), and the nine 64×64 cosmetic overlays
(`fig_merm`, `fig_angl`, `fig_krak`, `flag_pen`, `flag_ref`, `flag_trn`,
`dec_barn`, `dec_sqid`, `dec_boss`). `assets.zig`'s `A_NAMES` pins the
same order. M11 should note the loader currently exposes `spriteForDef`
only; boss V rows have symbolic ids (`var_def_ids = -1`), so
`spriteForDef(17)` always returns Armor. M11 needs a variant/overlay lookup
(an `assets.zig` addition) or must use the pinned V order; this is M11
implementation work, not an M10 data gap.

**Boat/score ownership confirmed.** `assets/out/boat00.zsp` and the nine
overlay `.zsp` files are committed and validated. M10 wires only creature
sprites plus the resident zone background: `render_art.ArtAssets` carries
only `bg`/`sprite`, `loop_gfx.artView` only calls `ensureBackgroundZone` +
`spriteForDef`, and `boss.zig`/`score.zig` do not exist yet. Boat render,
the blit order (base -> paint ramp -> decal -> figurehead -> flag), the
overlays, the boss screen, and the three-panel score/Field Record remain
M11-owned.

**M11 plan text: stale/contradictory, no design change.**

- The plan's "`boss00` sprite × 5 ramp recolors" and "boss screen (5 ramp
  recolors)" are realized by the base/Armor row plus four V rows (above).
  Treat Armor as the identity base, not a fifth V row.
- The architecture line says `boss_variants_seen`, `boss_kills`, and
  `runReset` are "persisted via M7". `boss_variants_seen`/`boss_kills` (and
  the Field Record/Last Run rows) are persisted by M7 (`save_io.zig`/
  `save_scan.zig`); `runReset` is an M5 `world.zig` function, not a saved
  field. M11 Task 0 already states the correct `runReset` check.
- M11's File Structure lists `boss.zig`, `score.zig`, `render_art.zig`,
  `render_term.zig`, tests/goldens but not `assets.zig`; the boss-variant
  lookup above will need that file (or an equivalent). File-list addition
  only.
- Tiebreak reminder (not a contradiction): `World.boat` indices are H=0,
  S=1, C=2, O=3, P=4 (`world.zig`), while the required variant tiebreak is
  H>P>C>O>S. M11's pinned helper must encode the tiebreak order explicitly,
  not scan `boat[0..4]` or max the array.

Task 0's existing-state checks are already true in the committed tree:
`data.z98` id17 has `subdue_chance=-1`, HP 300, Speed 7, Attack 10, and
respawn kill/overkill 20/40; `def.World` already carries
`boss_variants_seen`, `boss_kills`, `field_record_written`, `field_record`,
and `last_run`.
