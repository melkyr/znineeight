# Phase 4 P4 — Game Boy Color Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extend the DMG emulator to CGB: CGB palettes, VRAM/WRAM banking, double speed, HDMA, CGB sprite/BG attributes, and CGB APU behavior.

**Architecture:** The MMU grows from 8 KiB VRAM/8 KiB WRAM to 16 KiB VRAM/32 KiB WRAM with bank registers. CGB palette RAM/index state lives in `Bus`/MMU so the PPU can consume it without an `mmu`↔`ppu` import cycle; the PPU gains VRAM bank 1 attributes and CGB priority. The CPU gains `KEY1` double-speed switching and `STOP`; `emuRunFrame` counts dots while `cpuStep` counts current-speed T-cycles.

**Tech Stack:** Z98 only; P2/P3 modules; `cgb-acid2`, `cgb_sound`, `interrupt_time`, `2048.gb`; SameSuite CGB tests are optional probes only.

**Spec:** `docs/superpowers/specs/2026-11-10-phase4-project1-gameboy-design.md`

## Global Constraints

- CGB is additive: DMG mode and all P2/P3 gates must keep passing.
- No new std modules and no seed rotation in P4.
- No heap allocation; VRAM/WRAM/palette RAM are fixed arrays.
- 1 MiB stack remains a stack limit; CGB buffers are static.
- Test compiler: use the pinned `zig1_5_clean` with explicit `-I sf/src` for test builds that import std modules, or a v149-built compiler. Do not rebuild or rotate the seed in P4.
- `cgb-acid2` uses the exact 160x144 RGB32 golden derived from the official `mattcurrie/cgb-acid2` `img/reference.png` (release v1.1). The conversion is `(channel << 3) | (channel >> 2)` for each 5-bit CGB palette component. Missing ROM/golden is `SKIP`; closeout cannot claim the visual gate.
- `cgb_sound` is a hard gate using the Blargg SRAM memory protocol: status at `$A000`, signature `DE B0 61` at `$A001-$A003`, zero-terminated text at `$A004`. Missing ROM is `SKIP` and cannot close the milestone.
- `interrupt_time` is a CGB-only hard gate using the same Blargg SRAM memory protocol, not serial. It exercises both DMG-speed and CGB double-speed interrupt latency.
- Cartridge RAM is type-driven and tolerant of inconsistent headers: if the cartridge type includes RAM and the declared RAM size is zero, infer 8 KiB (`Cart.ram_inferred=true`); types without RAM stay unmapped at `$A000-$BFFF`; MBC2 is exempt when/if supported.
- Every CGB register has a documented read/write mask; no ignored writes silently.
- CGB mode state is explicit: `cgb_hw` = hardware selected by `--cgb`; `cgb_color` = CGB color mode for header `0x80`/`0xC0`; `cgb_compat` = header `0x00` with `--cgb` (CGB hardware in DMG compatibility, CGB registers inactive).
- Double speed (Pan Docs-verified): CPU, timer/divider, serial, and OAM DMA run at 2x; LCD/PPU dots, HDMA, and all sound timings stay at their normal rates. `STOP` stalls the CPU 2050 M-cycles (8200 T-cycles). PPU line timing is 456 dots regardless of speed.
- Clock split: `FRAME_CYCLES = 70224` is always **dots**. `cpuStep` returns current-speed CPU T-cycles; `emuRunFrame` accumulates dots and passes dot deltas to `ppuTick`; `busTick` derives APU/HDMA dots from `double_speed` (`cycles / 2` in double speed). Timer, serial, and OAM DMA continue to consume CPU T-cycles.
- General-purpose HDMA uses a CPU-stall counter drained by `cpuStep`. HBlank DMA is per-HBlank and does not halt the CPU.
- `-fsafe` arithmetic idiom (same binding as P2): shifts and wrapping math on `u32`/`u16` temps, mask-then-narrow, no `u8` shifts, masked `@intCast`; both `-ffast` and `-fsafe` build clean.
- CLI: `--cgb` sets `EmuConfig.cgb`; a CGB-only ROM (header `0x0143 == 0xC0`) without `--cgb` fails `CgbRequired` (CLI prints `z9gb: CgbRequired`, exit 2); gates run with `--cgb`.

## Review Focus

1. CGB mode detection and DMG compatibility; a CGB-only ROM must not silently run as DMG.
2. VRAM/WRAM bank switching and CGB attribute fetch; bank 1 must not corrupt tile data.
3. CGB palette RAM write/index auto-increment, read masks, and mode-3 lockout.
4. `KEY1`/`STOP` double-speed transition; CPU/timer/APU/PPU clock units stay coherent.
5. HDMA general/HBlank timing, CPU stall, source/destination masks, and VRAM bank selection.

---

### Task 0: Probe CGB test assets, headers, protocols, and golden reference

**Files:**
- Temporary only: `/tmp/phase4_p4_probe/*`

**Interfaces:**
- Consumes: P3 emulator and `/tmp/z9gb_roms`.
- Produces: CGB capability matrix, exact asset pins, and protocol/golden decisions.

- [ ] **Step 1: Inspect CGB headers**
Create temporary CGB ROMs with CGB flag `0x80` (DMG-compatible) and `0xC0` (CGB-only). Record current P3 behavior. Expected: P3 currently runs `0xC0` as DMG; P4 Task 1 adds `CgbRequired`.
- [ ] **Step 2: Probe exact assets**
Record present/absent and verify:
  - `cgb_sound/cgb_sound.gb` — **not `.gbc`**; 65,536 bytes; SHA-256 `de2101eb718a2bf5f778df76e73a63f4598d9b471559f9a85adc26efa692053b`; header `0xC0`.
  - `blargg/interrupt_time/interrupt_time.gb` — 32,768 bytes; SHA-256 `1a8f8f3bc609a92a5838214c00906c81e7cc77b3b9a63be5a1ec6d513f234929`; header `0xC0`.
  - `cgb-acid2.gbc` — release v1.1; 32,768 bytes; header `0xC0`; official `img/reference.png` available.
  - SameSuite CGB tests — record absent/present; optional only, never a hard gate.
- [ ] **Step 3: Probe memory protocol**
Run the pinned `cgb_sound` and `interrupt_time` ROMs headless and confirm:
  - status at `$A000`
  - `DE B0 61` at `$A001-$A003`
  - zero-terminated text at `$A004`
  - `$A000 == 0x80` while running
Record the exact pass/fail text. Do not assume serial output.
- [ ] **Step 4: Probe cgb-acid2 reference**
Download/verify the official `img/reference.png`; verify 160x144 and the CGB 5-bit conversion `(c << 3) | (c >> 2)`. Record the source URL, SHA-256, and derived 92,160-byte golden SHA-256.
- [ ] **Step 5: Probe double-speed timing references**
Record the `KEY1`/`STOP` sequence from the hardware docs used by the test ROMs. Expected: no guess; if the sequence is unclear, STOP.

---

### Task 1: CGB memory banking and mode

**Files:**
- Modify: `examples/z98/z9gb/cart.zig`
- Modify: `examples/z98/z9gb/mmu.zig`
- Modify: `examples/z98/z9gb/emu.zig`
- Modify: `examples/z98/z9gb/main.zig` (add `--cgb`)
- Create: `examples/z98/z9gb/tests/cgb_test.zig`
- Modify: `examples/z98/z9gb/tests/tier_dmg.sh` (synthetic MBC5 RAM fixture type `0x19` -> `0x1A`)
- Modify: `examples/z98/z9gb/tests/cpu_test.zig` (synthetic MBC1 RAM fixture type `0x01` -> `0x02`)
- Test: `examples/z98/z9gb/tests/tier_cgb.sh`

**Interfaces:**
- Consumes: P2 `Bus`/`Cart`.
- Produces:
  - `pub const CgbMode = enum(u8) { dmg, cgb_compatible, cgb_only };`
  - `pub fn cgbMode(c: *const Cart) CgbMode;`
  - `pub fn mmuSetVramBank(b: *Bus, bank: u8) void;`
  - `pub fn mmuSetWramBank(b: *Bus, bank: u8) void;`
  - `pub fn mmuVramBank(b: *const Bus) u8;`
  - `pub fn mmuWramBank(b: *const Bus) u8;`
  - `Bus.cgb_hw`, `Bus.cgb_color`, `Bus.cgb_compat` state.

- [ ] **Step 1: Write the failing test**
Tests: 16 KiB VRAM bank 0/1 read-back; 32 KiB WRAM bank 0-7 with `C000-CFFF` fixed and `D000-DFFF` switchable; `SVBK=0` maps to 1; CGB flag `0xC0` rejects DMG mode; `0x80` runs in CGB mode; `0x00` + `--cgb` runs CGB hardware in DMG compatibility; cartridge type includes RAM with declared size 0 infers 8 KiB (`interrupt_time` header); type without RAM keeps `$A000-$BFFF` unmapped even when declared size is nonzero; MBC2 is exempt. Expected: fails on missing banking/mode/RAM policy.
- [ ] **Step 2: Expand storage**
VRAM `[16384]u8`, WRAM `[32768]u8`; DMG mode uses only bank 0. `VBK=FF4F` bit 0; `SVBK=FF70` bits 0-2 (0 -> 1). Set `Bus.vram_bank`/`Bus.wram_bank` and rebuild page bases when they change.
Add `Cart.ram_inferred`; compute effective cart RAM at load:
  - type includes RAM and declared size nonzero → declared size;
  - type includes RAM and declared size zero → 8 KiB inferred;
  - type excludes RAM → zero even when a stray declared size is nonzero (MBC2 exempt when/if supported);
  - record inferred state for diagnostics/tests.
The synthetic P2 MBC5 RAM fixture in `tests/tier_dmg.sh` currently uses type `0x19` (MBC5, no RAM) with RAM code `0x04`; change that fixture header to `0x1A` (MBC5+RAM) so it matches the type-authoritative rule.
The synthetic P2 MBC1 RAM fixture in `tests/cpu_test.zig` currently uses `loadSyntheticRom(0x01, 0x02)` (MBC1, no RAM, with 8 KiB); change it to `loadSyntheticRom(0x02, 0x02)` (MBC1+RAM).


- [ ] **Step 3: Wire mode and the CLI flag**
`EmuConfig.cgb` selects CGB hardware. Semantics pinned by header `0x0143`:
  - `0xC0` (CGB-only) + `cfg.cgb=false` → `CgbRequired` (CLI prints `z9gb: CgbRequired`, exit 2).
  - `0x80` (CGB-compatible) + `cfg.cgb=true` → CGB color mode; `cfg.cgb=false` → DMG mode.
  - `0x00` (DMG-only) + `cfg.cgb=true` → CGB hardware in DMG compatibility: DMG palette/render, CGB palette and banking registers inactive.
Set `Bus.cgb_hw`, `Bus.cgb_color`, `Bus.cgb_compat` in `emuLoadRom`/`emuReset`. Implement `--cgb` in `main.zig` and specific `CgbRequired` reporting.
- [ ] **Step 4: Run**
Run `sh examples/z98/z9gb/tests/tier_cgb.sh "$ZIG" --all` and `sh examples/z98/z9gb/tests/tier_dmg.sh "$ZIG" --all`. Expected: PASS; DMG tests unchanged.
- [ ] **Step 5: Commit**
```bash
git add examples/z98/z9gb/cart.zig examples/z98/z9gb/mmu.zig examples/z98/z9gb/emu.zig examples/z98/z9gb/main.zig examples/z98/z9gb/tests/cgb_test.zig examples/z98/z9gb/tests/tier_cgb.sh examples/z98/z9gb/tests/tier_dmg.sh examples/z98/z9gb/tests/cpu_test.zig
git commit -m "feat(z9gb): add CGB mode and memory banking"
```

---

### Task 2: CGB palettes and PPU attributes

**Files:**
- Modify: `examples/z98/z9gb/ppu.zig`
- Modify: `examples/z98/z9gb/mmu.zig`
- Modify: `examples/z98/z9gb/tests/cgb_test.zig`
- Test: `examples/z98/z9gb/tests/tier_cgb.sh`

**Interfaces:**
- Consumes: `Bus.cgb_color`, VRAM bank 1, CGB palette RAM in `Bus`.
- Produces:
  - `pub fn cgbPaletteReset(b: *Bus) void;`
  - `pub fn cgbPaletteRead(b: *Bus, addr: u16) u8;`
  - `pub fn cgbPaletteWrite(b: *Bus, addr: u16, value: u8) void;`
  - `pub fn ppuCgbFramebuffer(p: *const Ppu) []const u32;` (the single 160x144 framebuffer the PPU renders into — the same storage `emuFramebuffer` exposes; no second/double buffer exists, CGB rendering replaces contents in place)

- [ ] **Step 1: Write the failing test**
Tests: BCPS/BCPD index auto-increment; OCPS/OCPD; palette color `0x7FFF` -> RGB32 `0x00FFFFFF`; BG attribute priority/VRAM bank/palettes; sprite attributes bank 1; DMG mode ignores CGB palettes; palette access blocked in mode 3. Expected: fails.
- [ ] **Step 2: Implement palette RAM**
Store 64 bytes background + 64 bytes object palette RAM in `Bus`; index registers bit 7 auto-increment; reads return the latched byte; writes masked to 6 bits. **Convert on write, not on pixel:** each palette-RAM write decodes the BGR555 word to an RGB32 value and stores it in a parallel 64-entry `cram_rgb` LUT in `Bus` (5-bit channels via `(c << 3) | (c >> 2)`). The renderer indexes `cram_rgb` directly. Model the CRAM Mode-3 lockout with a PPU-set `Bus.ppu_palette_blocked` flag: writes ignored, reads `0xFF`-class.
- [ ] **Step 3: Implement attributes**
VRAM bank 1 carries BG attributes (Pan Docs `Tile_Maps.md`): **bit 7 priority, bit 6 Y flip, bit 5 X flip, bit 3 VRAM bank, bits 2-0 CGB palette; bit 4 ignored** (readable/writable, no effect). Fetch the attribute, tile bank, flips, and palette **once per 8-pixel tile row** and reuse them for all 8 pixels. Sprite attributes use the same palette/bank fields with OBP; CGB sprite priority is **OAM order** (earlier OAM index wins), unlike DMG x-coordinate priority (`OPRI` FF6C bit 0 = 0 selects CGB-style; DMG-compat sets 1). BG-to-OBJ priority follows the three-flag truth table: if BG color index is 0 → OBJ wins; else if LCDC bit 0 clear → OBJ wins; else if both BG-attr bit 7 and OAM-attr bit 7 clear → OBJ wins; else BG color 1–3 wins (OAM bit 7 grants OBJ priority when **clear**). OBJ-vs-OBJ priority resolves before BG priority. DMG mode uses BGP/OBP0/OBP1 only.
- [ ] **Step 4: Run**
Run `tier_cgb --all` and `tier_dmg --all`. Expected: PASS; `dmg-acid2` golden still exact.
- [ ] **Step 5: Commit**
```bash
git add examples/z98/z9gb/ppu.zig examples/z98/z9gb/mmu.zig examples/z98/z9gb/tests/cgb_test.zig examples/z98/z9gb/tests/tier_cgb.sh
git commit -m "feat(z9gb): add CGB palettes and PPU attributes"
```

---

### Task 3: Double speed, STOP, and CGB timing

**Files:**
- Modify: `examples/z98/z9gb/cpu.zig`
- Modify: `examples/z98/z9gb/timer.zig`
- Modify: `examples/z98/z9gb/apu.zig`
- Modify: `examples/z98/z9gb/mmu.zig`
- Modify: `examples/z98/z9gb/emu.zig`
- Modify: `examples/z98/z9gb/tests/cgb_test.zig`
- Test: `examples/z98/z9gb/tests/tier_cgb.sh`

**Interfaces:**
- Consumes: `KEY1=FF4D`, `Bus.double_speed`.
- Produces:
  - `pub fn cgbSpeedSwitch(bus: *Bus) bool;`
  - `pub fn cgbIsDoubleSpeed(bus: *const Bus) bool;`
  - CPU `STOP` handling and dot-based `emuRunFrame`.

- [ ] **Step 1: Write the failing test**
Tests (Pan Docs `CGB_Registers.md` semantics): `KEY1` **bit 7 = current speed (read-only)**, **bit 0 = switch armed (R/W)**; setting bit 0 then executing `STOP` toggles speed and auto-clears bit 0; the CPU stalls 2050 M-cycles (8200 T-cycles) after `STOP`; timer ticks at the doubled CPU clock in double speed; PPU line remains 456 dots at either speed; APU frame sequencer keeps its normal rate at either speed. Expected: fails.
- [ ] **Step 2: Implement speed switch**
`KEY1` bit 0 arms the switch; `STOP` performs it when armed (then bit 0 clears; bit 7 flips to the new speed). Without an armed switch, `STOP` behaves as the plain stop/enter-idle case. Model the 2050 M-cycle stall after a speed-switching `STOP` (DIV does not tick during it; video-memory locking freezes per Pan Docs — minimally: CPU paused 8200 T-cycles, DIV frozen).
- [ ] **Step 3: Split clocks**
Keep `FRAME_CYCLES = 70224` as the dot budget. `emuRunFrame` accumulates dots: `dots += if (bus.double_speed) cpu_cycles / 2 else cpu_cycles`, and passes the dot delta to `ppuTick`. `busTick` continues to receive CPU T-cycles; APU and HDMA consume `cycles / 2` in double speed (normal real-time rates), while timer/divider, serial, and OAM DMA consume the original CPU T-cycles. PPU consumes dots (456 dots/line, never doubled). `emuRunFrame` still returns CPU T-cycles executed.
- [ ] **Step 4: Run**
Run `tier_cgb --all` and `tier_dmg --all`; both `-ffast` and `-fsafe`. Expected: PASS; DMG timing tests unchanged.
- [ ] **Step 5: Commit**
```bash
git add examples/z98/z9gb/cpu.zig examples/z98/z9gb/timer.zig examples/z98/z9gb/apu.zig examples/z98/z9gb/mmu.zig examples/z98/z9gb/emu.zig examples/z98/z9gb/tests/cgb_test.zig examples/z98/z9gb/tests/tier_cgb.sh
git commit -m "feat(z9gb): add CGB double speed and timing"
```

---

### Task 4: CGB HDMA

**Files:**
- Modify: `examples/z98/z9gb/cpu.zig`
- Modify: `examples/z98/z9gb/emu.zig`
- Modify: `examples/z98/z9gb/mmu.zig`
- Modify: `examples/z98/z9gb/ppu.zig`
- Modify: `examples/z98/z9gb/tests/cgb_test.zig`
- Test: `examples/z98/z9gb/tests/tier_cgb.sh`

**Interfaces:**
- Consumes: `HDMA1-5` `FF51-FF55`; `Bus.double_speed`.
- Produces:
  - `pub fn hdmaWrite(bus: *Bus, addr: u16, value: u8) void;`
  - `pub fn hdmaTick(bus: *Bus, dots: u32) void;`
  - `Bus.hdma.cpu_halt_cycles` drained by `cpuStep`.

- [ ] **Step 1: Write the failing test**
Tests (Pan Docs `CGB_Registers.md`): general-purpose DMA (bit 7 clear at start) copies all blocks, stalls the CPU until complete, and leaves `FF55 == 0xFF`; HBlank DMA (bit 7 set) copies one 16-byte block per HBlank and pauses during VBlank; source/destination low-nibble masks; **read** returns remaining blocks-1 while active and `0xFF` when complete (bit 7 read = 0 means active, 1 = not active); **abort** an active HBlank DMA by **writing 0 to bit 7** (e.g. `0x00`), after which the read returns remaining-1 in bits 0-6 with bit 7 reading 1; HALT pauses an active HBlank DMA. Expected: fails.
- [ ] **Step 2: Implement**
`HDMA1/2` source (lower 4 bits ignored; ROM/SRAM/WRAM ranges), `HDMA3/4` destination (lower 4 bits ignored, always VRAM `8000-9FF0`), `HDMA5` write: bits 0-6 = length/0x10 - 1 (`$00-$7F` → `0x10-0x800` bytes), bit 7 = mode (0 = general-purpose, CPU halted until done; 1 = HBlank). HBlank DMA transfers 16 bytes per HBlank (mode 0), ~8 M-cycles per block (16 fast M-cycles in double speed; HDMA rate is speed-independent in real time). General DMA sets `hdma.cpu_halt_cycles`; `cpuStep` drains it before executing instructions. Sample the destination VRAM bank at start; destination VRAM bank changes mid-transfer are unsupported (documented Pan Docs caveat). Do not start HBlank DMA during STAT mode 0 (documented warning).
- [ ] **Step 3: Run**
Run `tier_cgb --all` and `tier_dmg --all`. Expected: PASS; no VRAM outside `0x8000-0x9FFF` touched.
- [ ] **Step 4: Commit**
```bash
git add examples/z98/z9gb/cpu.zig examples/z98/z9gb/emu.zig examples/z98/z9gb/mmu.zig examples/z98/z9gb/ppu.zig examples/z98/z9gb/tests/cgb_test.zig examples/z98/z9gb/tests/tier_cgb.sh
git commit -m "feat(z9gb): add CGB HDMA"
```

---

### Task 4.5: CGB boot state and register defaults

**Files:**
- Modify: `examples/z98/z9gb/emu.zig`
- Modify: `examples/z98/z9gb/mmu.zig`
- Modify: `examples/z98/z9gb/tests/cgb_test.zig`
- Test: `examples/z98/z9gb/tests/tier_cgb.sh`

**Interfaces:**
- Consumes: `Bus.cgb_hw`, `Bus.cgb_color`, `Bus.cgb_compat`.
- Produces: CGB post-boot CPU/I/O state used by Blargg `interrupt_time` and CGB games.

- [ ] **Step 1: Write the failing test**
Tests: select CGB mode, then assert after `emuReset`:
  - `A=0x11, F=0x80, B=0x00, C=0x00, D=0xFF, E=0x56, H=0x00, L=0x0D, SP=0xFFFE, PC=0x0100`.
  - DMG mode still uses the P2 values (`A=0x01, F=0xB0, B=0x00, C=0x13, D=0x00, E=0xD8, H=0x01, L=0x4D`).
  - CGB post-boot I/O reads: `KEY1=0x7E`, `VBK=0xFE`, `SVBK=0xF9`, `OPRI=0xFE`, `HDMA5=0xFF`; DMG/CGB-compat behavior remains as Task 1–4 pinned.
Expected: fails on the current DMG reset values.

- [ ] **Step 2: Implement**
In `emuReset`, choose the CPU post-boot values from `e.bus.cgb_hw` (CGB values above, otherwise DMG values).
In `mmu.zig`, initialize the CGB boot I/O state and read masks: `KEY1` normal/not-armed (read `0x7E`), `VBK=0` (read `0xFE`), `SVBK=1` (read `0xF9`), `OPRI=0` (read `0xFE`), `HDMA5` inactive (`0xFF`). Do not change DMG behavior.
Blargg `interrupt_time` must then see `gb_id` CGB (`A` bit 4) and allow `cpu_fast`/`cpu_norm` to switch speed.

- [ ] **Step 3: Run**
Run `tier_cgb --all`, `tier_dmg --all`, and `run_cgb_interrupt_time.sh` with `--cgb --turbo --frames 200000`.
Expected: CGB/DMG tiers PASS; `interrupt_time` status `0` + terminal `Passed`. If the fast-speed measurement still fails after the boot-state fix, STOP and report the exact output; do not patch outside this task.

- [ ] **Step 4: Commit**
```bash
git add examples/z98/z9gb/emu.zig examples/z98/z9gb/mmu.zig examples/z98/z9gb/tests/cgb_test.zig examples/z98/z9gb/tests/tier_cgb.sh
git commit -m "feat(z9gb): add CGB boot state and defaults"
```

---

### Task 4.6: CGB APU semantics

**Files:**
- Modify: `examples/z98/z9gb/apu.zig`
- Modify: `examples/z98/z9gb/emu.zig`
- Modify: `examples/z98/z9gb/tests/cgb_test.zig`
- Test: `examples/z98/z9gb/tests/tier_cgb.sh`

**Interfaces:**
- Consumes: CGB color mode from `Bus.cgb_color`.
- Produces: CGB APU behavior and `apuSetCgb(a: *Apu, cgb: bool)` (or an equivalent explicit APU mode field) wired from `applyCgbMode`.

- [ ] **Step 1: Write the failing test**
Tests for CGB APU distinctions exercised by `cgb_sound` 08–12:
  - length counters reset on power-up (CGB) while DMG preserves them;
  - `NR11`/`NR21`/`NR31`/`NR41` length fields are readable in CGB mode (DMG masks them);
  - wave RAM reads while playing return the current byte on CGB (DMG garbage behavior unchanged);
  - wave trigger while already on works;
  - `NR12`/`NR13`/`NR41` clear after power cycle;
  - wave timer/phase/access behavior (frequency 0 valid, phase reset on trigger, current-byte access, write test).
Expected: fails on the DMG-only APU.

- [ ] **Step 2: Implement**
Add an explicit CGB APU mode and gate the CGB-specific behaviors on it; keep DMG behavior byte-identical. Do not change double-speed rates (APU stays normal real-time). Use `apuSetCgb`/mode field from `applyCgbMode`.
If a required CGB behavior is not covered by the test ROMs but is needed for DMG parity, keep it gated on CGB mode.

- [ ] **Step 3: Run**
Run `tier_cgb --all`, `tier_dmg --all`, and `run_cgb_sound.sh` with `--cgb --turbo --frames 200000`.
Expected: CGB/DMG tiers PASS; `cgb_sound` status `0` + terminal `Passed`. If it still fails, STOP with the exact subtest/status; do not patch outside this task.

- [ ] **Step 4: Commit**
```bash
git add examples/z98/z9gb/apu.zig examples/z98/z9gb/emu.zig examples/z98/z9gb/tests/cgb_test.zig examples/z98/z9gb/tests/tier_cgb.sh
git commit -m "feat(z9gb): add CGB APU semantics"
```

---

### Task 5: CGB gates and benchmark


**Files:**
- Modify: `examples/z98/z9gb/tests/tier_cgb.sh`
- Create: `examples/z98/z9gb/tests/run_cgb_acid2.sh`
- Create: `examples/z98/z9gb/tests/run_cgb_sound.sh`
- Create: `examples/z98/z9gb/tests/run_cgb_interrupt_time.sh`
- Create: `examples/z98/z9gb/testdata/golden/cgb-acid2.fb`
- Create: `examples/z98/z9gb/testdata/golden/cgb-acid2.sha256`
- Modify: `examples/z98/z9gb/testdata/golden/README.md`
- Modify: `examples/z98/z9gb/testdata/roms/manifest.sha256`
- Modify: `examples/z98/z9gb/testdata/roms/README.md`
- Test: `examples/z98/z9gb/tests/tier_cgb.sh`

**Interfaces:**
- Consumes: P4 core; official reference image.
- Produces: CGB hard gates and benchmark evidence.

- [ ] **Step 1: Add `cgb-acid2` gate**
Run `cgb-acid2.gbc` headless with `--cgb` for 120 frames; compare `--fb-out` to the committed 92,160-byte golden. Capture settings: CGB mode, frame 120, BCPD/OCPD palette data, official `mattcurrie/cgb-acid2` v1.1 `img/reference.png`, conversion `(c << 3) | (c >> 2)`, little-endian `u32` RGB32 dump. Missing ROM, reference image, or golden = `SKIP`; closeout cannot claim the visual gate.
- [ ] **Step 2: Add `cgb_sound` gate**
Run `cgb_sound/cgb_sound.gb` with `--cgb --turbo --frames 200000`. Use the Blargg SRAM memory protocol: poll `$A000` status, require `$A001-$A003 == DE B0 61`, read zero-terminated text at `$A004`. PASS = status `0`, text contains `Passed`, no `Failed`; any nonzero terminal status = fail code; cap without magic/verdict = FAIL. Missing ROM = `SKIP`; closeout cannot claim the audio gate.
- [ ] **Step 3: Add `interrupt_time` CGB gate**
Run `blargg/interrupt_time/interrupt_time.gb` with `--cgb --turbo --frames 200000`. Use the same `$A000` memory protocol, **not serial**. PASS requires status `0` and terminal `Passed`/`Passed all tests.`/`Passed all tests` with no `Failed`; cap without a verdict = FAIL. Missing ROM = `SKIP`; P4 closeout cannot claim PASS while this gate is skipped.
- [ ] **Step 4: Add a benchmark ROM**
Named benchmark homebrew: **`2048.gb`** (built from `Sanqui/2048-gb`, same pinned commit and zlib license as P3's homebrew gate — user-supplied bytes). Run 600 frames headless and windowed under Wine, in DMG mode and with `--cgb`. Record wall, CPU, RSS, and frames/sec (target clock 59.7275 Hz). No estimate is labeled measured; Wine numbers are labeled Wine, never Win98.
- [ ] **Step 5: Run**
Expected: `cgb-acid2` exact hash; `cgb_sound` PASS; `interrupt_time` PASS; benchmark numbers recorded.
- [ ] **Step 6: Commit**
```bash
git add examples/z98/z9gb/tests/tier_cgb.sh examples/z98/z9gb/tests/run_cgb_acid2.sh examples/z98/z9gb/tests/run_cgb_sound.sh examples/z98/z9gb/tests/run_cgb_interrupt_time.sh examples/z98/z9gb/testdata/golden examples/z98/z9gb/testdata/roms/manifest.sha256 examples/z98/z9gb/testdata/roms/README.md
git commit -m "test(z9gb): add CGB color, sound and interrupt gates"
```
---

### Task 6: P4 closeout

**Files:**
- Modify: `examples/z98/z9gb/README.md`
- Modify: `examples/z98/z9gb/tests/measure_rss.sh`
- Modify: `examples/z98/z9gb/tests/tier_perf.sh`
- Modify: `README.md`, `docs/sf/QUICK_REF.md` (CGB status)
- Test: `examples/z98/z9gb/tests/tier_cgb.sh`

**Interfaces:**
- Consumes: all P4 tasks.
- Produces: P4 evidence and truthful docs.

- [ ] **Step 1: Run all tiers**
Run `tier_smoke`, `tier_dmg`, `tier_audio`, `tier_win32`, `tier_cgb`. Expected: no DMG regression. Per spec §5.3, milestone closeout requires the hard gates **present and passing**: a `SKIP` (absent external ROM/golden) is recorded truthfully but the closeout may **not** claim PASS while any CGB hard gate is skipped — "close green with zero gates" is forbidden.
- [ ] **Step 2: Measure**
Run `measure_rss.sh --cgb` and `tier_perf.sh --cgb`; record RAM/CPU with CGB enabled. `measure_rss.sh` and `tier_perf.sh` must pass the CGB flag through to the CLI.
- [ ] **Step 3: Update docs**
README: CGB support, CGB-only requirement, double-speed, HDMA, palettes, gate commands, real-hardware caveat, official `cgb-acid2` golden provenance.
- [ ] **Step 4: Commit**
```bash
git add examples/z98/z9gb/README.md examples/z98/z9gb/tests/measure_rss.sh examples/z98/z9gb/tests/tier_perf.sh README.md docs/sf/QUICK_REF.md
git commit -m "docs(z9gb): record P4 CGB evidence"
```
