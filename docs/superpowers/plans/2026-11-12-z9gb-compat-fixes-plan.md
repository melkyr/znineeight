# z9gb Commercial-ROM Compatibility Fixes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix the two proven z9gb defects (missing VBlank IRQ, dynarec backward-patch trap), implement the joypad IRQ and MBC7 (`k_tt`) support, close the gate holes, and re-establish the dynarec performance claim with coverage data.

**Architecture:** One core interrupt fix in the PPU plus a joypad IRQ path in the bus; an evidence-driven fix to the x86 emitter's label patching with overflow-to-fallback hardening; coverage counters in the dynarec facade; MBC7 added as a cartridge kind with an EEPROM/accelerometer register window routed like the existing MBC3 RTC window; a CLI default change for frame count. No `sf/src`, compiler, or seed changes.

**Tech Stack:** Z98 (pure, no heap), z9gb emulator (`examples/z98/z9gb/`), tier shell harnesses, Wine/xvfb for windowed evidence, mingw cross-build for the Win9x exe.

**Spec:** `docs/superpowers/specs/2026-11-12-z9gb-compat-fixes-design.md`
**Investigation evidence:** `docs/superpowers/specs/2026-11-12-z9gb-compat-investigation.md`

## Global Constraints

- Pinned compiler: `/tmp/z9gb_p2_seed/zig1_5_clean`, md5 `73c75a65e30dfd212fdf93ae1e57a687`; seed v149, lib 65. Build Z98 with `-I /workspace/znineeight/sf/src`.
- Pure Z98 product code: no `@cImport`, asm, intrinsics, C macros, generics, `anytype`, methods, or `@alignCast`. No heap. Large state stays in the static `Emu`; 1 MiB stack limit; the 1 MiB dynarec RWX cache is the only executable allocation.
- No `sf/src`, compiler, seed, or code-cache changes. No seed rotation.
- Never commit ROM bytes, reference PNGs, or user save files. User ROMs live in `lin_bin/` and are SKIP-able evidence only.
- Wine evidence is Wine, never Win98 hardware.
- One commit per task, explicit staging, no amend of prior commits, no push.
- Every `--dynarec` run must show non-vacuous counters (`blocks > 0`, `executed > 0`); `dynarec=disabled reason=...` is a SKIP/FAIL never a PASS.
- Hard gates must be present and passing; a skipped hard gate blocks closeout.
- **Mandatory STOP after Task 7** (present results, wait for the operator) before Task 8.
- Task 8 is feasibility + report only: no product code.

## Review Focus

1. **VBlank double-raise / LCD-off raise:** exactly one IF bit 0 per frame, none while the LCD is off, and none on LCD re-enable before line 144.
2. **Joypad IRQ storm:** raise only on a newly pressed button in the currently selected P1 group; never on release, never when the group is deselected.
3. **MBC7 EEPROM bit-banging:** CS/CLK edges shift exactly one bit per clock; power-loss mid-write must not corrupt the saved EEPROM.
4. **Dynarec backward patch correctness:** a backward rel32 emitted where a forward jump was intended executes wrong code silently under `-ffast`; parity must be proven, not assumed.
5. **Frame-count semantics:** `--frames` absent/`0` must not hang, must keep `--fb-out` behavior defined, and windowed quit must still work.

---

### Task 1: VBlank IRQ, joypad IRQ, IF read masks

**Files:**
- Modify: `examples/z98/z9gb/ppu.zig`
- Modify: `examples/z98/z9gb/mmu.zig`
- Modify: `examples/z98/z9gb/emu.zig`
- Create: `examples/z98/z9gb/tests/irq_test.zig`
- Modify: `examples/z98/z9gb/tests/tier_dmg.sh`

**Interfaces:**
- Consumes: `mmumod.busRaiseIrq(bus, mask)`, `Ppu.line`, `Bus.io[]`, `Bus.buttons`.
- Produces: `pub fn busApplyButtons(bus: *Bus, mask: u8) void` in `mmu.zig` (newly pressed selected buttons raise IF `0x10`); `emuSetButtons` delegates to it; `enterLine` raises IF `0x01` on `line == VISIBLE_LINES` while the LCD is on.

- [ ] **Step 1: Write the failing IRQ tests**

Create `tests/irq_test.zig` following the structure of `tests/cgb_test.zig` (module-scope statics, `check*` helpers, prints `irq ok <n> checks`). Cases:

1. `test_vblank_once`: `ppuReset` + `busInit`; tick 154 lines of 456 dots; assert IF bit 0 set; clear IF, tick one more full frame; assert exactly one raise and that it does not re-raise within the same frame (tick 143→144 alone sets it once, further ticks on line 144 do not).
2. `test_vblank_lcd_off`: clear LCDC bit 7, tick `155 * 456` dots (more than one full frame), assert IF bit 0 stays 0 and `p.line == 0` / `p.dot == 0`. Then with the LCD on, run to line 143, write LCDC off, tick one line, and assert no VBlank. The `enterLine` LCD-on guard is defensive (unreachable through public ticks); this test pins the observable behaviour.
3. `test_joypad_irq`: select directions (`io[0x00] = 0x1F`), `busApplyButtons(bus, 0x01)` → IF `0x10` set; clear IF, `busApplyButtons(bus, 0x01)` again (still held) → no new raise; `busApplyButtons(bus, 0x00)` → no raise.
4. `test_joypad_unselected`: select buttons (`io[0x00] = 0x2F`), press a direction (`0x01`) → no raise; press A (`0x10`) → raise.
5. `test_if_read_mask`: `ioRead(0x0F)` returns bits 5–7 as 1 (`value | 0xE0`).

- [ ] **Step 2: Run to verify RED**

Run: `sh examples/z98/z9gb/tests/tier_dmg.sh /tmp/z9gb_p2_seed/zig1_5_clean --only irq`
Expected: FAIL (`vblank` checks 0, joypad 0). Register the `irq` mode in `tier_dmg.sh` following the `input` mode block.

- [ ] **Step 3: Implement the VBlank raise**

In `ppu.zig` `enterLine`, before the mode branch: if `line == VISIBLE_LINES` and `(p.lcdc & 0x80) != 0`, call `mmumod.busRaiseIrq(bus, 0x01)`. Do not raise when `line < VISIBLE_LINES`. Keep `updateStatLine` responsible for the STAT VBlank bit.

- [ ] **Step 4: Implement the joypad IRQ and IF mask**

In `mmu.zig`: add `pub fn busApplyButtons(bus: *Bus, mask: u8) void` — compute `pressed = mask & ~bus.buttons`, store `bus.buttons = mask`, then if `pressed` overlaps the selected group (`sel = bus.io[0x00]`; directions when bit 5 is 0, buttons when bit 4 is 0) call `busRaiseIrq(bus, 0x10)`. In `emu.zig` `emuSetButtons`, replace the direct store with `mmumod.busApplyButtons(&e.bus, bits)` (keep `e.buttons` mirror). In `ioWrite(0xFF00)`, after updating bits 5–4, recompute and raise if a currently selected pressed button now appears. In `ioRead(0x0F)`, return `bus.io[0x0F] | 0xE0`.

- [ ] **Step 5: Run to verify GREEN**

Run: `sh examples/z98/z9gb/tests/tier_dmg.sh /tmp/z9gb_p2_seed/zig1_5_clean --only irq`
Expected: PASS both `-ffast` and `-fsafe`; `irq ok <n>`.

- [ ] **Step 6: Full regression**

Run: `sh examples/z98/z9gb/tests/tier_dmg.sh /tmp/z9gb_p2_seed/zig1_5_clean --all`, `--gates` with `Z9GB_ROM_DIR=/tmp/z9gb_roms`, and `tier_smoke.sh`.
Expected: `--all` 49+ new cases pass, `--gates` 166/0, smoke 18/18.

- [ ] **Step 7: Commit**

```bash
git add examples/z98/z9gb/ppu.zig examples/z98/z9gb/mmu.zig examples/z98/z9gb/emu.zig examples/z98/z9gb/tests/irq_test.zig examples/z98/z9gb/tests/tier_dmg.sh
git commit -m "fix(z9gb): raise VBlank and joypad interrupts"
```

---

### Task 2: Dynarec backward label patches and overflow hardening

**Files:**
- Modify: `examples/z98/z9gb/dynarec/x86.zig`
- Modify: `examples/z98/z9gb/dynarec/dynarec.zig`
- Modify: `examples/z98/z9gb/tests/dynarec_test.zig`

**Interfaces:**
- Consumes: `Emit`, `Label`, `labelAdd`, `labelPatchAt`, `emitBlock`, `translate`.
- Produces: `Emit.patch_overflow: bool`; `emitBlock` returns `error.Unsupported` when a label patch table overflows; `translate` rejects such blocks (interpreter fallback); `DynarecStats.rejected` count.

- [ ] **Step 1: Determine the backward-patch semantics (evidence, not guess)**

Copy `examples/z98/z9gb` to `/tmp/z9gb_patch_probe`, add temporary logging in `labelPatchAt` (`label id pointer`, `l.n`, each `at`, `target`, `e.len`), build with the pinned compiler, and run `wine` on a `/tmp` copy of the `p_pin.gbc` block harness (or the full exe if the probe bundle is awkward). Record which label and which emitting function produce `target <= at + 3`.

Write the finding into the task report as: intended backward jump (a loop/epilogue re-entry) vs emitter ordering defect. This decides Step 2. STOP and present to the operator if the evidence shows a forward jump was intended but emitted backward (that is a control-flow bug, not a patch-arithmetic bug).

- [ ] **Step 2: Apply the ruled fix**

If intended backward: change `const rel: usize = target - (at + 4);` to wrapping `target -% (at + 4)`.
If ordering defect: reorder the emit/bind sequence so the target always follows the patched site, and keep the strict subtraction.
Record the ruling in the SDD ledger with cost-if-wrong.

- [ ] **Step 3: Hard-fail patch overflow instead of silent drop**

Add `patch_overflow: bool = false` to `Emit`. In `labelAdd`, when `l.n >= l.at.len`, set `e.patch_overflow = true` (change the signature to take `*Emit`). `emitBlock` checks it after each instruction and returns `error.Unsupported`. `translate` maps that to a rejected block (no cache entry) and increments `dynarec.stats.rejected`.

- [ ] **Step 4: Write the failing regressions, then verify**

Add to `tests/dynarec_test.zig`:
1. `test_backward_patch_parity` — a synthetic block that exercises the ruled backward-patch path; interpret vs dynarec CPU/framebuffer/cycle parity.
2. `test_patch_overflow_fallback` — a synthetic block forced past the patch cap; assert `emitBlock` returns `Unsupported`, no cache entry, and interpreter execution matches.
Run RED first (the overflow test must fail against the current silent-drop behavior), then GREEN.

Run: `sh examples/z98/z9gb/tests/tier_dynarec.sh /tmp/z9gb_p2_seed/zig1_5_clean`
Expected: PASS, both modes, with the new checks.

- [ ] **Step 5: Full gate regression**

Run: `tier_dmg --gates` (`Z9GB_ROM_DIR=/tmp/z9gb_roms`), `tier_dmg --all`, `tier_smoke`.
Expected: 166/0 gates (Mooneye PPU parity included), 49+ pass, smoke 18/18.

- [ ] **Step 6: Commit**

```bash
git add examples/z98/z9gb/dynarec/x86.zig examples/z98/z9gb/dynarec/dynarec.zig examples/z98/z9gb/tests/dynarec_test.zig
git commit -m "fix(z9gb): fix dynarec backward label patches"
```

---

### Task 3: Coverage accounting in `--dynarec-stats`

**Files:**
- Modify: `examples/z98/z9gb/dynarec/dynarec.zig`
- Modify: `examples/z98/z9gb/emu.zig`
- Modify: `examples/z98/z9gb/main.zig`
- Modify: `examples/z98/z9gb/tests/dynarec_test.zig`
- Modify: `examples/z98/z9gb/tests/tier_dynarec.sh`

**Interfaces:**
- Consumes: existing `DynarecStats` (`blocks`, `executed`, `chained`, `fallback`).
- Produces: `DynarecStats.tinstr` (instructions executed inside translated blocks), `DynarecStats.minstr` (instructions executed by the interpreter), `DynarecStats.rejected` (blocks rejected at translation), and a printed `coverage=<permille>‰` derived from `tinstr / (tinstr + minstr)`. Existing keys keep their names.

- [ ] **Step 1: Write the failing counter test**

In `tests/dynarec_test.zig`, add a test that runs one known multi-instruction ROM block with dynarec enabled and asserts: `stats.tinstr == block.len` on a cold run, `stats.minstr` increments for a non-ROM PC step, and `stats.rejected` increments for a deliberately rejected block. Assert the derived coverage is 1000 on an all-translated run.

- [ ] **Step 2: Run to verify RED**

Run: `sh examples/z98/z9gb/tests/tier_dynarec.sh /tmp/z9gb_p2_seed/zig1_5_clean`
Expected: FAIL (fields missing).

- [ ] **Step 3: Implement the counters**

Increment `tinstr` by the executed instruction count for each translated block (`blocks` already counts translations; count from the builder's decoded length), `minstr` by one per `cpuStep` fallback/interpreter step (including non-ROM PC and rejected blocks), and `rejected` in `translate` on rejection.

- [ ] **Step 4: Print coverage**

In `main.zig` `--dynarec-stats` output append ` tinstr=<n> minstr=<n> rejected=<n> coverage=<permille>‰`. Keep the existing `blocks/executed/fallback` keys.

- [ ] **Step 5: Verify GREEN and the CLI**

Run the dynarec tier and one CLI smoke: `wine lin_bin/z9gb_o2.exe --headless --frames 120 --dynarec --dynarec-stats --rom /tmp/z9gb_roms/2048.gb`.
Expected: counters non-zero, `coverage` printed, `dynarec=on blocks>0`.

- [ ] **Step 6: Commit**

```bash
git add examples/z98/z9gb/dynarec/dynarec.zig examples/z98/z9gb/emu.zig examples/z98/z9gb/main.zig examples/z98/z9gb/tests/dynarec_test.zig examples/z98/z9gb/tests/tier_dynarec.sh
git commit -m "feat(z9gb): report dynarec coverage in stats"
```

---

### Task 4: Re-measure dynarec performance (2048, Crystal, Pinball)

**Files:**
- Modify: `examples/z98/z9gb/tests/tier_perf.sh`
- Modify: `examples/z98/z9gb/README.md`
- Modify: `README.md`
- Modify: `docs/sf/QUICK_REF.md`

**Interfaces:**
- Consumes: Tasks 1-3 fixes; `--dynarec-stats` coverage keys; user ROMs in `lin_bin/`.
- Produces: corrected measured numbers + coverage-qualified verdict in the docs.

- [ ] **Step 1: Add the workload matrix**

Extend `tier_perf.sh` with a `--compat` section: for each ROM in `{2048 (from Z9GB_ROM_DIR), p_cry, p_pin}` run `--headless --turbo --frames 600`, interpreter and `--dynarec`, warm alternating, 3 runs each. Report wall, CPU, T-cycles/sec (`42,134,400 / wall`), fps, and the dynarec `coverage` value. Missing user ROMs → truthful `SKIP` (never PASS). Pin exact commands in the script header.

- [ ] **Step 2: Run and record**

Run: `sh examples/z98/z9gb/tests/tier_perf.sh /tmp/z9gb_p2_seed/zig1_5_clean --compat --user-roms /workspace/znineeight/lin_bin`.
Expected: completed matrix; coverage values large enough to interpret (record, do not threshold).

- [ ] **Step 3: Rewrite the verdict truthfully**

Replace the P5 "no measurable gain" wording: state the measured interpreter/dynarec T-cycles/sec per ROM **with coverage %**, explain that the P5 result measured ≤6% coverage, and give the corrected conclusion (gain, none, or workload-dependent). Wine numbers labelled Wine; no Win98 claim. Update `tier_perf` usage/status text (currently says "P3 performance evidence").

- [ ] **Step 4: Verify docs consistency**

Run: `git diff --check`; grep for stale "no measurable speedup" / "P3 performance" wording.
Expected: clean; no stale claims.

- [ ] **Step 5: Commit**

```bash
git add examples/z98/z9gb/tests/tier_perf.sh examples/z98/z9gb/README.md README.md docs/sf/QUICK_REF.md
git commit -m "docs(z9gb): re-measure dynarec with corrected coverage"
```

---

### Task 5: `--frames` default unlimited

**Files:**
- Modify: `examples/z98/z9gb/main.zig`
- Modify: `examples/z98/z9gb/tests/tier_smoke.sh`
- Modify: `examples/z98/z9gb/README.md`
- Modify: `README.md`

**Interfaces:**
- Consumes: existing CLI parsing (`--frames`, `--headless`, `--windowed`), frame loop.
- Produces: `frames == 0` means unlimited; absent `--frames` → `0`; windowed exits on quit/`Esc`; headless runs until `--frames` or process termination; `--fb-out` is written only when a finite frame count completes (documented).

- [ ] **Step 1: Write the failing CLI test**

In `tier_smoke.sh`, add: emit the example, run `timeout 3 prog --headless --rom <synth 32K> ` with no `--frames`, assert exit code 124 (still running) — RED because it currently exits ~immediately with rc 0 after one frame. Also assert `--frames 2` exits rc 0 and `--frames 0` behaves like absent (still running at timeout).

- [ ] **Step 2: Implement**

`var frames: u32 = 0;` (`0` = unlimited). Loop condition `while (frames == 0 or f < frames)`. Keep pacing/quit logic; ensure `--fb-out` writes only when `frames != 0` and the loop completed. Update usage line 7.

- [ ] **Step 3: Verify GREEN and tiers**

Run the new smoke cases, then `tier_smoke.sh`, `tier_dmg --all`.
Expected: new cases pass; no tier regressions.

- [ ] **Step 4: Update docs/run commands**

READMEs: windowed = run until quit; headless requires `--frames` for a bounded run; add example commands for Crystal/Pinball/`k_dl`.

- [ ] **Step 5: Commit**

```bash
git add examples/z98/z9gb/main.zig examples/z98/z9gb/tests/tier_smoke.sh examples/z98/z9gb/README.md README.md
git commit -m "feat(z9gb): run indefinitely unless --frames is given"
```

---

### Task 6: MBC7 support (`k_tt` type 0x22) and MBC5 rumble banking

**Files:**
- Modify: `examples/z98/z9gb/cart.zig`
- Modify: `examples/z98/z9gb/mmu.zig`
- Modify: `examples/z98/z9gb/main.zig`
- Modify: `examples/z98/z9gb/tests/tier_dmg.sh`
- Test: `examples/z98/z9gb/tests/tier_dmg.sh` (cart/save sections), `tests/cpu_test.zig` fixtures if a header fixture needs updating

**Interfaces:**
- Consumes: `Cart`, `cartLoad`, `cartRead`, `cartWrite`, `cartRamSize`, `cartSaveRam`, `cartLoadRam`, `PageKind`, `rebuildCartPages`.
- Produces: `.mbc7` cartridge kind; `typeIncludesRam(0x22) == true`; EEPROM size 256 bytes (93LC56); `PageKind.mbc7` for `0xA000-0xA0FF`; `cartMbc7Read`/`cartMbc7Write` routing; `emuSetTilt(x: i16, y: i16)` test seam; MBC5 rumble RAM bank `& 0x07` for `0x1C..0x1E`.

- [ ] **Step 1: Pin the MBC7 register map (no guessing)**

Read the Pan Docs MBC7 section and disassemble `k_tt.gbc`'s boot code (`objdump` on a `/tmp` copy or a byte dump). Record in the task report: ROM bank registers, RAM/EEPROM enable value, EEPROM `0xA080` bit assignments (CS/CLK/DI/DO), accelerometer X/Y window, and the latch mechanism. STOP and present to the operator if the evidence contradicts this plan's sketch.

- [ ] **Step 2: Write the failing cart tests**

Add cases to the cart/save tier:
1. Load a synthetic type-`0x22` ROM: accepted, `cartRamSize == 256`.
2. MBC5-style ROM banking: write bank registers, assert `cartRead` returns bytes from the selected bank.
3. EEPROM round-trip: bit-bang a byte in, read it back, save to `.sav`, reload, assert persistence.
4. Accelerometer: with the test seam `emuSetTilt(0x8000, 0x8000)`, the latch/read path returns the programmed values; no tilt set → neutral.
5. MBC5 rumble: type `0x1E`, write `0x08` to the RAM-bank register, assert the active RAM bank is 0 (not 8) and a save round-trip keeps bank-0 data.

- [ ] **Step 3: Run to verify RED**

Run: `sh examples/z98/z9gb/tests/tier_dmg.sh /tmp/z9gb_p2_seed/zig1_5_clean --only save` (and the cart case).
Expected: FAIL (`UnsupportedMbc`).

- [ ] **Step 4: Implement MBC7 + rumble mask**

`cart.zig`: `mbcKnown` accepts `0x22`; `typeIncludesRam` includes `0x22`; MBC7 EEPROM is a 256-byte view of `cart.ram` (RAM size 256, exempt from the 8 KiB inference); ROM banking per the Step 1 map; `cartMbc7Read/Write` implement the EEPROM bit-bang and accelerometer latch with the test seam. `mmu.zig`: route `0xA000-0xA0FF` to `PageKind.mbc7` when the cart is MBC7 (rebuild on enable/write like the RTC window); disabled → `0xFF`/ignored. `cart.zig`: MBC5 write masks `& 0x07` for types `0x1C..0x1E`.

- [ ] **Step 5: Clear loader diagnostics**

`main.zig`: stop collapsing `UnsupportedMbc` into `cannot read ROM`; print `z9gb: unsupported cartridge type 0xNN` with the feature name for known-but-unimplemented types. (MBC7 itself no longer hits this path.)

- [ ] **Step 6: Verify GREEN**

Run the cart/save tier, `tier_dmg --all`, `--gates`, `tier_cgb`.
Expected: new cases pass, no regressions.

- [ ] **Step 7: Commit**

```bash
git add examples/z98/z9gb/cart.zig examples/z98/z9gb/mmu.zig examples/z98/z9gb/main.zig examples/z98/z9gb/tests/tier_dmg.sh examples/z98/z9gb/tests/cpu_test.zig
git commit -m "feat(z9gb): support MBC7 and fix MBC5 rumble banking"
```

---

### Task 7: Verification, docs, `-O2` ship — then MANDATORY STOP

**Files:**
- Modify: `scripts/win32_cross/cross_nocrt.sh` (add `EXTRA_CFLAGS`, default empty)
- Modify: `examples/z98/z9gb/README.md`, `README.md`, `docs/sf/QUICK_REF.md`
- Rebuild (untracked): `lin_bin/z9gb.exe`

**Interfaces:**
- Consumes: Tasks 1-6.
- Produces: verified build, truthful docs, `-O2` exe; operator STOP.

- [ ] **Step 1: Add `EXTRA_CFLAGS` to the cross harness**

Add `EXTRA_CFLAGS=${EXTRA_CFLAGS:-}` and append it to the three gcc compile lines. Empty default must keep current behavior byte-identical: build `examples/z98/hello` before/after and compare the produced `.exe` md5.

- [ ] **Step 2: Full in-repo battery**

Run, in order, with the pinned compiler:
`tier_smoke.sh`, `tier_dmg.sh --all`, `tier_dmg.sh --gates` (`Z9GB_ROM_DIR=/tmp/z9gb_roms`), `tier_cgb.sh --all`, `tier_audio.sh`, `tier_win32.sh --smoke`, `tier_dynarec.sh`, `tier_perf.sh`, `verify_stdlib.sh`, `run_crosscheck.sh`.
Expected: all pass; gates 166/0; no SKIP on a hard gate.

- [ ] **Step 3: Rebuild and verify the shipped exe**

```bash
DUMP_TARGET="-osw -I /workspace/znineeight/sf/src" \
EXTRA_CFLAGS="-O2" EXTRA_LIBS="-luser32 -lgdi32 -lwinmm" \
bash scripts/win32_cross/cross_nocrt.sh /tmp/z9gb_p2_seed/zig1_5_clean \
  examples/z98/z9gb/main.zig /tmp/z9gb_ship /workspace/znineeight/lin_bin/z9gb.exe
```
Verify PE32 i386, Win9x import gate (KERNEL32/USER32/WINMM; no static DDRAW/DINPUT8/DSOUND), and a headless `--frames 60` self-test.

- [ ] **Step 4: End-to-end ROM matrix (evidence, not committed)**

For `p_cry --cgb`, `p_pin --cgb`, `p_pin` (DMG), `k_tt --cgb`, `k_dl`: headless `--frames 600` and `--frames 3600`, interpreter and `--dynarec`; capture `--fb-out`, exit code, unique-color count, and dynarec counters. Windowed smoke for Crystal and Pinball (`--scale 2`, `--no-audio` if the host lacks audio). Record per-ROM reachable state; `k_tt` must load and progress as far as neutral sensors allow; no fabricated playability claim.

- [ ] **Step 5: Docs**

Update status, run commands (`--frames` semantics), gates, MBC7 support + accelerometer limitation, MBC5 rumble note, corrected performance verdict, and prerequisites (include `EXTRA_CFLAGS=-O2` for shipping builds).

- [ ] **Step 6: Commit**

```bash
git add scripts/win32_cross/cross_nocrt.sh examples/z98/z9gb/README.md README.md docs/sf/QUICK_REF.md
git commit -m "docs(z9gb): verify commercial-ROM fixes and ship -O2"
```

- [ ] **Step 7: MANDATORY STOP**

Present:
1. Battery results and the per-ROM matrix (Crystal, Pinball, `k_tt`, `k_dl`; interpreter + dynarec; headless + windowed smoke).
2. Dynarec counters/coverage and the corrected performance table.
3. Docs diff summary and the shipped `-O2` exe evidence (PE32, import gate, self-test).
4. **Task 9 option menu** — tilt input for the MBC7 accelerometer: (1) gamepad analog, (2) keyboard digital tilt, (3) mouse-relative tilt, (4) static `--tilt X,Y`, (5) hybrid gamepad+keyboard, (6) decline — plus the rumble yes/no decision, with a recommendation.

Wait for the operator's choice before Task 8 or Task 9. Task 8 is feasibility-only; Task 9 is operator-gated and must not start without an explicit choice.

---

### Task 8 (feasibility): Dynarec block-start-at-PPU-read relaxation — report only

**Files:**
- Create: `docs/superpowers/specs/2026-11-12-z9gb-boundary-feasibility.md`
- Report: `.superpowers/sdd/2026-11-12-z9gb-compat-fixes-plan/task-8-report.md`
- Scratch only: `/tmp/z9gb_boundary_fx/` (copy of the emulator)

**Interfaces:**
- Consumes: Tasks 1-7 build; the P5 Task 6.2 helper PPU sync; `tier_dmg --gates`.
- Produces: feasibility report; no product code.

- [ ] **Step 1: Build the experimental variant**

In the `/tmp` copy only, remove the "reject a block starting at a statically-known PPU read" rule (`0x40`/`0x1A`/`0xF0`/`0xFA`/`0xEA` start rejection) while keeping block *ending* at those boundaries and helper PPU sync unchanged.

- [ ] **Step 2: Measure**

Run `2048`, Crystal, Pinball at `--frames 600 --dynarec`, recording `blocks/executed/fallback/tinstr/minstr/coverage` and wall time vs the Task 4 baseline. Run `tier_dynarec`, `tier_dmg --gates` (Mooneye `lcdon_timing-GS`, `stat_irq_blocking`) and interpreter-vs-dynarec framebuffer parity.

- [ ] **Step 3: Report**

State: does coverage improve, does timing parity hold, do the gates pass, and what the risk is. Recommend implement/decline. STOP; no product change without a further ruling.

---

### Task 9 (maybe): Tilt input for the MBC7 accelerometer — operator-gated

Do not start without the operator's explicit choice made at the Task 7 STOP. If
the choice is "decline", record that in the ledger and close the plan.

**Option menu presented at the Task 7 STOP (choose one, plus rumble yes/no):**

| # | Option | Source | Playable without extra hardware | Trade-off |
|---|---|---|---|---|
| 1 | Gamepad analog (recommended) | DInput8 joystick X/Y axes, dead zone + calibration | No (needs a pad) | Authentic analog feel; needs hardware verification |
| 2 | Keyboard digital tilt | Four configurable keys (default `I/J/K/L`) ramp tilt at a bounded rate | Yes | Digital feel; ramp/centre tuning |
| 3 | Mouse-relative tilt | Windowed cursor delta maps to tilt | Yes (windowed only) | Needs focus/capture; unusable headless |
| 4 | Static CLI tilt | `--tilt X,Y` fixed orientation | N/A (debug) | Calibration/tests only; no gameplay |
| 5 | Hybrid | Gamepad when a device exists, keyboard otherwise | Yes | Most code; two mappings to test |
| 6 | Decline | Keep the neutral orientation | — | `k_tt` remains loadable-only |

**Rumble sub-decision:** MBC7 rumble -> on-screen/audio feedback *or* ignored.
Default recommendation: ignored and documented (no generic Win9x motor API;
an audio-buzz mapping is optional and must not couple to `sf/src`).

**Files (depend on the chosen option):**
- Modify: `examples/z98/z9gb/platform/backend.zig` (extend `InputState` with `tilt_x: i16`, `tilt_y: i16`; no `Platform` table field change)
- Modify: `examples/z98/z9gb/platform/win32.zig` (DInput8 axes and/or key/mouse mapping, poll-time, no allocation)
- Modify: `examples/z98/z9gb/platform/headless.zig` (static tilt for tests)
- Modify: `examples/z98/z9gb/emu.zig` (apply `InputState` tilt to the cart each frame via the Task 6 `emuSetTilt` seam)
- Modify: `examples/z98/z9gb/cart.zig` (accelerometer latch returns the current tilt; already the seam)
- Modify: `examples/z98/z9gb/main.zig` (option flags such as `--tilt-keys` / `--tilt`)
- Test: `examples/z98/z9gb/tests/input_test.zig` (axis polarity, clamping at +-0x7FFF, dead zone, neutral default)

**Interfaces:**
- Consumes: Task 6 `emuSetTilt(x, y)`, the MBC7 accelerometer window, `InputState`/`Platform`, the Win32 backend.
- Produces: the operator-selected tilt source; documented axis polarity/range; manual playtest evidence for `k_tt`.

- [ ] **Step 1: Record the operator choice** (option 1-6, plus rumble yes/no) in the ledger before touching code.
- [ ] **Step 2: Write the failing mapping tests** (neutral default, polarity, clamp, dead zone if analog) in the Task 1/6 style; run RED.
- [ ] **Step 3: Implement only the chosen mapping.** Neutral default when no tilt source is active; no heap; no `Platform` field changes beyond `InputState`.
- [ ] **Step 4: Verify** the new tests, `tier_smoke.sh`, `tier_dmg.sh --all`, `tier_win32.sh --smoke`.
- [ ] **Step 5: Manual `k_tt` playtest evidence** (operator, or Wine with the chosen device): pass calibration, reach gameplay, and confirm tilt registers. Record exact commands and observed behaviour; no automated playability claim.
- [ ] **Step 6: Commit** `feat(z9gb): add operator-selected tilt input for MBC7` plus docs.
- [ ] **Step 7: STOP** — report evidence; no merge/push.

---

## Self-Review

- **Spec coverage:** RC1 → Task 1; RC2 → Task 2; RC3 → Tasks 3-4; `--frames` → Task 5; joypad IRQ → Task 1; `k_tt` MBC7 + MBC5 rumble → Task 6; gate-hole closure → Task 1 tests + Task 2 regressions; `-O2` ship → Task 7; boundary relaxation feasibility → Task 8 + STOP; `k_tt` tilt enablement → Task 9 (operator-gated; option menu presented at the Task 7 STOP).
- **Step scan:** every step names a command and expected result; no "handle edge cases" placeholders.
- **Type consistency:** `busApplyButtons`, `DynarecStats.{tinstr,minstr,rejected}`, `Emit.patch_overflow`, `.mbc7`, `PageKind.mbc7`, `emuSetTilt` are used consistently across tasks.
- **Review Focus:** each of the five items has a covering test in Tasks 1, 6, 2, and 5.
- **Proportion:** plan ≈ spec ×2; code bodies omitted where signatures + tests determine them. The Task 6 register map is deliberately pinned during execution (Step 1) rather than asserted from memory.
