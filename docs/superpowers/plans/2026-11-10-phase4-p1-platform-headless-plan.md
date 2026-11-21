# Phase 4 P1 — Platform Abstraction and Headless Backend Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Create `examples/z98/z9gb`, the backend table, the deterministic headless backend, the `Emu` facade, and the RSS/framebuffer test harness. No emulator logic yet.

**Architecture:** A five-field `Platform` table isolates presentation/input/audio. The headless backend is pure Z98 and imports no Win32. `Emu` owns fixed framebuffer/state storage and exposes `emuRunFrame`; P1 fills it with a deterministic self-test pattern, not emulation.

**Tech Stack:** Z98 only; `std.os`/`std.io`/`std.file`/`std.time`; POSIX shell test tiers; `/usr/bin/time` for RSS when present.

**Spec:** `docs/superpowers/specs/2026-11-10-phase4-project1-gameboy-design.md`

## Global Constraints

- Pure Z98: no `@cImport`, `asm`, intrinsics, C macros, generics, methods, `anytype`, or `@alignCast`.
- The headless backend imports no Win32 and no DirectX header.
- `Emu` and all large buffers are static/global; no heap allocation in P1.
- 1 MiB stack is a stack limit only. ROM, framebuffer, audio, and code cache are separate regions.
- 1 MiB code cache is not part of P1.
- `examples/z98/z9gb/main.zig` makes the directory a corpus entry; it must dump and gcc clean.
- No `scripts/stdlib/expected_dirs.txt` entry for the example directory.
- External ROMs are never committed. Missing assets are `SKIP`, never `PASS`.
- Test runs are sequential; spill files collide in one CWD.
- No seed rotation in P1; P1 changes no `sf/src` file.

## Review Focus

1. The headless backend must not import Win32 or DirectX and must build on Linux.
2. The `Platform` table must not leak HWND/COM/Win32 types; `*void` is opaque only.
3. Deterministic framebuffer bytes: same input, same 160x144 RGB32 output, every run.
4. Large buffers must be static/global, not stack locals; 1 MiB stack is respected.
5. Corpus entry resolution and example-matrix accounting must stay truthful.

---

### Task 0: Feasibility probes (no commits)

**Files:**
- Temporary only: `/tmp/phase4_p1_probe/*`
- Read: `sf/src/std_os.zig`, `sf/src/std_file.zig`, `examples/z98/gfx_demo/main.zig`

**Interfaces:**
- Consumes: none.
- Produces: confirmed build and measurement facts; no repository file.

- [ ] **Step 1: Confirm compiler and lib**
Run `ZIG1=${ZIG1:-/tmp/z9gb_seed/zig1_5_clean}` and `"$ZIG1" --help`; confirm a seed-built compiler runs. Expected: usage/banner, exit 0; no lib error. (`--version` does not exist; `sf/src/main.zig` has no such flag.)
- [ ] **Step 2: Probe static large buffers**
Compile a temporary Z98 program with a module-scope `var rom: [8 * 1024 * 1024]u8 = undefined;` and a `[160 * 144]u32` framebuffer. Expected: dump and gcc build clean; runnable; RSS printed.
- [ ] **Step 3: Probe RSS tool**
Run `/usr/bin/time -f '%M' -o /tmp/phase4_p1_probe/rss true`. Expected: file contains a number. If `/usr/bin/time` is absent, record that the RSS tier must emit `SKIP`.
- [ ] **Step 4: Probe example corpus entry**
Run `bash scripts/corpus/list_corpus_dirs.sh | grep 'examples/z98/z9gb'`. Expected: absent now. The rule (`scripts/corpus/list_corpus_dirs.sh`) resolves a depth-1 entry file (`main.zig` or `<basename>.zig`), so `z9gb` enters the corpus only once `main.zig` exists — i.e. after Task 2, not after Task 1. Expected after Task 2: exactly one line.
- [ ] **Step 5: Record findings**
Write probe outputs into the task report. If a probe fails, STOP and present it before Task 1.

---

### Task 1: Create the backend table and headless backend

**Files:**
- Create: `examples/z98/z9gb/platform/backend.zig`
- Create: `examples/z98/z9gb/platform/headless.zig`
- Create: `examples/z98/z9gb/testdata/.gitignore`
- Test: `examples/z98/z9gb/tests/tier_smoke.sh`

**Interfaces:**
- Consumes: none.
- Produces:
  - `pub const InputState = struct { buttons: u8, quit: bool };`
  - `pub const Platform = struct { state: *void, open_fn: fn (*void, u32, u32, u32) bool, present_fn: fn (*void, []const u32) void, poll_fn: fn (*void, *InputState) bool, audio_fn: fn (*void, []const i16) void, close_fn: fn (*void) void };`
  - `pub fn platformHeadless() *Platform;`

- [ ] **Step 1: Write the failing test**
Create `tests/tier_smoke.sh` that builds `main.zig` once it exists; for this step it only checks that `platform/backend.zig` and `platform/headless.zig` appear in the dump. Expected: fails because the files do not exist.
- [ ] **Step 2: Run it**
Run `bash examples/z98/z9gb/tests/tier_smoke.sh "$ZIG1"`. Expected: FAIL, missing file.
- [ ] **Step 3: Implement the table and backend**
Create `platform/backend.zig` with `InputState`, `Platform`, and a null-safe helper `platformNoop`. Create `platform/headless.zig` with a single static `Platform`:
  - `open_fn` stores width/height/scale in headless state and returns true for 160x144.
  - `present_fn` copies the 160x144 frame into a static headless snapshot.
  - `poll_fn` returns false.
  - `audio_fn` counts consumed samples.
  - `close_fn` sets closed.
  - `platformHeadless()` returns `&g_platform`.
- [ ] **Step 4: Run the dump check**
Run `"$ZIG1" -ffast --dump-c89 -o /tmp/p1_emit examples/z98/z9gb/platform/backend.zig` and `"$ZIG1" -ffast --dump-c89 -o /tmp/p1_emit2 examples/z98/z9gb/platform/headless.zig`. Expected: both rc 0, no Win32/`windows.h` in emitted C.
- [ ] **Step 5: Add ignore rules**
Create `examples/z98/z9gb/testdata/.gitignore` containing:
  ```
  *.gb
  *.gbc
  *.sav
  *.rtc
  !synth/*.gb
  !synth/*.gbc
  !expected.txt
  ```
The `!synth/` negations are required: without them the bare `*.gb` pattern recursively blocks the tracked synthetic test ROMs that P2 commits under `testdata/synth/` (spec §5.3). Later patterns override earlier ones; `synth/` itself is not ignored, so the negation is effective.
- [ ] **Step 6: Commit**
```bash
git add examples/z98/z9gb/platform/backend.zig examples/z98/z9gb/platform/headless.zig examples/z98/z9gb/testdata/.gitignore examples/z98/z9gb/tests/tier_smoke.sh
git commit -m "feat(z9gb): add platform table and headless backend"
```

---

### Task 2: Add the Emu facade and deterministic framebuffer

**Files:**
- Create: `examples/z98/z9gb/emu.zig`
- Create: `examples/z98/z9gb/main.zig`
- Modify: `examples/z98/z9gb/tests/tier_smoke.sh`
- Test: `examples/z98/z9gb/tests/tier_smoke.sh`

**Interfaces:**
- Consumes: `platform/backend.zig`, `platform/headless.zig`.
- Produces (facade signatures must match spec §8.2 exactly — P2/P4/P5 consume them):
  - `pub const EmuConfig = struct { cgb: bool, serial_log: bool, turbo: bool, dynarec: bool };`
  - `pub const EmuError = error{ RomTooLarge, BadHeader, UnsupportedMbc, CgbRequired, SaveCorrupt, Io, OutOfMemory };`
  - `pub const Emu = struct { /* fixed storage */ };`
  - `pub fn emuInit(e: *Emu, cfg: EmuConfig) void;`
  - `pub fn emuLoadRom(e: *Emu, path: []const u8) EmuError!void;`
  - `pub fn emuReset(e: *Emu) void;`
  - `pub fn emuRunFrame(e: *Emu) u32;`
  - `pub fn emuFramebuffer(e: *const Emu) []const u32;`
  - `pub fn emuSetButtons(e: *Emu, bits: u8) void;`
  - `pub fn emuTakeSerial(e: *Emu, out: []u8) usize;`
  - `pub fn emuSetSavePath(e: *Emu, path: []const u8) void;`
  - `pub fn emuSaveBattery(e: *Emu) EmuError!void;`
  - `pub fn emuLoadBattery(e: *Emu) EmuError!void;`
  - `pub fn emuSelfTestPattern(e: *Emu) void;` (P1-only test hook; removed or renamed in P2)
  P1 semantics: `emuLoadRom` copies the file into the fixed ROM buffer (8 MiB cap; `RomTooLarge` above it, `Io` on file error) and sets `rom_len`; header parsing is P2's. `emuReset` clears serial/buttons counters. `emuSetButtons` stores the raw 8-bit pad state. `emuTakeSerial` drains `serial_log` into `out`, returns bytes copied. `emuSetSavePath` copies into `save_path` (cap 260). `emuSaveBattery`/`emuLoadBattery` return `error.Io` in P1 (no save backend until P2 Task 8); the signatures are fixed here so P2 fills them in without API churn.

- [ ] **Step 1: Write the failing test**
Extend `tier_smoke.sh` to run:
```sh
"$BIN" --headless --frames 2 --fb-out /tmp/z9gb_p1.fb
test "$(stat -c %s /tmp/z9gb_p1.fb)" = "92160"
echo "54c0af1aa8cee3642b6f1c4a24831e89  /tmp/z9gb_p1.fb" | md5sum -c -
```
and to check the first, middle, and last little-endian u32 with `od`. The md5 `54c0af1aa8cee3642b6f1c4a24831e89` is the exact hash of the 92,160-byte little-endian dump of `fb[y*160+x] = 0x00010000 | (x & 0xFF) | ((y & 0xFF) << 8)`. Expected: fails because the binary and facade do not exist.
- [ ] **Step 2: Run it**
Run `bash examples/z98/z9gb/tests/tier_smoke.sh "$ZIG1"`. Expected: FAIL, missing `main.zig`.
- [ ] **Step 3: Implement `Emu` and the pattern**
`Emu` stores:
  - `rom: [8 * 1024 * 1024]u8`, `rom_len: usize` (fixed buffer P2's loader contract consumes; `emuLoadRom` does the size-checked copy)
  - `fb: [160 * 144]u32`
  - `serial_log: [4096]u8`, `serial_len: usize`
  - `buttons: u8`
  - `cfg: EmuConfig`
  - `save_path: [260]u8`, `save_len: usize`
  - no heap, no large stack locals.
`Emu` is ~8.5 MiB and must be a module-scope `var` (e.g. `var g_emu: Emu = undefined;`); never a stack local or a by-value copy — the 1 MiB stack is a hard limit.
`emuSelfTestPattern` sets:
  - `fb[y * 160 + x] = 0x00010000 | (x & 0xFF) | ((y & 0xFF) << 8)`
`emuRunFrame` calls `emuSelfTestPattern` and returns `70224` (one DMG frame in T-cycles) for P1.
- [ ] **Step 4: Implement CLI**
`main.zig` accepts:
  - `--headless`
  - `--frames <n>` (default 1)
  - `--fb-out <path>`
  - `--rom <path>` (loaded into the fixed buffer via `emuLoadRom`: size-checked copy only; `RomTooLarge` if > 8 MiB, `Io` on read failure; no header parsing until P2)
It opens `platformHeadless()`, runs `n` frames, presents the final frame, and writes 160*144 little-endian `u32` bytes when `--fb-out` is set.
- [ ] **Step 5: Verify exact pixels**
Run the test and `od -An -tx4 -N4 /tmp/z9gb_p1.fb`; expected first word `00010000`. Check the middle pixel at offset `(72*160+80)*4`; expected `0x00014850` (`0x00010000 | 80 | (72<<8)`). Check the last pixel offset `(143*160+159)*4`; expected `0x00018F9F`. Verify the whole-file hash: `md5sum /tmp/z9gb_p1.fb` must print `54c0af1aa8cee3642b6f1c4a24831e89`.
- [ ] **Step 6: Commit**
```bash
git add examples/z98/z9gb/emu.zig examples/z98/z9gb/main.zig examples/z98/z9gb/tests/tier_smoke.sh
git commit -m "feat(z9gb): add deterministic headless frame facade"
```

---

### Task 3: Add RSS measurement and repeated-run determinism

**Files:**
- Create: `examples/z98/z9gb/tests/measure_rss.sh`
- Modify: `examples/z98/z9gb/tests/tier_smoke.sh`
- Test: `examples/z98/z9gb/tests/measure_rss.sh`

**Interfaces:**
- Consumes: the `--headless --frames N` entry point.
- Produces: `measure_rss.sh <zig1> <out-dir>` printing `rss_kb=<n>`; a `SKIP` line when `/usr/bin/time` is absent.

- [ ] **Step 1: Write the failing test**
`measure_rss.sh` builds the program, runs `--headless --frames 60` under `/usr/bin/time -f '%M' -o "$OUT/rss.txt"`, and asserts `rss_kb` is a positive integer below `12000`. Expected: fails because the script does not exist.
- [ ] **Step 2: Implement the script**
Use POSIX `sh`, `SCRIPT_DIR`/`ROOT`, `mktemp -d`, and no network. If `/usr/bin/time` is absent, print `SKIP: /usr/bin/time unavailable` and exit 77.
- [ ] **Step 3: Add determinism**
Run the same command three times; read `/tmp/z9gb_p1.fb` after each and compare with `cmp -s`. Expected: identical.
- [ ] **Step 4: Verify memory accounting**
The script prints `rss_kb=<n>`, `fb_bytes=92160`, and `rom_bytes=8388608` (the two documented fixed buffers; `Emu` also carries 4 KiB serial + 260 B path, negligible). The framebuffer alone was never the whole static footprint — do not report `static_bytes=92160`. Expected: `rss_kb` below 12000 with the 8 MiB ROM buffer resident (P1 holds the buffer even without a ROM loaded).
- [ ] **Step 5: Commit**
```bash
git add examples/z98/z9gb/tests/measure_rss.sh examples/z98/z9gb/tests/tier_smoke.sh
git commit -m "test(z9gb): add headless RSS and determinism tier"
```

---

### Task 4: Register the example and truth-up matrix counts

**Files:**
- Create: `examples/z98/z9gb/README.md`
- Modify: `README.md` (example matrix count and P1 status)
- Modify: `docs/sf/QUICK_REF.md` (example matrix count, build recipe)
- Test: `examples/z98/z9gb/tests/tier_smoke.sh`

**Interfaces:**
- Consumes: the built example.
- Produces: a corpus-visible example and truthful documentation.

- [ ] **Step 1: Write the failing check**
Run `bash scripts/corpus/list_corpus_dirs.sh | grep -c 'examples/z98/z9gb'`. Expected before the files exist: `0`.
- [ ] **Step 2: Add README**
Document: P1 status, build command, `--headless`, `--frames`, `--fb-out`, `--rom` (size-checked load into the 8 MiB fixed buffer; no header parsing or emulation until P2), RAM model (1 MiB stack separate from 1 MiB code cache; 8 MiB ROM buffer is static, not stack).
- [ ] **Step 3: Update matrix counts**
Current matrix is 28/28 over 32 directories. Adding `z9gb` makes 33 directories; with the same four exclusions (`demo`, `gfx_demo`, `z9dbg`, `z9edit`) the matrix becomes 29/29. Update every live count and the build recipe. Keep historical counts labeled historical.
- [ ] **Step 4: Verify corpus and build**
Run:
```sh
bash scripts/corpus/list_corpus_dirs.sh | grep -c 'examples/z98/z9gb'
"$ZIG1" -ffast -o /tmp/z9gb_p1 examples/z98/z9gb/main.zig
sh /tmp/z9gb_p1/build_target.sh linux /tmp/z9gb_p1/z9gb
/tmp/z9gb_p1/z9gb --headless --frames 1 --fb-out /tmp/z9gb_p1.fb
```
Expected: count `1`; dump/gcc/link rc 0; fb file 92160 bytes.
- [ ] **Step 5: Commit**
```bash
git add examples/z98/z9gb/README.md README.md docs/sf/QUICK_REF.md
git commit -m "docs(z9gb): register the headless example and matrix count"
```

---

### Task 5: P1 closeout

**Files:**
- Modify: `examples/z98/z9gb/README.md`
- Test: `examples/z98/z9gb/tests/tier_smoke.sh`, `examples/z98/z9gb/tests/measure_rss.sh`

**Interfaces:**
- Consumes: all P1 tasks.
- Produces: a green P1 with recorded evidence.

- [ ] **Step 1: Run the P1 tier**
Run `bash examples/z98/z9gb/tests/tier_smoke.sh "$ZIG1"` and `bash examples/z98/z9gb/tests/measure_rss.sh "$ZIG1" /tmp/z9gb_p1_rss`. Expected: PASS and `rss_kb` below 12000.
- [ ] **Step 2: Run the corpus dump**
Run `"$ZIG1" -ffast --dump-c89 -o /tmp/z9gb_p1_dump examples/z98/z9gb/main.zig` and `"$ZIG1" -ffast --dump-c89 -o /tmp/z9gb_p1_emit examples/z98/z9gb/emu.zig`. Expected: rc 0. The z9gb module C/H (`main_*.c/.h`, `emu_*.c/.h`) contain no `windows.h`/`ddraw.h`; shared runtime/support files (`zig_pal.c`, `c_exit.c`, `zig_nocrt.c`, `std_io_*.c`, `std_os_prelude.h`) may contain guarded Win32 includes.
- [ ] **Step 3: Record evidence**
Write the exact command, rc, framebuffer size, rss_kb, and the three-run cmp result into the task report. Record the P1 matrix count.
- [ ] **Step 4: Commit closeout**
```bash
git add examples/z98/z9gb/README.md
git commit -m "docs(z9gb): record P1 headless evidence"
```
