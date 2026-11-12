# z9gb Commercial-ROM Compatibility Fixes — Design

**Date:** 2026-11-12
**Scope:** Phase 4 Project 1 follow-on (z9gb Game Boy emulator)
**Evidence base:** `docs/superpowers/specs/2026-11-12-z9gb-compat-investigation.md` (Task 8 (I) report)

## 1. Intent

Commercial DMG/CGB ROMs hang on a uniform screen (white in CGB mode, green in
DMG mode) and never load graphics, and `Pokemon Pinball` crashes the dynarec at
translation time. The investigation proved two independent root causes and
exposed one invalid performance verdict plus several audit gaps. This design
fixes the causes, closes the gate holes that let them ship, and re-establishes
the dynarec performance claim with coverage data.

The operator additionally requires:

- Joypad interrupt (vector `0x60`) implemented, not just documented.
- `k_tt.gbc` (Kirby Tilt 'n' Tumble, cart type `0x22` = MBC7) supported.
- `Pokemon Pinball` included in the performance re-measurement.
- Boundary relaxation (allowing dynarec blocks to start at PPU reads) is a
  **Task 8 feasibility investigation only**, taken after a **mandatory STOP**
  following Task 7; it is reported, not implemented, without a further ruling.

## 2. Confirmed root causes (do not re-litigate)

### RC1 — VBlank interrupt never raised

- `examples/z98/z9gb/ppu.zig:603-623` (`enterLine`): entering line 144 sets
  `mode = 1` but never raises IF bit 0.
- The only PPU IRQ source is STAT (`0x02`) at `ppu.zig:91` and `ppu.zig:219`.
- `git log -S "busRaiseIrq(bus, 0x01)" -- examples/z98/z9gb/ppu.zig` is empty:
  the feature never existed in any commit.
- Consequence: games that set a flag in their VBlank handler (`Crystal`) or
  increment an HRAM counter (`Pinball`) HALT/poll forever. Only STAT/timer wake
  the CPU, so the main loop never advances and VRAM/palettes stay empty.
- Proof: a `/tmp`-only patch raising `0x01` at line 144 produced non-uniform
  framebuffers (3/8/4/4 unique colors at 600 frames) versus uniform baseline.

### RC2 — Dynarec `pal_trap` on backward label patches

- `examples/z98/z9gb/dynarec/x86.zig:153`:
  `const rel: usize = target - (at + 4);` underflows when a patched site lies at
  or after its target; under `-fsafe` this traps through `pal_trap` (`int3`).
- Caller chain (mapped from `lin_bin/backtrace.txt`):
  `pal_trap <- labelPatchAt <- emitMemWrite <- emitPushImm16 <- emitCallInsn <-
  emitInsn <- emitBlock <- translate <- dynarecRunBlock`.
- Triggered while translating a Pinball block first reached around frame 11.
  Interpreter, Crystal and `k_dl` never hit it. `-ffast` wraps and encodes a
  rel32, which is only correct if the backward jump is intentional.
- Whether the backward reference is intended or an emitter ordering defect is
  an open question Task 2 must answer before choosing the fix.
- Latent hazard: `x86.zig:133-138` (`labelAdd`) silently drops patches past the
  table cap (12), i.e. can emit wrong code with no signal.

### RC3 — P5 dynarec performance verdict is invalid

Measured counters (`--dynarec-stats`) show dynarec barely ran:

| Workload | translated (`executed`) | interpreter (`fallback`) | coverage |
|---|---|---|---|
| 2048, 600 frames | 22,254 | 10,415,335 | ~0.2% |
| Crystal, 300 frames | 233,870 | 3,580,351 | ~6% |

So the "~0.4% gain" measured interpreter-dominated execution. Causes: RC1 parks
games in LY-poll loops that dynarec rejects; HALT-heavy waits are
dispatch-excluded; RC2 kills Pinball translation. The performance claim must be
re-measured after RC1/RC2 fixes, with coverage reported alongside throughput.

### Other confirmed facts

- `--frames` defaults to 1 (`main.zig:7,270`); without it a run executes one
  frame and exits `rc=0` (the "crash-like" exits users saw).
- `k_tt.gbc` type `0x22` is rejected by `mbcKnown` (`cart.zig:144-150`) into the
  generic `z9gb: cannot read ROM` (`main.zig:367`).
- MBC5 rumble types (`0x1C..0x1E`) mask RAM bank with `& 0x0F`
  (`cart.zig:203,505`); bit 3 is rumble, so the bank must be `& 0x07`.
- `lin_bin/z9gb.exe` was built `-O0` (~1 fps under Wine); the `-O2` build is
  ~100x faster.

## 3. Goals

1. Raise VBlank IRQ (`0x01`) exactly once per frame at the 143→144 transition,
   correct across LCD off/enable and double speed.
2. Implement the joypad IRQ (`0x10`, vector `0x60`) on selected-line press.
3. Fix RC2 with evidence-based semantics; make patch-table overflow fail into
   interpreter fallback instead of silent wrong code.
4. Report dynarec coverage (translated vs interpreted instruction counts) in
   `--dynarec-stats`.
5. Re-measure performance on `2048.gb`, `Pokemon Crystal`, `Pokemon Pinball`
   after fixes, reporting coverage and T-cycles/sec; rewrite the docs verdict.
6. Change `--frames` default to unlimited.
7. Support cart type `0x22` (MBC7: ROM banking, EEPROM save, accelerometer
   registers) so `k_tt.gbc` loads and runs as far as a neutral sensor allows;
   fix the MBC5 rumble RAM-bank mask.
8. Close the test-coverage hole that allowed RC1 (no VBlank IRQ test) and add
   regressions for every fix.
9. Ship a `-O2` no-CRT exe and truthful run commands.

## 4. Non-goals

- Real Win98/Pentium II hardware sign-off; Wine/cross-build evidence only.
- Accelerometer **gameplay** for `k_tt` is deferred: Task 9 is operator-gated,
  and its tilt-input option menu is presented at the Task 7 STOP. Until an
  option is chosen, the design provides the register surface, a neutral
  orientation, and a test seam only.
- Boundary relaxation implementation (Task 8 is feasibility + report only).
- `sf/src`, compiler, or seed changes; no seed rotation.
- Committing ROM bytes or reference images.
- GBA support.

## 5. Constraints

- Pure Z98 product code; no heap; large state stays in static `Emu`; 1 MiB stack
  limit; the 1 MiB dynarec code cache remains the only executable allocation.
- Pinned compiler `/tmp/z9gb_p2_seed/zig1_5_clean`
  (`73c75a65e30dfd212fdf93ae1e57a687`), seed v149, lib 65.
- User ROMs stay in `lin_bin/`; never committed, never referenced by tracked
  tests as a hard dependency (they are SKIP-able evidence).
- One commit per task, explicit staging, no push, no unrelated fixes.
- Mandatory STOP after Task 7 (results plus the Task 9 tilt option menu) before
  Task 8 or Task 9.
- Task 8 writes only a feasibility report (no product code).
- Task 9 starts only after the operator chooses a tilt option at that STOP.

## 6. Approaches and decisions

### 6.1 VBlank raise location

- (a) Raise inside `enterLine` when `line == VISIBLE_LINES` — single call path,
  naturally once per frame.
- (b) Raise inside `ppuTick` when the dot counter crosses the line boundary —
  duplicates logic across the first-line/LCD-enable paths.
- **Decision (a).** Add a guard that the LCD is on; do not raise when the PPU is
  disabled (LCD off forces line 0 without a VBlank event). Verify the STAT
  VBlank source (STAT bit 4) still behaves through `updateStatLine`.

### 6.2 Joypad IRQ source

- (a) Raise in `ioWrite(0xFF00)` only — misses button presses while the group is
  already selected.
- (b) Raise from a shared `busApplyButtons` used by both `emuSetButtons` and
  `ioWrite` — detects newly pressed buttons in the currently selected group.
- **Decision (b).** Falling edge = button newly pressed (`old & ~new`) and
  selected by P1 bit 4/5. Add hardware-accurate IF high-bit read masks if the
  audit shows they are missing (`IF` bits 5–7 read as 1).

### 6.3 Dynarec backward-patch fix

- (a) `target -% (at + 4)` — wrapping subtraction, encodes two's-complement
  rel32; correct only if the backward jump is intentional.
- (b) Reorder emit/bind so every intra-block patch is forward.
- **Decision: evidence first.** Task 2 instruments the failing patch (label
  identity, `at`, `target`, `e.len`) and rules (a) or (b). A ruling is recorded
  in the ledger. Independently, patch-table overflow becomes a hard
  `Unsupported` result that rejects the block to interpreter fallback.

### 6.4 Performance re-measurement

- Report **both** T-cycles/sec (primary, as in P5 Task 7) and coverage %
  (translated instruction share). Benchmarks: `2048.gb` (pinned), Crystal and
  Pinball (user ROMs; SKIP when absent). Warm alternating 3-run medians. The
  docs verdict changes from "no gain" to a coverage-qualified statement.

### 6.5 `--frames` default

- (a) Keep `--frames 1` and fix docs only.
- (b) Default unlimited: windowed runs until quit/`Esc`; headless runs until
  `--frames N` or process termination. `--frames 0` means unlimited.
- **Decision (b).** Users emulate indefinitely; a finite default is a footgun.

### 6.6 MBC7 (`k_tt`, type `0x22`)

- Cartridge type `0x22` = MBC7 + accelerometer + rumble + RAM/EEPROM + battery.
- Required surface: MBC5-style 9-bit ROM banking; RAM/EEPROM enable at
  `0x0000-0x1FFF`; EEPROM (93LC56) bit-banged at `0xA080-0xA08F`
  (`CS`/`CLK`/`DI`/`DO`); accelerometer X/Y registers in the `0xA000-0xA01F`
  window; battery-backed EEPROM persistence.
- The exact register offsets and latch sequence must be pinned from Pan Docs
  and verified against `k_tt`'s boot code **before** implementation (Task 6
  Step 1); the published map is not assumed from memory.
- Accelerometer values are a fixed neutral orientation plus an `emuSetTilt(x, y)`
  seam used by tests. Real tilt input is Task 9 (operator-gated); until it is
  chosen, gameplay needing tilt is documented as unsupported and no progress is
  claimed beyond what is observed.
- MBC5 rumble types mask the RAM bank with `& 0x07`.

### 6.7 Task 9 options (operator-gated tilt input)

Presented at the Task 7 STOP; only one option is implemented, and only after the
operator picks it:

1. Gamepad analog (recommended) — DInput8 joystick X/Y axes, dead zone +
   calibration.
2. Keyboard digital tilt — four configurable keys (default `I/J/K/L`) ramping
   tilt at a bounded rate.
3. Mouse-relative tilt — windowed cursor delta maps to tilt.
4. Static `--tilt X,Y` — fixed orientation for calibration/tests.
5. Hybrid — gamepad when present, keyboard otherwise.
6. Decline — keep neutral; `k_tt` stays loadable-only.

A rumble sub-decision (on-screen/audio feedback vs ignore) is made at the same
time; the default recommendation is ignore-and-document, with no `sf/src`
coupling. Any chosen option extends `InputState` with `tilt_x`/`tilt_y` (no
`Platform` table field change), stays allocation-free, and requires manual
`k_tt` playtest evidence.

### 6.8 Test strategy

- Unit-level: `tests/irq_test.zig` (VBlank once/frame, LCD-off, joypad IRQ,
  IF read masks), MBC7 tests in the save/cart tier, dynarec patch regressions in
  `tests/dynarec_test.zig`.
- Integration: full `tier_dmg`, `tier_cgb`, `tier_dynarec`, `tier_smoke`,
  `tier_perf`.
- End-to-end evidence (Task 7, not committed): Crystal/Pinball/k_tt/k_dl render
  and run long under interpreter and dynarec.

## 7. Verification bar

- VBlank IF bit 0 asserted once per frame; LCD-off raises none; STAT VBlank bit
  consistent; joypad IRQ raises on a selected press and not otherwise.
- Pinball translates past the former trap frame with dynarec; interpreter and
  dynarec produce identical framebuffers.
- `tier_dmg --all` 49/49 (+ new cases), `tier_dmg --gates` 166/0,
  `tier_cgb` 18/18, `tier_dynarec` 26/0 (+ new regressions), `tier_smoke` 18/18,
  `tier_perf` with coverage data.
- `k_tt` loads (no `cannot read ROM`), EEPROM save round-trips across process
  restarts, and it executes past init as far as neutral sensors allow.
- All four user ROMs run long without a uniform screen (Crystal/Pinball/`k_dl`);
  documented per-ROM reachable state.
- Rebuilt `lin_bin/z9gb.exe` is the `-O2` binary and passes the Win9x import
  gate.

## 8. Risks

- VBlank timing granularity (instruction-boundary IRQ checks) is unchanged; the
  fix must not alter dot timing or the existing Mooneye PPU gates.
- Joypad IRQ can storm if raised on every write; the falling-edge rule bounds it.
- MBC7 register map guessed wrong would break `k_tt` silently; Step 1 pins it.
- Dynarec patch fix under `-fsafe` vs `-ffast` must stay semantically identical;
  parity tests run both modes.
- Perf re-measurement may still show a small gain; the report must state
  coverage, not just the number.
