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

- **W1 deferred-fix re-pin:** decline now logs the plain copy
  (`MSG_DECLINE_PLAIN`, "The creature recovers its footing.") unless a coupling
  regen is active (`MSG_DECLINE` keeps the recovering-will wording); the
  `--dump-grid` golden was re-pinned for the pinned `DUMP_SEED=98`; rare
  actions report per-mille (`rare_actions_pm`). No assertion was weakened.

| Creature | token | actions | rare actions (pm) | ascent % | switches % | prompts |
| :--- | :--- | ---: | ---: | ---: | ---: | ---: |
| Mystic Eel | `eel` | 8 | 0 | 0.0 | 100 | 0 |
| Mystic Electric Eel | `electric_eel` | 10 | 0 | 0.0 | 100 | 0 |
| Steel Tuna | `steel_tuna` | 11 | 0 | 0.0 | 100 | 0 |
| Anemoniacus | `anemoniacus` | 11 | 11525 | 4.0 | 100 | 292 |
| Freezing Perch | `freezing_perch` | 5 | 5385 | 1.5 | 25 | 73 |

- Rare-fight actions `≤12000pm`: PASS (Anemoniacus 11525pm, Freezing Perch 5385pm).
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
  Anemoniacus **8.5% (85 pm, seed 4)**, Freezing Perch **4.0% (40 pm, seed
  100)**. Recorded, not tuned.
  tuned further.

### M3 -> M4 amendment review (Task 6)

Read `2026-11-12-undersanded-m04-expedition-loop-plan.md` against the
shipped M3 sim surfaces. Verdict: **no amendment needed** — the M3 report is
per-creature fight metrics with no World/availability/rare-pipeline input, so
M4's World and encounter work is validated by M4's own `world_test`/
`encounter_test` (M4 plan Tasks 1–2) without a per-zone report shape.

- **Hull-0 is not an outcome.** `fight.zig` clamps `hull` at 0
  (`fight.zig:482-485`, `:296-297`) and `def.OUT_*` has no ascent value
  (`def.zig:114-119`); `sim.zig:117-120` stops the loop at `hull == 0` and
  counts `ascents` (`sim.zig:129-130`). M4 owns termination, the +1 phase and
  dropping current-fight loot (spec §6); do not expect the fight resolver to
  end the fight at Hull 0.
- **Seed convention.** `fight.startFightDef` seeds each fight from
  `exp.seed + fight_index*77` with three warm-up draws (`fight.zig:155-158`;
  spec:1173,1186). M4 `depart` must draw `exp.seed` from `world.rng_state`
  (M4 plan:56; spec:1186) and set `exp.fight_index` per fight; the sim bypasses
  Depart and sets `exp.seed = seed0`, `exp.fight_index = i` directly
  (`sim.zig:99-101`).
- **`--hull` is sim-only.** `undtool` defaults Hull to 100 and overrides it per
  sim fight (`undtool.zig:249`, `:315-323`; `sim.zig:102-103`); the gate uses
  150 (spec:1249). M4's real Hull is persistent fight/boat state (spec §6,
  spec:1249), not the tool flag.
- **Dense `DEFS` index vs `id`.** `creatures.DEFS` is a 5-element array indexed
  0..4 (`creatures_t1.zig:193-210`; `undtool.zig:32-42`), while
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
  Eel, Steel Tuna, Anemoniacus, Freezing Perch (`creatures_t1.zig:193-200`),
  but spec §13 Z1–Z3 names additional creatures (Rust Tuna, Kelp Crab, Spark
  Anemone, …; spec:536-578) with no defs yet. M4 must stub/restrict those
  pools until content arrives (M4 plan:51 stubs Z4–Z8/D).
- **M3 report shape is independent.** `SimReport` aggregates one `CreatureDef`
  (`sim.zig:28-41`, `:86-144`), the §25.9 policy reads only fight state
  (`sim.zig:68-84`), and the header/`sim creature=` line are tooling output
  (`undtool.zig:64-90`, `:391`). Availability, rare-chance arithmetic,
  renormalization and empty-pool Rest belong to M4 unit tests; per-zone sim
  runs would only re-partition the same fight metrics.
- **R8 note.** The sim is safe with `var s: GameState = undefined` because
  `fight.startFightDef` reads only the seed fields of `exp` and never touches
  `world` (`sim.zig:98-103`; `fight.zig:112-158`); M4's World/expedition path
  must explicitly initialize `GameState.world` (R8, spec §24).

