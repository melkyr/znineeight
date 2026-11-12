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
- No `sf/src`, compiler, seed, or code-cache changes. No seed rotation. Single exception: Task 8A may add the additive `dinputPollRaw` accessor to `sf/src/std_dinput.zig` / `std_dinput_pal.zig` (no behavior change for existing callers).
- Never commit ROM bytes, reference PNGs, or user save files. User ROMs live in `lin_bin/` and are SKIP-able evidence only.
- Wine evidence is Wine, never Win98 hardware.
- One commit per task, explicit staging, no amend of prior commits, no push.
- Every `--dynarec` run must show non-vacuous counters (`blocks > 0`, `executed > 0`); `dynarec=disabled reason=...` is a SKIP/FAIL never a PASS.
- Hard gates must be present and passing; a skipped hard gate blocks closeout.
- **Mandatory STOP after Task 7** (present results, wait for the operator) before Task 8A.
- Task 8A is implementation (configurable mapping + `--mapkeys`); Task 8B is a conditional translation fix gated on the operator's captured evidence; Task 8 is feasibility + report only: no product code.

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

### Task 2: Dynarec emit-overflow rejection and patch hardening

**Files:**
- Modify: `examples/z98/z9gb/dynarec/x86.zig`
- Modify: `examples/z98/z9gb/dynarec/dynarec.zig`
- Modify: `examples/z98/z9gb/tests/dynarec_test.zig`

**Interfaces:**
- Consumes: `Emit{code,len,cap}`, `Label{at,n}`, `labelAdd`, `labelPatchAt`, `emitBlock`, `translate`.
- Produces: the overflow sentinel `e.len == e.cap + 1` is the single failure signal (already set by `emitByte`; now also set by `labelAdd` when its patch table is full); `labelPatchAt` skips patching when the buffer is overflowed; the existing end-of-block check in `emitBlock` rejects the block; `translate` returns null so the block runs interpreted. No new `Emit` field and no counters (Task 3 owns `rejected`).

- [ ] **Step 1: Record the evidence (already gathered; verify, do not re-derive)**

The probe found 40 underflows in `labelPatchAt`, all with `target = e.len = BLOCK_MAX_BYTES + 1` (4097), i.e. the x86 emit buffer already overflowed. `emitByte` signals this by setting `len = cap + 1`; callers ignore the bool, and `emitBlock`'s end check runs only **after** the final `labelPatchAt`, so the trap fires first. This is **not** a backward jump and not an emitter ordering defect. Separately, `labelAdd` would silently drop patches past its table; `Label.at` is 256 entries (`x86.zig:83`) and a legal 64-instruction block produces at most one `g_epilogue` jump per helper-using instruction (≤64), so the table cannot fill for legal blocks today. The silent drop is a latent class if the block cap or per-instruction patch count ever grows; keep the sentinel hardening in Step 3 as defence.

If new evidence contradicts either statement, STOP and present it.

- [ ] **Step 2: Guard the patch arithmetic**

In `labelPatchAt` (`dynarec/x86.zig`), at entry: if `e.len > e.cap`, set `l.n = 0` and return (skip every patch; the block will be rejected by the existing end check). Keep the strict `target - (at + 4)` subtraction: a true backward patch is never expected, and if one is ever introduced it must fail loudly rather than silently emit a wrong rel32.

- [ ] **Step 3: Make patch-table overflow use the same sentinel (defensive)**

Change `labelAdd` to `fn labelAdd(e: *Emit, l: *Label, at: usize) void`; when `l.n >= l.at.len`, set `e.len = e.cap + 1` and return instead of silently dropping. Update its two call sites (`emitJcc`, `emitJmp`). Do not add a struct field and do not change `Label.at`. This branch is unreachable for legal blocks today (256 entries vs ≤64 patches) and is defence against future block/patch growth; it is not unit-tested through the public API (see Step 4).

- [ ] **Step 4: Write the regressions, then verify**

Add to `tests/dynarec_test.zig`:
1. `test_emit_buffer_overflow_rejected` (RED) — emit a block into a test `Emit` whose cap is too small for its expansion; assert `emitBlock` returns false and does not trap, no cache entry is installed, and interpreter execution matches. Today this traps under `-fsafe` (or reports success with an overflowed length).
2. `test_helper_heavy_block_translates` (regression guard) — a block of ~48-60 `LD r,(HL)` instructions (~48-60 helper calls) translates, executes, and matches interpreter CPU/cycle behaviour; proves no epilogue-patch loss at the current 256-entry table and guards against future cap regressions.
3. `test_normal_block_translates` — a normal block still translates and executes.
Run RED first for item 1; items 2-3 are regression guards (expected to pass before and after).

Run: `sh examples/z98/z9gb/tests/tier_dynarec.sh /tmp/z9gb_p2_seed/zig1_5_clean`
Expected: PASS, both modes, with the new checks.

- [ ] **Step 5: Full gate regression**

Run: `tier_dmg --gates` (`Z9GB_ROM_DIR=/tmp/z9gb_roms`), `tier_dmg --all`, `tier_smoke`.
Expected: 166/0 gates (Mooneye PPU parity included), 49+ pass, smoke 18/18.

- [ ] **Step 6: Commit**

```bash
git add examples/z98/z9gb/dynarec/x86.zig examples/z98/z9gb/dynarec/dynarec.zig examples/z98/z9gb/tests/dynarec_test.zig
git commit -m "fix(z9gb): reject overflowing dynarec translations"
```


---

### Task 3: Coverage accounting in `--dynarec-stats`

**Files:**
- Modify: `examples/z98/z9gb/dynarec/cache.zig`
- Modify: `examples/z98/z9gb/dynarec/dynarec.zig`
- Modify: `examples/z98/z9gb/emu.zig`
- Modify: `examples/z98/z9gb/main.zig`
- Modify: `examples/z98/z9gb/tests/dynarec_test.zig`
- Modify: `examples/z98/z9gb/tests/tier_dynarec.sh`

**Interfaces:**
- Consumes: `cache.Stats` (`blocks`, `executed`, `chained`, `fallback`, `resets`, `collisions`), `emu.DynarecStats` projection, `translate` rejection sites.
- Produces: `cache.Stats.tinstr`, `cache.Stats.minstr`, `cache.Stats.rejected` (with explicit initializer at `cache.zig`'s `Stats{...}` init); `emu.DynarecStats` gains `tinstr`, `minstr`, `rejected`; printed ` tinstr=<n> minstr=<n> rejected=<n> coverage=<permille>‰` derived from `tinstr / (tinstr + minstr)`. Existing keys keep their names.

- [ ] **Step 1: Write the failing counter test**

In `tests/dynarec_test.zig`, add a test that runs one known multi-instruction ROM block with dynarec enabled and asserts: `stats.tinstr == block.len` on a cold run, `stats.minstr` increments for a non-ROM PC step, and `stats.rejected` increments for a deliberately rejected block (an oversized or patch-overflow block from Task 2). Assert the derived coverage is 1000 on an all-translated run.

- [ ] **Step 2: Run to verify RED**

Run: `sh examples/z98/z9gb/tests/tier_dynarec.sh /tmp/z9gb_p2_seed/zig1_5_clean`
Expected: FAIL (fields missing).

- [ ] **Step 3: Implement the counters**

Add the three fields to `cache.Stats` and its explicit initializer. In `dynarec.zig`: increment `tinstr` by the executed instruction count for each translated block (from the builder's decoded length), `minstr` by one per interpreter/fallback step (`interpStep` and the dispatch-gate paths), and `rejected` at every `translate` rejection return (blockBuild failure, empty block, ROM span bounds, ROM0/ROMX straddle, `emitBlock` false). Do not add a second rejection counter elsewhere.

- [ ] **Step 4: Print coverage**

Extend the `emu.DynarecStats` projection and `main.zig` output: append ` tinstr=<n> minstr=<n> rejected=<n> coverage=<permille>‰`. Keep the existing `blocks/executed/fallback` keys.

- [ ] **Step 5: Verify GREEN and the CLI**

Rebuild the verification exe from the current sources (untracked scratch; do not commit the exe, do not touch `lin_bin/z9gb.exe`):

```bash
cat > /tmp/gcc-o2 <<'EOS'
#!/bin/sh
exec i686-w64-mingw32-gcc -O2 "$@"
EOS
chmod +x /tmp/gcc-o2
DUMP_TARGET="-osw -I /workspace/znineeight/sf/src" CROSS_GCC=/tmp/gcc-o2 \
EXTRA_LIBS="-luser32 -lgdi32 -lwinmm" \
bash scripts/win32_cross/cross_nocrt.sh /tmp/z9gb_p2_seed/zig1_5_clean \
  examples/z98/z9gb/main.zig /tmp/z9gb_task3_build \
  /workspace/znineeight/lin_bin/z9gb_o2.exe
```

Run the dynarec tier and one CLI smoke: `wine lin_bin/z9gb_o2.exe --headless --frames 120 --dynarec --dynarec-stats --rom /tmp/z9gb_roms/2048.gb`.
Expected: counters non-zero, `coverage` printed, `dynarec=on blocks>0`, and the stats line contains `tinstr= minstr= rejected= coverage=`.


- [ ] **Step 6: Commit**

```bash
git add examples/z98/z9gb/dynarec/cache.zig examples/z98/z9gb/dynarec/dynarec.zig examples/z98/z9gb/emu.zig examples/z98/z9gb/main.zig examples/z98/z9gb/tests/dynarec_test.zig examples/z98/z9gb/tests/tier_dynarec.sh
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
- Modify: `examples/z98/z9gb/tests/tier_cgb.sh`
- Modify: `examples/z98/z9gb/tests/tier_dynarec.sh`
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

- [ ] **Step 4: Update bounded tier invocations**

`tier_cgb.sh` (five sites: ~264, 272, 279, 286, 293) and `tier_dynarec.sh` (~311) pass `--frames 0` expecting an immediate exit; with `0` = unlimited they must send an explicit bounded count. Change those invocations to `--frames 1` (the ~264 failure case may also move to `1`; its expect-early-exit assertion is unchanged). Do not change any assertions.

Run `tier_cgb.sh --all`, `tier_dynarec.sh`, `tier_smoke.sh`, `tier_dmg.sh --all`.
Expected: all pass; no timeouts from the changed invocations.
Commit: `test(z9gb): pass explicit --frames in bounded tier checks` (new commit, no amend).

- [ ] **Step 5: Update docs/run commands**

READMEs: windowed = run until quit; headless runs until `--frames` or Ctrl-C; tests/harnesses that need a bounded run must pass `--frames N`; add example commands for Crystal/Pinball/`k_dl`.

- [ ] **Step 6: Commit**

```bash
git add examples/z98/z9gb/main.zig examples/z98/z9gb/tests/tier_smoke.sh examples/z98/z9gb/tests/tier_cgb.sh examples/z98/z9gb/tests/tier_dynarec.sh examples/z98/z9gb/README.md README.md
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
- Produces: `.mbc7` cartridge kind; `typeIncludesRam(0x22) == true`; EEPROM size 256 bytes (93LC56); `PageKind.mbc7` for `0xA000-0xAFFF`; `cartMbc7Read`/`cartMbc7Write` routing; `emuSetTilt(x: i16, y: i16)` test seam; MBC5 rumble RAM bank `& 0x07` for `0x1C..0x1E`.

- [ ] **Step 1: Pin the MBC7 register map (no guessing)**

The map below is pinned from Pan Docs (MBC7) and `k_tt.gbc` boot bytes (`0xCDF0` `3E 55 / EA 00 A0`, `0xCDF5` `3E AA / EA 10 A0`, `0xCE0D`/`0xCE12` enables, `0xCE17`/`0xCE1B` X reads, `0xCE2B`/`0xCE2F` Y reads, `0x50E` `LD A,$2E; LD ($2100),A`, `0x167E0` EEPROM helper). Re-verify against Pan Docs and a byte dump of the `k_tt.gbc` boot code, record the evidence in the report, then implement it. STOP and present to the operator only if the evidence contradicts this pinned map.

- `0x0000-0x1FFF`: RAM enable 1 (`0x0A`); `0x4000-0x5FFF`: RAM enable 2 (`0x40`); both required, else `0xA000-0xAFFF` reads `0xFF` and writes are ignored.
- `0x2000-0x3FFF`: 8-bit ROM bank register (banks `0x00-0x7F`), masked by ROM size like MBC5.
- `0xA000-0xAFFF`: registers selected by address bits 4-7 (bits 0-3 and 8-11 ignored): `Ax0x` write `0x55` = erase latch to `0x8000`; `Ax1x` write `0xAA` = latch (only if erased since the last latch); both read `0xFF`. `Ax2x`/`Ax3x` and `Ax4x`/`Ax5x` = X/Y low/high (16-bit, reset/erase `0x8000`); `Ax6x`=0x00, `Ax7x`=0xFF, `Ax9x`-`AxFx`=0xFF; `Ax8x` = EEPROM pins (bit0 DO, bit1 DI, bit6 CLK, bit7 CS).
- `0xB000-0xBFFF`: reads `0xFF`.
- EEPROM: 93LC56, 256 bytes, 16-bit words, 10-bit commands + 16 data bits MSB-first, all 7 commands (READ/EWEN/EWDS/WRITE/ERASE/ERAL/WRAL), programming gated by EWEN, instant-ready DO; blank EEPROM is erased (`0xFF`).

- [ ] **Step 2: Write the failing cart tests**

Add cases to the cart/save tier:
1. Load a synthetic type-`0x22` ROM: accepted, `cartRamSize == 256`; with no `.sav`, EEPROM/register reads are erased (`0xFF`), not zero.
2. ROM banking: write the `0x2000-0x3FFF` register, assert `cartRead` returns bytes from the selected bank; out-of-range bank values mask by ROM size like MBC5.
3. RAM enables: with enable1 only or enable2 only, `0xA020-0xA05F` reads `0xFF` and writes are ignored; both enabled → registers active.
4. Accelerometer: erase (`0x55`→`0xA000`) then latch (`0xAA`→`0xA010`) with the seam `emuSetTilt(0x1234, 0x5678)`; read X `0xA020`/`0xA030`, Y `0xA040`/`0xA050`; a second latch without a new erase is a no-op; `Ax0x`/`Ax1x` reads are `0xFF`; `A060`=0x00, `A070`=0xFF, `A090`=0xFF, `0xB000`=0xFF; no seam → neutral `0x8000`.
5. EEPROM: EWEN + WRITE + READ round-trip; WRITE without EWEN is ignored; ERASE/ERAL/WRAL behave per the 93LC56; save to `.sav`, reload, assert persistence.
6. MBC5 rumble: type `0x1E`, write `0x08` to the RAM-bank register, assert the active RAM bank is 0 (not 8) and a save round-trip keeps bank-0 data.

- [ ] **Step 3: Run to verify RED**

Run: `sh examples/z98/z9gb/tests/tier_dmg.sh /tmp/z9gb_p2_seed/zig1_5_clean --only save` (and the cart case).
Expected: FAIL (`UnsupportedMbc`).

- [ ] **Step 4: Implement MBC7 + rumble mask**

`cart.zig`: `mbcKnown` accepts `0x22`; `typeIncludesRam` includes `0x22`; MBC7 EEPROM is a 256-byte view of `cart.ram` (RAM size 256, exempt from the 8 KiB inference; blank EEPROM is erased, i.e. `0xFF`-filled, not zero-filled); ROM banking is an 8-bit register at `0x2000-0x3FFF` (banks `0x00-0x7F`) masked by ROM size like MBC5; `cartMbc7Read/Write` implement: register selection by address bits 4-7 across `0xA000-0xAFFF`; erase/latch at `Ax0x`/`Ax1x` with latch-requires-erase; X/Y low/high at `Ax2x`-`Ax5x` (16-bit, reset/erase value `0x8000`, high bytes masked to `0x0F` on read); `Ax6x`=0x00, `Ax7x`=0xFF, `Ax9x`-`AxFx`=0xFF; EEPROM pins at `Ax8x` (bit0 DO, bit1 DI, bit6 CLK, bit7 CS) driving a 93LC56 state machine (10-bit commands + 16 data bits MSB-first, all 7 commands, EWEN-gated writes, instant-ready DO); `0xB000-0xBFFF` reads `0xFF`; both RAM enables (`0x0000`=0x0A and `0x4000`=0x40) are required. `mmu.zig`: route `0xA000-0xAFFF` to `PageKind.mbc7` when the cart is MBC7 (rebuild on enable/write like the RTC window); disabled → `0xFF`/ignored. `cart.zig`: MBC5 write masks `& 0x07` for types `0x1C..0x1E` (bit 3 is rumble); no rumble output.

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

Operator decision after this STOP: implement **Task 8A** (configurable keyboard mapping + `--mapkeys`) first and test it on real ROMs; Task 8B is conditional on that evidence; Task 8 is the report-only study; Task 9 is tilt **option 5 hybrid** plus the opt-in rumble cue (default off).

---

### Task 8A: Configurable keyboard input and `--mapkeys` — implement first

**Files:**
- Create: `examples/z98/z9gb/input_config.zig`
- Create: `examples/z98/z9gb/tests/input_map_test.zig`
- Modify: `examples/z98/z9gb/main.zig`
- Modify: `examples/z98/z9gb/platform/win32.zig`
- Modify: `sf/src/std_dinput.zig`, `sf/src/std_dinput_pal.zig` (additive raw keyboard-state accessor only; no behavior change for existing callers)
- Modify: `examples/z98/z9gb/tests/tier_dmg.sh` (new `input_map` case)
- Rebuild (untracked): `lin_bin/z9gb.exe`

**Interfaces:**
- Consumes: the platform poll path, `InputState` bit order (0 right, 1 left, 2 up, 3 down, 4 a, 5 b, 6 select, 7 start), the `input_test.zig` JOYP semantics.
- Produces: `InputConfig` (9 logical inputs -> raw key code + backend tag), `z9gb.ini` load/save, `--mapkeys`, `--printkeys`, `--input-debug`, and additive `dinputPollRaw(d, out: []u8) bool`.

- [ ] **Step 1: Write the failing tests**

Add `input_map_test.zig` cases (Task 1/6 style):
1. Defaults: absent ini -> the pinned default map (arrows=D-pad, Z=A, X=B, Enter=Start, Backspace=Select, Esc=quit).
2. Ini round-trip: save then load reproduces the 9 raw codes and backend tag.
3. Duplicate raw code in the ini or during capture is rejected (loader falls back to defaults; wizard re-prompts).
4. Backend mismatch (ini `backend=fallback` under DInput8, or the reverse) -> defaults plus a warning.
5. Synthetic raw-state mapping: set a raw index in a 256-byte array, assert the mapped `InputState` bit for each of the 9 logical inputs.
6. Wizard capture state machine: synthetic transitions produce one capture per prompt, debounce ignores held keys, and the recorded `fixed=` diagnostic reflects the legacy table.
Run: RED.

- [ ] **Step 2: Implement `input_config.zig`**

`KeyBinding{ raw: u8, kind: u8 }`; `InputConfig` with `right,left,up,down,a,b,select,start,quit`; default table = the DIK codes currently in `std_dinput_pal.mapKeys`. `configLoad(path)`, `configSave(path)`, `configApply(raw_keys, *InputState)`. Ini format: `[keys]`, `backend=dinput8|fallback`, `Button=0xNN`, `;` comments; malformed/unknown lines ignored; any parse or duplicate failure -> defaults + warning.

- [ ] **Step 3: Add the additive raw accessor**

`std_dinput.dinputPollRaw(d, out: []u8) bool` (and a pal passthrough) returns the 256-byte keyboard state read by the same `GetDeviceState` call; `fallback` returns the VK-indexed view or false. Existing `dinputPoll` behavior is unchanged.

- [ ] **Step 4: Runtime mapping and CLI modes**

`win32.zig` poll maps raw state -> `InputState` through the active `InputConfig` when one is loaded, otherwise keeps the existing mapped path. `main.zig`: load `z9gb.ini` at startup when present; `--printkeys` prints the active table (logical input, raw code, backend); `--input-debug` prints the raw code and mapped button on each change; `--mapkeys` is Win32-only, opens the platform window (scale 1, audio off), prints the current table, prompts `Map "A" button to.. `, captures the first raw transition with debounce, rejects duplicates, and writes `z9gb.ini` including `raw=0xNN` plus a `; Button raw=0xNN fixed=...` diagnostic line showing what the legacy table would have produced. Non-Windows `--mapkeys` prints a clear unsupported-host message and exits 2.

- [ ] **Step 5: Verify GREEN**

Run `tier_dmg.sh --only input_map`, `tier_dmg.sh --only input`, `tier_smoke.sh`, plus one windowed mapping smoke under Wine. No full battery (operator ruling: gates already done).

- [ ] **Step 6: Rebuild and hand off**

Rebuild `lin_bin/z9gb.exe` with `EXTRA_CFLAGS=-O2`. Report the active default table, the ini path, the exact `--mapkeys` command, and the diagnostic behavior. The operator runs `--mapkeys`, tests the ROMs, and sends the ini + observations.

- [ ] **Step 7: Commit** `feat(z9gb): add configurable keyboard mapping and --mapkeys`.

- [ ] **Step 8: STOP** — wait for the operator's mapping report before Task 8B or 8.

---

### Task 8B (conditional): Translation-layer fix from the capture evidence

Only if the operator's report shows the wizard recorded the intended keys but the games still misread. Diagnose from the saved ini + `--input-debug` output (raw code, mapped button, fixed-table diagnostic); fix only the layer the evidence identifies (legacy DIK table, DInput data-format indexing, or the raw->JOYP mapping). STOP and present before editing if the evidence is ambiguous or points at more than one layer. Light verification only; commit `fix(z9gb): correct key translation`.

---

### Task 8 (study): PPU-boundary relaxation and input residuals — report only

**Files:**
- Create: `docs/superpowers/specs/2026-11-12-z9gb-boundary-feasibility.md`
- Report: `.superpowers/sdd/2026-11-12-z9gb-compat-fixes-plan/task-8-report.md`
- Scratch only: `/tmp/z9gb_boundary_fx/` (copy of the emulator)

**Interfaces:**
- Consumes: Tasks 1-8A build; the P5 Task 6.2 helper PPU sync; `tier_dmg --gates`.
- Produces: feasibility report (perf + input residuals); no product code.

- [ ] **Step 1: Build the experimental variant**

In the `/tmp` copy only, remove the "reject a block starting at a statically-known PPU read" rule (`0x40`/`0x1A`/`0xF0`/`0xFA`/`0xEA` start rejection) while keeping block *ending* at those boundaries and helper PPU sync unchanged.

- [ ] **Step 2: Measure**

Run `2048`, Crystal, Pinball at `--frames 600 --dynarec`, recording `blocks/executed/fallback/tinstr/minstr/coverage` and wall time vs the Task 4 baseline. Run `tier_dynarec`, `tier_dmg --gates` (Mooneye `lcdon_timing-GS`, `stat_irq_blocking`) and interpreter-vs-dynarec framebuffer parity. Attribute Crystal's low coverage (PPU-poll block boundaries vs HALT/idle paths) and 2048's fallback share.

- [ ] **Step 3: Report**

Perf: does coverage improve, does timing parity hold, do the gates pass, what is the risk; recommend implement/decline. Input residuals: backend-neutral key identity across the ini, tilt key naming, and the legacy-table diagnostic meaning. No product change without a further ruling. STOP.

---

### Task 9: Tilt input (option 5 hybrid) and opt-in rumble cue

Operator decision recorded at the Task 7 STOP follow-up: **option 5 — hybrid gamepad analog + keyboard digital tilt**, and **rumble cue default off** (`--rumble` enables it; games keep their own rumble options).

**Files:**
- Modify: `examples/z98/z9gb/platform/backend.zig` (`InputState` gains `tilt_x: i16`, `tilt_y: i16`; no `Platform` table field change)
- Modify: `examples/z98/z9gb/platform/win32.zig` (DInput8 axes when a pad exists; keyboard ramp keys otherwise; poll-time, no allocation)
- Modify: `examples/z98/z9gb/platform/headless.zig` (static tilt for tests)
- Modify: `examples/z98/z9gb/emu.zig` (apply `InputState` tilt each frame through the Task 6 `emuSetTilt` seam)
- Modify: `examples/z98/z9gb/cart.zig` (only if the seam needs a rumble-bit accessor)
- Modify: `examples/z98/z9gb/main.zig` (`--tilt-keys`, `--rumble`)
- Test: `examples/z98/z9gb/tests/input_test.zig` (neutral default, axis polarity, clamp, dead zone, keyboard ramp, rumble-cue gating)

**Interfaces:**
- Consumes: `emuSetTilt(x, y)`, the MBC7 window, `InputState`/`Platform`, the MBC5 rumble bit (`cart.zig` types `0x1C..0x1E`), the APU/audio path.
- Produces: hybrid tilt source (gamepad preferred, keyboard fallback) with configurable ramp keys; opt-in rumble cue; documented polarity/range; manual `k_tt` playtest evidence.

- [ ] **Step 1: Write the failing mapping tests** — neutral default (0x8000), axis/keyboard polarity, clamp to the 12-bit range, dead zone, keyboard ramp and return to center, rumble cue gated off by default and on with `--rumble`. Run RED.
- [ ] **Step 2: Implement the hybrid tilt source.** Gamepad axes when the device is present; otherwise keyboard ramp at a bounded rate. Neutral when no source is active; no heap; no `Platform` field changes beyond `InputState`.
- [ ] **Step 3: Implement the rumble cue.** When `--rumble` is set and the decoded MBC5 rumble bit is active, mix a soft low tone into the audio output; default off leaves audio byte-identical. MBC7 rumble remains unimplemented unless Task 8 finds evidence.
- [ ] **Step 4: Verify** the new tests, `tier_smoke.sh`, `tier_win32.sh --smoke`, and `tier_audio.sh` (default-off byte identity).
- [ ] **Step 5: Manual `k_tt` playtest evidence** (operator): pass calibration, reach gameplay, confirm tilt registers. Record exact commands and observed behaviour; no automated playability claim.
- [ ] **Step 6: Commit** `feat(z9gb): add hybrid MBC7 tilt and opt-in rumble cue` plus docs.
- [ ] **Step 7: STOP** — report evidence; no merge/push.

---

## Self-Review

- **Spec coverage:** RC1 → Task 1; RC2 → Task 2; RC3 → Tasks 3-4; `--frames` → Task 5; joypad IRQ → Task 1; `k_tt` MBC7 + MBC5 rumble → Task 6; gate-hole closure → Task 1 tests + Task 2 regressions; `-O2` ship → Task 7; configurable keyboard mapping + `--mapkeys` → Task 8A (operator mapping test) with Task 8B conditional on the captured evidence; boundary relaxation feasibility → Task 8 (report only) + STOP; `k_tt` tilt enablement → Task 9 option 5 hybrid, rumble cue default off (operator decision recorded after the Task 7 STOP).
- **Step scan:** every step names a command and expected result; no "handle edge cases" placeholders.
- **Type consistency:** `busApplyButtons`, the `e.len == e.cap + 1` overflow sentinel, `cache.Stats.{tinstr,minstr,rejected}`, `.mbc7`, `PageKind.mbc7`, `emuSetTilt` are used consistently across tasks.
- **Review Focus:** each of the five items has a covering test in Tasks 1, 6, 2, and 5.
- **Proportion:** plan ≈ spec ×2; code bodies omitted where signatures + tests determine them. The Task 6 register map is deliberately pinned during execution (Step 1) rather than asserted from memory.
