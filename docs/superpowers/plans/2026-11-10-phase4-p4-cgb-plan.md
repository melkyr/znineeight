# Phase 4 P4 — Game Boy Color Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extend the DMG emulator to CGB: CGB palettes, VRAM/WRAM banking, double speed, HDMA, CGB sprite/BG attributes, and CGB APU behavior.

**Architecture:** The MMU grows from 8 KiB VRAM/8 KiB WRAM to 16 KiB VRAM/32 KiB WRAM with bank registers. The PPU gains CGB palette RAM and VRAM bank 1 attributes. The CPU gains `KEY1` double-speed switching and `STOP`.

**Tech Stack:** Z98 only; P2/P3 modules; `cgb-acid2`, `cgb_sound`, SameSuite CGB tests, homebrew.

**Spec:** `docs/superpowers/specs/2026-11-10-phase4-project1-gameboy-design.md`

## Global Constraints

- CGB is additive: DMG mode and all P2/P3 gates must keep passing.
- No new std modules and no seed rotation in P4.
- No heap allocation; VRAM/WRAM/palette RAM are fixed arrays.
- 1 MiB stack remains a stack limit; CGB buffers are static.
- `cgb-acid2` uses the exact 160x144 RGB32 golden; missing golden is `SKIP`. The golden is pinned to exact capture settings (Task 5) so it is reproducible; a self-generated golden needs operator visual sign-off.
- `cgb_sound` is a hard gate with the verdict-harness semantics (turbo, generous cap, cap-without-result = FAIL); missing ROM is `SKIP` and cannot close the milestone.
- Every CGB register has a documented read/write mask; no ignored writes silently.
- Double speed (Pan Docs-verified): CPU, timer/divider, serial, and OAM DMA run at 2x; LCD/PPU dots, HDMA, and all sound timings stay at their normal rates. `STOP` stalls the CPU 2050 M-cycles (8200 T-cycles). PPU line timing is 456 dots regardless of speed.
- `-fsafe` arithmetic idiom (same binding as P2): shifts and wrapping math on `u32`/`u16` temps, mask-then-narrow, no `u8` shifts, masked `@intCast`; both `-ffast` and `-fsafe` build clean.
- CLI: `--cgb` sets `EmuConfig.cgb`; a CGB-only ROM (header `0x0143 == 0xC0`) without `--cgb` fails `CgbRequired`; gates run with `--cgb`.

## Review Focus

1. CGB mode detection and DMG compatibility; a CGB-only ROM must not silently run as DMG.
2. VRAM/WRAM bank switching and CGB attribute fetch; bank 1 must not corrupt tile data.
3. CGB palette RAM write/index auto-increment and read masks.
4. `KEY1`/`STOP` double-speed transition; timer/APU/PPU clocks stay coherent.
5. HDMA general/hblank timing and source/destination masks.

---

### Task 0: Probe CGB test assets and headers

**Files:**
- Temporary only: `/tmp/phase4_p4_probe/*`

**Interfaces:**
- Consumes: P3 emulator.
- Produces: CGB capability matrix.

- [ ] **Step 1: Inspect CGB headers**
Create temporary CGB ROMs with CGB flag `0x80` (DMG-compatible) and `0xC0` (CGB-only). Expected: P3 rejects CGB-only cleanly or runs DMG-compatible in DMG mode; record behavior.
- [ ] **Step 2: Probe assets**
Check `cgb-acid2.gbc`, `cgb_sound.gbc`, and SameSuite CGB tests in the manifest. Expected: record present/absent.
- [ ] **Step 3: Probe double-speed timing references**
Record the expected `KEY1`/`STOP` sequence from the hardware docs used by the test ROMs. Expected: no guess; if the sequence is unclear, STOP.

---

### Task 1: CGB memory banking and mode

**Files:**
- Modify: `examples/z98/z9gb/cart.zig`
- Modify: `examples/z98/z9gb/mmu.zig`
- Modify: `examples/z98/z9gb/emu.zig`
- Modify: `examples/z98/z9gb/main.zig` (add `--cgb`)
- Create: `examples/z98/z9gb/tests/cgb_test.zig`
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

- [ ] **Step 1: Write the failing test**
Tests: 16 KiB VRAM bank 0/1 read-back; 32 KiB WRAM bank 0-7 with `C000- CFFF` fixed and `D000-DFFF` switchable; `SVBK=0` maps to 1; CGB flag `0xC0` rejects DMG mode; `0x80` runs in CGB mode with DMG compatibility. Expected: fails on missing banking.
- [ ] **Step 2: Expand storage**
VRAM `[16384]u8`, WRAM `[32768]u8`; DMG mode uses only bank 0. `VBK=FF4F` bit 0; `SVBK=FF70` bits 0-2 (0 -> 1).
- [ ] **Step 3: Wire mode and the CLI flag**
`EmuConfig.cgb` selects CGB hardware. Semantics pinned by header `0x0143`:
  - `0xC0` (CGB-only) + `cfg.cgb=false` → `CgbRequired` (CLI prints `z9gb: CgbRequired`, exit 2).
  - `0x80` (CGB-compatible) + `cfg.cgb=true` → CGB mode; `cfg.cgb=false` → DMG mode.
  - `0x00` (DMG-only) + `cfg.cgb=true` → **CGB hardware in DMG compatibility** (runs; CGB registers inactive).
Implement `--cgb` in `main.zig` (sets `cfg.cgb`), and extend the CGB test to cover all three header/flag combinations and the `CgbRequired` exit code.
- [ ] **Step 4: Run**
Expected: PASS; DMG P2 tests unchanged.
- [ ] **Step 5: Commit**
```bash
git add examples/z98/z9gb/cart.zig examples/z98/z9gb/mmu.zig examples/z98/z9gb/emu.zig examples/z98/z9gb/main.zig examples/z98/z9gb/tests/cgb_test.zig examples/z98/z9gb/tests/tier_cgb.sh
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
- Consumes: VRAM bank 1, CGB palette RAM.
- Produces:
  - `pub fn cgbPaletteReset(p: *Ppu) void;`
  - `pub fn cgbPaletteRead(p: *Ppu, addr: u16) u8;`
  - `pub fn cgbPaletteWrite(p: *Ppu, addr: u16, value: u8) void;`
  - `pub fn ppuCgbFramebuffer(p: *const Ppu) []const u32;` (the single 160x144 framebuffer the PPU renders into — the same storage `emuFramebuffer` exposes; no second/double buffer exists, CGB rendering replaces contents in place)

- [ ] **Step 1: Write the failing test**
Tests: BCPS/BCPD index auto-increment; OCPS/OCPD; palette color `0x7FFF` -> RGB32 `0x00FFFFFF`; BG attribute priority/VRAM bank/ palettes; sprite attributes bank 1; DMG mode ignores CGB palettes. Expected: fails.
- [ ] **Step 2: Implement palette RAM**
64 bytes background + 64 bytes object; index registers bit 7 auto-increment; reads return the latched byte; writes masked to 6 bits. **Convert on write, not on pixel:** each palette-RAM write decodes the BGR555 word to an RGB32 value and stores it in a parallel 64-entry `cram_rgb` LUT (5-bit channels replicated to 8 bits). The renderer indexes `cram_rgb` directly. Model the CRAM Mode-3 lockout: palette-RAM access while the PPU is in mode 3 is blocked (writes ignored, reads open-bus/`0xFF`-class) per Pan Docs video-memory access rules.
- [ ] **Step 3: Implement attributes**
VRAM bank 1 carries BG attributes (Pan Docs `Tile_Maps.md`): **bit 7 priority, bit 6 Y flip, bit 5 X flip, bit 3 VRAM bank, bits 2-0 CGB palette; bit 4 ignored** (readable/writable, no effect). Fetch the attribute, tile bank, flips, and palette **once per 8-pixel tile row** and reuse them for all 8 pixels — never re-read the attribute map per pixel. Sprite attributes use the same palette/bank fields with OBP; CGB sprite priority is **OAM order** (earlier OAM index wins), unlike DMG x-coordinate priority (`OPRI` FF6C bit 0 = 0 selects CGB-style; DMG-compat sets 1). BG-to-OBJ priority follows the three-flag truth table: if BG color index is 0 → OBJ wins; else if LCDC bit 0 clear → OBJ wins; else if both BG-attr bit 7 and OAM-attr bit 7 clear → OBJ wins; else BG color 1–3 wins (OAM bit 7 grants OBJ priority when **clear**). OBJ-vs-OBJ priority resolves before BG priority. DMG mode uses BGP/OBP0/OBP1 only.
- [ ] **Step 4: Run**
Expected: PASS; `dmg-acid2` golden still exact.
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
- Modify: `examples/z98/z9gb/tests/cgb_test.zig`
- Test: `examples/z98/z9gb/tests/tier_cgb.sh`

**Interfaces:**
- Consumes: `KEY1=FF4D`.
- Produces:
  - `pub fn cgbSpeedSwitch(bus: *Bus) bool;`
  - `pub fn cgbIsDoubleSpeed(bus: *const Bus) bool;`
  - CPU `STOP` handling.

- [ ] **Step 1: Write the failing test**
Tests (Pan Docs `CGB_Registers.md` semantics): `KEY1` **bit 7 = current speed (read-only)**, **bit 0 = switch armed (R/W)**; setting bit 0 then executing `STOP` toggles speed and auto-clears bit 0; the CPU stalls 2050 M-cycles (8200 T-cycles) after `STOP`; timer ticks at the doubled CPU clock in double speed; PPU line remains 456 dots at either speed; APU frame sequencer keeps its normal rate at either speed. Expected: fails.
- [ ] **Step 2: Implement speed switch**
`KEY1` bit 0 arms the switch; `STOP` performs it when armed (then bit 0 clears; bit 7 flips to the new speed). Without an armed switch, `STOP` behaves as the plain stop/enter-idle case. Model the 2050 M-cycle stall after a speed-switching `STOP` (DIV does not tick during it; video-memory locking freezes per Pan Docs — minimally: CPU paused 8200 T-cycles, DIV frozen).
- [ ] **Step 3: Split clocks**
Keep `cpu_cycles` (current-speed T-cycles) and `dot_cycles` (constant 4.19 MHz dots). In double speed the CPU executes 2 `cpu_cycles` per dot. PPU consumes `dot_cycles` (456 dots/line, never doubled); timer and divider consume `cpu_cycles` (therefore 2x per frame in double speed); APU and HDMA derive from `dot_cycles` (normal rates). OAM DMA length scales with `cpu_cycles` (runs 2x fast).
- [ ] **Step 4: Run**
Expected: PASS; DMG timing tests unchanged.
- [ ] **Step 5: Commit**
```bash
git add examples/z98/z9gb/cpu.zig examples/z98/z9gb/timer.zig examples/z98/z9gb/apu.zig examples/z98/z9gb/mmu.zig examples/z98/z9gb/tests/cgb_test.zig examples/z98/z9gb/tests/tier_cgb.sh
git commit -m "feat(z9gb): add CGB double speed and timing"
```

---

### Task 4: CGB HDMA

**Files:**
- Modify: `examples/z98/z9gb/mmu.zig`
- Modify: `examples/z98/z9gb/ppu.zig`
- Modify: `examples/z98/z9gb/tests/cgb_test.zig`
- Test: `examples/z98/z9gb/tests/tier_cgb.sh`

**Interfaces:**
- Consumes: `HDMA1-5` `FF51-FF55`.
- Produces:
  - `pub fn hdmaWrite(bus: *Bus, addr: u16, value: u8) void;`
  - `pub fn hdmaTick(bus: *Bus, dots: u32) void;`

- [ ] **Step 1: Write the failing test**
Tests (Pan Docs `CGB_Registers.md`): general-purpose DMA (bit 7 clear at start) copies all blocks immediately and leaves `FF55 == 0xFF`; HBlank DMA (bit 7 set) copies one 16-byte block per HBlank and pauses during VBlank; source/destination low-nibble masks; **read** returns remaining blocks-1 while active and `0xFF` when complete (bit 7 read = 0 means active, 1 = not active); **abort** an active HBlank DMA by **writing 0 to bit 7** (e.g. `0x00`), after which the read returns remaining-1 in bits 0-6 with bit 7 reading 1; HALT pauses an active HBlank DMA. Expected: fails.
- [ ] **Step 2: Implement**
`HDMA1/2` source (lower 4 bits ignored; ROM/SRAM/WRAM ranges), `HDMA3/4` destination (lower 4 bits ignored, always VRAM `8000-9FF0`), `HDMA5` write: bits 0-6 = length/0x10 - 1 (`$00-$7F` → `0x10-0x800` bytes), bit 7 = mode (0 = general-purpose, CPU halted until done; 1 = HBlank). HBlank DMA transfers 16 bytes per HBlank (mode 0), ~8 M-cycles per block (16 fast M-cycles in double speed; HDMA rate is speed-independent in real time). Destination VRAM bank changes mid-transfer are unsupported (documented Pan Docs caveat). Do not start HBlank DMA during STAT mode 0 (documented warning).
- [ ] **Step 3: Run**
Expected: PASS; no VRAM outside `0x8000-0x9FFF` touched.
- [ ] **Step 4: Commit**
```bash
git add examples/z98/z9gb/mmu.zig examples/z98/z9gb/ppu.zig examples/z98/z9gb/tests/cgb_test.zig examples/z98/z9gb/tests/tier_cgb.sh
git commit -m "feat(z9gb): add CGB HDMA"
```

---

### Task 5: CGB gates and benchmark

**Files:**
- Modify: `examples/z98/z9gb/tests/tier_cgb.sh`
- Create: `examples/z98/z9gb/tests/run_cgb_acid2.sh`
- Create: `examples/z98/z9gb/tests/run_cgb_sound.sh`
- Create: `examples/z98/z9gb/testdata/golden/cgb-acid2.fb`
- Create: `examples/z98/z9gb/testdata/golden/cgb-acid2.sha256`
- Modify: `examples/z98/z9gb/testdata/roms/manifest.sha256`
- Test: `examples/z98/z9gb/tests/tier_cgb.sh`

**Interfaces:**
- Consumes: P4 core.
- Produces: CGB hard gates and benchmark evidence.

- [ ] **Step 1: Add `cgb-acid2` gate**
Run `cgb-acid2.gbc` headless with `--cgb` for 120 frames; compare `--fb-out` to the committed 92,160-byte golden. Capture settings are pinned for reproducibility: CGB mode, frame 120, the ROM's own palette data (BCPD/OCPD), little-endian `u32` RGB32 dump. Capture procedure: reference emulator in CGB mode (e.g. SameBoy/BGB under Wine) at the same frame, or self-captured golden with operator visual sign-off against cgb-acid2's documented final screen. Missing ROM or golden = `SKIP`; closeout cannot claim the visual gate.
- [ ] **Step 2: Add `cgb_sound` gate**
Blargg `cgb_sound` reports via its **SRAM memory protocol and screen, not serial** (verified against the test framework). The harness runs `--cgb --turbo --frames 200000` and polls the `$A000` region: Task 0 Step 1 probes the exact protocol in the pinned ROM (expected Blargg convention: magic `DE B0 61` at `$A000-$A002`, status byte at `$A003`, `0` = pass) and pins the layout in `run_cgb_sound.sh`; PASS = status `0`, any nonzero = fail code, cap without the magic = FAIL (timeout). The manifest pins the exact upstream filename and SHA-256 from the pinned Blargg commit (record the real extension; do not assume `.gbc`). Missing ROM = `SKIP`, and closeout cannot claim the audio gate.
- [ ] **Step 3: Add a benchmark ROM**
Named benchmark homebrew: **`2048.gb`** (built from `Sanqui/2048-gb`, same pinned commit and zlib license as P3's homebrew gate — user-supplied bytes). Run 600 frames headless and windowed under Wine, in DMG mode and with `--cgb`. Record wall, CPU, RSS, and frames/sec (target clock 59.7275 Hz). No estimate is labeled measured; Wine numbers are labeled Wine, never Win98.
- [ ] **Step 4: Run**
Expected: `cgb-acid2` exact hash; `cgb_sound` PASS; benchmark numbers recorded.
- [ ] **Step 5: Commit**
```bash
git add examples/z98/z9gb/tests/tier_cgb.sh examples/z98/z9gb/tests/run_cgb_acid2.sh examples/z98/z9gb/tests/run_cgb_sound.sh examples/z98/z9gb/testdata/golden examples/z98/z9gb/testdata/roms/manifest.sha256
git commit -m "test(z9gb): add CGB color and sound gates"
```

---

### Task 6: P4 closeout

**Files:**
- Modify: `examples/z98/z9gb/README.md`
- Modify: `README.md`, `docs/sf/QUICK_REF.md` (CGB status)
- Test: `examples/z98/z9gb/tests/tier_cgb.sh`

**Interfaces:**
- Consumes: all P4 tasks.
- Produces: P4 evidence and truthful docs.

- [ ] **Step 1: Run all tiers**
Run `tier_smoke`, `tier_dmg`, `tier_audio`, `tier_win32`, `tier_cgb`. Expected: no DMG regression. Per spec §5.3, milestone closeout requires the hard gates **present and passing**: a `SKIP` (absent external ROM/golden) is recorded truthfully but the closeout may **not** claim PASS while any CGB hard gate is skipped — "close green with zero gates" is forbidden.
- [ ] **Step 2: Measure**
Run `measure_rss.sh` and `tier_perf.sh`; record RAM/CPU with CGB enabled.
- [ ] **Step 3: Update docs**
README: CGB support, CGB-only requirement, double-speed, HDMA, palettes, gate commands, real-hardware caveat.
- [ ] **Step 4: Commit**
```bash
git add examples/z98/z9gb/README.md README.md docs/sf/QUICK_REF.md
git commit -m "docs(z9gb): record P4 CGB evidence"
```
