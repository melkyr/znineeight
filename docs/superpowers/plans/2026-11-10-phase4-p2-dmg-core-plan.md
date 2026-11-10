# Phase 4 P2 — Headless DMG Core Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn `z9gb` from a pattern generator into a headless DMG emulator: SM83 CPU, MMU, MBC1/MBC3+RTC/MBC5, scanline PPU, timers, interrupts, HALT, OAM DMA, serial harness, and battery saves.

**Architecture:** The CPU is a 256-case interpreter with a nested `0xCB` switch; the MMU routes a 64 KiB address space into fixed arrays and cartridge banks; the PPU renders one 456-cycle scanline at a time into the 160x144 RGB32 framebuffer. All state is static.

**Tech Stack:** Z98 only; `std.file` for ROM/save I/O; existing P1 `Emu`/`Platform`; Blargg, Mooneye, SameSuite, `dmg-acid2`.

**Spec:** `docs/superpowers/specs/2026-11-10-phase4-project1-gameboy-design.md`

## Global Constraints

- Pure Z98; no new compiler features.
- DMG only in P2. CGB mode is rejected or runs in DMG compatibility; CGB lands in P4.
- No heap allocation in CPU/PPU/MMU/timer hot paths. ROM, VRAM, WRAM, OAM, framebuffer, and save RAM are fixed arrays.
- 1 MiB stack limit: no large local arrays; all large state is static/global.
- No third-party ROM bytes are committed. External suites are user-supplied and hash-checked; missing suites are `SKIP`, never `PASS`.
- `dmg-acid2` compares the exact 160x144 RGB32 framebuffer against the committed golden hash; a missing golden is `SKIP`. The golden is pinned to the plan's exact palette and capture frame (Task 9.3, derived from the official reference image) so the hash is reproducible.
- Serial harness is the test transport; link cable is out of scope.
- Every `switch` over opcodes has an `else`; opcode constants are module-scope.
- `-fsafe` arithmetic idiom (mandatory in `z9gb` sources): shifts and wrapping math run on `u32`/`u16` temps, then mask and narrow. `u8` values are never shifted (`value << 8` on `u8` traps under `-fsafe`); DIV/TIMA wrap uses `& 0xFFFF` or `+%`; every `@intCast` is preceded by an explicit mask. Builds must pass under both `-ffast` and `-fsafe`.
- Tests run sequentially; no parallel spill-file use.
- No `sf/src` changes and no seed rotation in P2.

## Review Focus

1. CPU flags, half-carry, DAA, signed SP offset, and the HALT bug; Blargg `cpu_instrs` is the oracle.
2. MBC1 banking modes and MBC3 RTC latch semantics; a wrong bank must not silently read ROM0.
3. PPU mode timing and STAT/LYC interrupts; scanline rendering must not depend on host timing.
4. OAM DMA timing and source ranges; DMA must not read from VRAM or wrap incorrectly.
5. Save corruption: short/foreign `.sav`/`.rtc` must fail cleanly and never overwrite.

---

### Task 0: Probe headers, ROM sizes, and test assets

**Files:**
- Temporary only: `/tmp/phase4_p2_probe/*`
- Read: `examples/project1_phase4.txt` ROM table, `examples/z98/z9gb/testdata`

**Interfaces:**
- Consumes: P1 `Emu`.
- Produces: a recorded ROM header matrix and test-asset plan.

- [ ] **Step 1: Probe ROM header shapes**
Create three temporary 32 KiB files with MBC type bytes `0x00`, `0x01`, and `0x19`, ROM-size byte `0x00`, RAM-size byte `0x00`. Run P1's `emuLoadRom` (real size-checked copy into the fixed 8 MiB `Emu` buffer — P1 already provides this, plus `RomTooLarge`/`Io`). Expected: all accepted as 32 KiB; no size error.
- [ ] **Step 2: Probe 8 MiB limit**
Create a temporary 8 MiB file and an 8 MiB + 1 file. Expected: 8 MiB accepted; 8 MiB + 1 rejects `RomTooLarge`.
- [ ] **Step 3: Probe external suite presence**
Check `testdata/roms/manifest.sha256` paths for Blargg `cpu_instrs`, Mooneye timer/PPU, and `dmg-acid2`. Expected: record which are present; absent files are `SKIP`.
- [ ] **Step 4: Record the matrix**
Write the accepted/rejected header values and suite presence into the task report. If the 8 MiB boundary is wrong, STOP.

---

### Task 1: ROM header, cartridge interface, and MBC1

**Files:**
- Create: `examples/z98/z9gb/cart.zig`
- Modify: `examples/z98/z9gb/emu.zig`
- Create: `examples/z98/z9gb/testdata/synth/minimal.gb`
- Create: `examples/z98/z9gb/tests/gen_synth_roms.c`
- Test: `examples/z98/z9gb/tests/tier_dmg.sh`

**Interfaces:**
- Consumes: `Emu` fixed ROM buffer.
- Produces:
  - `pub const Cart = struct { /* rom ptr + fixed ram [131072]u8 + bank regs + cached window ptrs */ };`
  - `pub const CartError = error{ BadHeader, UnsupportedMbc, RomTooLarge, Io };`
  - `pub fn cartLoad(c: *Cart, bytes: []const u8) CartError!void;`
  - `pub fn cartRead(c: *Cart, addr: u16) u8;`
  - `pub fn cartWrite(c: *Cart, addr: u16, value: u8) void;`
  - `pub fn cartRamSize(c: *const Cart) usize;`
  - `pub fn cartSaveRam(c: *const Cart) []const u8;`
  - `pub fn cartLoadRam(c: *Cart, bytes: []const u8) bool;`
- **Cart RAM is a fixed `[131072]u8`** (MBC5 maximum); `ram_size` selects the active prefix (MBC3 ≤32 KiB, MBC5 ≤128 KiB). `cartRamSize`/save `.sav` use `ram_size` exactly; load rejects a size mismatch.
- Bank registers only recompute cached window pointers/offsets into the ROM/RAM buffers (`rom0_ptr`, `romx_ptr`, `ram_ptr`). **Never copy bank data.** Reads are one pointer/offset access.

- [ ] **Step 1: Write the failing test**
Add a tier case that builds a 32 KiB `minimal.gb`, loads it, and prints `cart ok mbc=0 rom=32768 ram=0`. Expected: fails because `cart.zig` does not exist.
- [ ] **Step 2: Implement the header parser**
Read title `0x0134-0x0143`, cartridge type `0x0147`, ROM size `0x0148`, RAM size `0x0149`, CGB flag `0x0143`. Accept 32 KiB to 8 MiB. Map `0x00` to no MBC, `0x01-0x03` to MBC1, `0x0F-0x13` to MBC3, `0x19-0x1E` to MBC5. Unknown types reject `UnsupportedMbc`.
- [ ] **Step 3: Implement MBC1**
Registers: RAM enable `0x0000-0x1FFF`, ROM bank `0x2000-0x3FFF` (5-bit), RAM bank/secondary `0x4000-0x5FFF` (2-bit), mode `0x6000-0x7FFF`. Model the three hardware edges exactly (Mooneye `emulator-only/mbc1/*` gates them):
  1. the 5-bit register value 0 reads as 1 **before** combining: `romx_bank = (upper2 << 5) | (lower5 == 0 ? 1 : lower5)` — so banks `0x20/0x40/0x60` are unreachable (they become `0x21/0x41/0x61`);
  2. the 2-bit register contributes **ROMX bits 5-6 in both modes**;
  3. in **mode 1** the 2-bit register additionally banks the **ROM0 window** (`0000-3FFF` → `rom0_ptr = base + (upper2 << 5) * 16K`), and selects 8 KiB RAM banks instead of contributing to ROMX.
Mode 0: 32 KiB ROM banking, RAM bank 0. RAM access requires enable `0x0A`.
- [ ] **Step 4: Implement the synthetic ROM**
`gen_synth_roms.c` writes `minimal.gb` with a valid header and a tiny program at `0x0100`:
`JP 0x0150`, then at `0x0150`: `LD SP,0xFFFE`, `XOR A`, `LD (0xC000),A`, `JP 0x0150`.
Commit the generated 32 KiB file.
- [ ] **Step 5: Run the test**
Run `bash examples/z98/z9gb/tests/tier_dmg.sh "$ZIG1" --only cart`. Expected: PASS and stdout `cart ok mbc=0 rom=32768 ram=0`.
- [ ] **Step 6: Commit**
```bash
git add examples/z98/z9gb/cart.zig examples/z98/z9gb/emu.zig examples/z98/z9gb/testdata/synth/minimal.gb examples/z98/z9gb/tests/gen_synth_roms.c examples/z98/z9gb/tests/tier_dmg.sh
git commit -m "feat(z9gb): add cartridge header and MBC1"
```

---

### Task 2: CPU base, ALU, flags, and DAA

**Files:**
- Create: `examples/z98/z9gb/cpu.zig`
- Create: `examples/z98/z9gb/mmu.zig` (Bus skeleton; Task 5 completes it)
- Create: `examples/z98/z9gb/tests/cpu_test.zig`
- Test: `examples/z98/z9gb/tests/tier_dmg.sh`

**Interfaces:**
- Consumes: `Cart` (Task 1).
- Produces:
  - `pub const Cpu = struct { a: u8, f: u8, b: u8, c: u8, d: u8, e: u8, h: u8, l: u8, sp: u16, pc: u16, ime: bool, halted: bool, halt_bug: bool, cycles: u64 };`
  - `pub fn cpuInit(cpu: *Cpu) void;`
  - `pub fn cpuStep(cpu: *Cpu, bus: *Bus) u32;`
  - `pub fn cpuSetBus(cpu: *Cpu, bus: *Bus) void;`
  - `pub const PageKind = enum(u8) { rom0, romx, vram, cart_ram, rtc, wram, echo, oam, io, hram };`
  - `pub const Page = struct { kind: PageKind, base: [*]u8 };`
  - `pub const Bus = struct { pages: [256]Page, wram: [8192]u8, hram: [127]u8, cart: *Cart, /* io stubs */ };`
  - `pub fn busInit(bus: *Bus, cart: *Cart) void;`
  - `pub fn read8(self: *Bus, addr: u16) u8;`
  - `pub fn write8(self: *Bus, addr: u16, value: u8) void;`
  - `pub fn read16(self: *Bus, addr: u16) u16;`
  - `pub fn write16(self: *Bus, addr: u16, value: u16) void;`
- **Bus design (no per-access mapping math):** a **256-entry page table of 256-byte pages** covering the full 64 KiB map (`256 × 256 B = 64 KiB`), indexed by `addr >> 8`. Each entry is `{kind, base}` with `base` pre-rebased so access is one index + `kind` switch + direct `base[addr & 0xFF]`. Bank switches rewrite the window's page entries (e.g. ROMX = pages `0x40`–`0x7F`); ordinary ROM/RAM access never compares address ranges or recomputes banks. Echo pages (`0xE0`–`0xFD`) alias WRAM through `base` (no per-access mirror math). Page `0xFE` is `oam` (offsets ≥ `0xA0` are the unusable region); page `0xFF` is `hram` with `0xFFFF` handled as IE inside the handler. The Task 2 skeleton initializes `rom0`/`romx`/`cart_ram`/`wram`/`hram`; Task 5 fills `vram`/`oam`/`io`/`echo` and `busTick`.

- [ ] **Step 1: Write the failing ALU tests**
Tests: ADD/ADC/SUB/SBC/AND/OR/XOR/CP for `0x00`, `0x0F`, `0x80`, `0xFF`; INC/DEC half-carry; DAA after add/sub; RLCA/RRCA/RLA/RRA; CPL/SCF/CCF; `ADD SP,e8` and `LD HL,SP+e8` signed offsets. Expected: fails because `cpu.zig` does not exist.
- [ ] **Step 2: Implement the `Bus` skeleton**
Create `mmu.zig` exactly as the Interfaces block describes (cart + WRAM + HRAM, `0xFF` stubs elsewhere). Expected: `cpu_test.zig` can now link `cpuStep(cpu, bus)` calls even though the ALU is missing.
- [ ] **Step 3: Implement register/flag helpers**
Store flags in F bits 7..4 (Z=0x80, N=0x40, H=0x20, C=0x10); bits 3..0 are zero. Implement 8-bit add/sub helpers that return value and flags; use `u16` intermediates.
- [ ] **Step 4: Implement the ALU opcode group**
`0x80-0xBF` ALU A,r; `0x00-0x3F` INC/DEC/LD; `0x07/0x0F/0x17/0x1F` rotates; `0x27` DAA; `0x2F/0x37/0x3F`; `0xE8` ADD SP; `0xF8` LD HL,SP+e8.
- [ ] **Step 5: Add cycle and length tables**
`const OP_LEN: [256]u8` and `const OP_CYCLES: [256]u8`; CB prefix length 2. Every switch has `else => unreachable`.
- [ ] **Step 6: Run the unit test**
Build with `-ffast` and `-fsafe`; expected: all ALU cases PASS, no traps.
- [ ] **Step 7: Commit**
```bash
git add examples/z98/z9gb/cpu.zig examples/z98/z9gb/mmu.zig examples/z98/z9gb/tests/cpu_test.zig examples/z98/z9gb/tests/tier_dmg.sh
git commit -m "feat(z9gb): add SM83 ALU, flags and Bus skeleton"
```

---

### Task 3: CPU loads, stack, jumps, and calls

**Files:**
- Modify: `examples/z98/z9gb/cpu.zig`
- Modify: `examples/z98/z9gb/tests/cpu_test.zig`
- Test: `examples/z98/z9gb/tests/tier_dmg.sh`

**Interfaces:**
- Consumes: `Bus`.
- Produces: full non-CB load/stack/control and immediate-ALU opcode coverage, with taken-branch cycle extras.

- [ ] **Step 1: Write the failing tests**
Tests: `LD r,r'`, `LD r,(HL)`, `LD (HL),r`, `LD (BC/DE/HL),A`, `LDH (a8),A`, `LD (a16),A`, `LD A,(a16)`, `LD SP,d16`, `LD SP,HL`, `PUSH/POP`, `JP a16`, `JP cc,a16`, `JR e8`, `JR cc,e8`, `CALL a16`, `CALL cc,a16`, `RET`, `RET cc`, `RETI`, `RST`, `JP (HL)`, `LD (a16),SP`, immediate ALU `ADD/ADC/SUB/SBC/AND/OR/XOR/CP A,d8` (`0xC6/0xCE/0xD6/0xDE/0xE6/0xEE/0xF6/0xFE`), and taken/not-taken cycle checks for `JR cc`, `JP cc`, `CALL cc`, `RET cc`.
Expected: fails on missing handlers.
- [ ] **Step 2: Implement 16-bit helpers**
`read16`/`write16` little-endian; stack push decrements SP by 2; pop increments; `RETI` sets IME.
- [ ] **Step 3: Implement control flow and cycle extras**
Conditional flags use Z/C only. `JR` offset is signed `i8`, PC relative to the next instruction. `JP (HL)` reads `HL`. The base cycle table stores the not-taken cost; when the condition is taken add the standard extra: `JR cc +4`, `JP cc +4`, `CALL cc +12`, `RET cc +12` T-cycles. `LD SP,HL` is 8 T-cycles. Immediate ALU opcodes are 8 T-cycles.
- [ ] **Step 4: Verify stack, PC, and cycles**
Unit test asserts SP before/after push/pop, return address bytes, `RETI` IME, and the taken/not-taken cycle totals above.
- [ ] **Step 5: Run the test**
Expected: PASS under `-ffast` and `-fsafe`.
- [ ] **Step 6: Commit**
```bash
git add examples/z98/z9gb/cpu.zig examples/z98/z9gb/tests/cpu_test.zig
git commit -m "feat(z9gb): add SM83 loads, stack and control flow"
```

---

### Task 4: CB-prefixed instructions

**Files:**
- Modify: `examples/z98/z9gb/cpu.zig`
- Modify: `examples/z98/z9gb/tests/cpu_test.zig`
- Test: `examples/z98/z9gb/tests/tier_dmg.sh`

**Interfaces:**
- Consumes: `Bus`.
- Produces: full `0xCB` set: RLC/RRC/RL/RR/SLA/SRA/SWAP/SRL, BIT, RES, SET.

- [ ] **Step 1: Write the failing tests**
For each CB group, test register and `(HL)` forms, flags, and the `0x00/0x7F/0x80/0xFF` boundaries. Expected: fails on missing CB switch.
- [ ] **Step 2: Implement the nested switch**
`switch (op2)` with 0x00-0x3F rotates/shifts, 0x40-0x7F BIT, 0x80-0xBF RES, 0xC0-0xFF SET. `BIT` sets Z from the bit and clears N/H; preserves C. `(HL)` forms add 8 cycles (BIT 12).
- [ ] **Step 3: Verify no local constants**
Opcode constants are module-scope; no local `const` case labels.
- [ ] **Step 4: Run the test**
Expected: PASS under `-ffast` and `-fsafe`.
- [ ] **Step 5: Commit**
```bash
git add examples/z98/z9gb/cpu.zig examples/z98/z9gb/tests/cpu_test.zig
git commit -m "feat(z9gb): add SM83 CB-prefixed instructions"
```

---

### Task 5: MMU, IO routing, and OAM DMA

**Files:**
- Modify: `examples/z98/z9gb/mmu.zig` (completes the Task 2 Bus skeleton)
- Modify: `examples/z98/z9gb/emu.zig`
- Modify: `examples/z98/z9gb/tests/cpu_test.zig`
- Test: `examples/z98/z9gb/tests/tier_dmg.sh`

**Interfaces:**
- Consumes: `Cart`, the Task 2 `Bus` skeleton (`busInit`/`read8`/`write8`/`read16`/`write16`).
- Produces (additions to `mmu.zig`):
  - `pub fn ioRead(self: *Bus, addr: u16) u8;`
  - `pub fn ioWrite(self: *Bus, addr: u16, value: u8) void;`
  - `pub fn busTick(self: *Bus, cycles: u32) void;`
  - full address routing (VRAM, OAM, echo RAM, `FEA0-FEFF`, IE at `FFFF`).

- [ ] **Step 1: Write the failing test**
Tests: ROM0/ROM1 reads, VRAM/WRAM read-back, echo mirroring, OAM read/write, HRAM, IE, and OAM DMA from `0xC000` to `0xFE00`. Expected: fails because the full routing/IO/DMA behavior does not exist in the skeleton.
- [ ] **Step 2: Implement address routing**
Ranges per spec. Echo maps `E000-FDFF` to `C000-DDFF`. `FEA0-FEFF` reads `0xFF` and writes ignored. IO routes to `ioRead`/`ioWrite`. `FFFF` is IE.
- [ ] **Step 3: Implement OAM DMA**
`FF46` write starts DMA; source masks to `0xFF00`. Transfer **one byte per M-cycle** (4 dots) for 160 M-cycles, driven from `busTick` (not an instant 160-byte copy). While DMA is active the CPU may access **only HRAM** (`FF80-FFFE`); all other bus reads return `0xFF` and writes are ignored (this is the hardware restriction, not just the OAM window). OAM access is blocked for the full duration; games run their DMA wait loops from HRAM.
- [ ] **Step 4: Implement IO defaults**
`FF00=0xCF`, `FF0F=0xE1`, `FF40=0x91`, `FF47=0xFC`, `FF48=0xFF`, `FF49=0xFF`, `FF4A=0x00`, `FF4B=0x00`, `FFFF=0x00`. Timer/PPU/APU registers are owned by their modules.
- [ ] **Step 5: Run the test**
Expected: PASS; DMA copies exactly 160 bytes and blocks OAM access while active.
- [ ] **Step 6: Commit**
```bash
git add examples/z98/z9gb/mmu.zig examples/z98/z9gb/emu.zig examples/z98/z9gb/tests/cpu_test.zig
git commit -m "feat(z9gb): add 64 KiB MMU and OAM DMA"
```

---

### Task 6: Timer, interrupts, HALT, and serial harness

**Files:**
- Create: `examples/z98/z9gb/timer.zig`
- Create: `examples/z98/z9gb/serial.zig`
- Modify: `examples/z98/z9gb/cpu.zig`
- Modify: `examples/z98/z9gb/mmu.zig`
- Modify: `examples/z98/z9gb/emu.zig`
- Test: `examples/z98/z9gb/tests/tier_dmg.sh`

**Interfaces:**
- Consumes: `Bus`.
- Produces:
  - `pub fn timerTick(t: *Timer, cycles: u32) void;`
  - `pub fn timerRead(t: *Timer, addr: u16) u8;`
  - `pub fn timerWrite(t: *Timer, addr: u16, value: u8) void;`
  - `pub fn serialReset(s: *Serial) void;`
  - `pub fn serialWrite(s: *Serial, addr: u16, value: u8) void;`
  - `pub fn serialTick(s: *Serial, cycles: u32) void;`
  - `pub fn serialTake(s: *Serial, out: []u8) usize;`
- **Superseded by Task 7:** Timer/Serial no longer store `ifr`; their IRQ-raising entry points take `*Bus` and call `busRaiseIrq`. Task 7 owns the interface change.

- [ ] **Step 1: Write the failing test**
Tests: DIV increments at 16384 Hz; any DIV write resets the 16-bit divider to zero (and the DIV-write falling edge can spuriously tick TIMA); TAC selects 4096/262144/65536/16384 Hz and TAC-write mux changes can glitch an extra TIMA tick; TIMA overflow holds 0 for one M-cycle (4 T-cycles), then reloads TMA and requests timer interrupt; HALT with IME=0 and pending interrupt triggers the HALT bug (PC double-fetch); `EI` takes effect only after the next instruction while `DI` cancels it; serial write logs `SB` and clears SC bit 7 after 8 cycles. Expected: fails on missing modules.
- [ ] **Step 2: Implement DIV/TIMA**
Keep a 16-bit internal divider; DIV is the high byte. Any write to DIV resets the entire 16-bit divider to 0 (the low byte must not survive — mooneye `div_write.gb` gates this). TAC enable bit 2 and clock select bits 0-1. TIMA increments on the selected falling edge; overflow reloads TMA and sets IF bit 2. Model the three hardware glitch edges exactly (TCAGBD/Pan Docs; gated by the Mooneye timer subset):
  1. the DIV-write reset can itself produce a falling edge on the selected bit — implement it as a real divider reset that may spuriously increment TIMA;
  2. a TAC write that changes enable/select can glitch an extra TIMA increment (muxed-signal falling edge): compute the selected-bit state before and after the write and count a falling edge if it changed 1→0;
  3. on overflow TIMA stays **0 for one M-cycle (4 T-cycles)** before the TMA reload + IF raise (not instant) — track a small reload-delay counter; reads during the window return 0.
All wrap math follows the `-fsafe` idiom (u16 temp + `& 0xFFFF` / `+%`).
- [ ] **Step 3: Implement interrupts and the EI delay**
At instruction boundaries, if IME and `IE & IF & 0x1F`:
push PC, clear IME, clear the IF bit, jump to the vector, add 20 cycles. If halted and IME=0 with a pending interrupt, set `halt_bug` and do not halt; the HALT bug must manifest in the **fetch path as a PC double-fetch** (the next opcode byte is fetched twice — the first fetch does not increment PC), which the CPU fetch implements explicitly; cover with one dedicated test. `EI` does not enable IME immediately: it arms a pending flag that takes effect only after the instruction following `EI` (spec §8.5; covered by the local EI-delay test). `DI` clears IME immediately and cancels a pending EI. `RETI` enables IME immediately. The Blargg `interrupt_time` ROM is CGB-only and deferred to P4.
- [ ] **Step 4: Implement post-boot state in `emuReset`**
`emuReset` (P1 facade) sets the documented DMG post-boot state from spec §8.5: `A=0x01, F=0xB0, B=0x00, C=0x13, D=0x00, E=0xD8, H=0x01, L=0x4D, SP=0xFFFE, PC=0x0100`, I/O registers at the Task 5 Step 4 defaults, `LY=0x91`. Add a test asserting these exact values after `emuReset`.
- [ ] **Step 5: Implement serial harness**
On `SC` write with bit 7: append `SB`, clear bit 7, schedule serial interrupt after 8 cycles. `serialTake` drains.
- [ ] **Step 6: Run the test**
Expected: PASS; timer and serial values match exact counts; post-boot register test green.
- [ ] **Step 7: Commit**
```bash
git add examples/z98/z9gb/timer.zig examples/z98/z9gb/serial.zig examples/z98/z9gb/cpu.zig examples/z98/z9gb/mmu.zig examples/z98/z9gb/emu.zig examples/z98/z9gb/tests/tier_dmg.sh
git commit -m "feat(z9gb): add timer, interrupts, HALT and serial harness"
```

---

### Task 7: DMG scanline PPU

**Files:**
- Create: `examples/z98/z9gb/ppu.zig`
- Modify: `examples/z98/z9gb/mmu.zig`
- Modify: `examples/z98/z9gb/cpu.zig`
- Modify: `examples/z98/z9gb/timer.zig`
- Modify: `examples/z98/z9gb/serial.zig`
- Modify: `examples/z98/z9gb/emu.zig`
- Test: `examples/z98/z9gb/tests/tier_dmg.sh`

**Interfaces:**
- Consumes: VRAM/OAM from `Bus`; framebuffer from `Emu`.
- Produces:
  - `pub fn ppuReset(p: *Ppu) void;`
  - `pub fn ppuTick(p: *Ppu, cycles: u32, bus: *Bus) void;`
  - `pub fn ppuRead(p: *Ppu, addr: u16) u8;`
  - `pub fn ppuWrite(p: *Ppu, addr: u16, value: u8, bus: *Bus) void;`
  - `pub fn ppuFramebuffer(p: *Ppu) []const u32;`
  - `pub fn busRaiseIrq(bus: *Bus, mask: u8) void;` (in `mmu.zig`; ORs into IF `io[0x0F]`)
  - Task 6 interface amendment folded here: `timerTick(t: *Timer, cycles: u32, bus: *Bus) void;`, `timerWrite(t: *Timer, addr: u16, value: u8, bus: *Bus) void;`, `serialWrite(s: *Serial, addr: u16, value: u8, bus: *Bus) void;`, `serialTick(s: *Serial, cycles: u32, bus: *Bus) void;`. Timer/Serial no longer store `ifr`; every IRQ raise goes through `busRaiseIrq`.

- [ ] **Step 1: Write the failing test**
Tests: mode sequence 2→3→0 per line; VBlank mode 1 at line 144; `LY=LYC` STAT; BG tile map and tile data; window; 8x8 and 8x16 sprites; sprite priority; window `WX=0`, `WX=1..6`, `WX=7`, `WX=166`, `WX=167` clipping; Pan Docs per-tile mode-3 OBJ penalty incl. same-tile suppression; LYC-write STAT IRQ; LCD re-enable enters mode 2. Expected: fails on missing PPU.
- [ ] **Step 2: Implement mode timing**
456 T-cycles per line, 154 lines. Mode 2 for 80 cycles; mode 1 (lines 144-153) for 4560 cycles. Mode 3 uses the **Pan Docs per-tile OBJ model**, not a literal per-sprite sum: base `172 + (SCX % 8) + (6 if the window starts on this line)`; group the ≤10 line sprites by the 8-pixel BG/window tile column they overlap; for each distinct tile column with at least one sprite add 6 once, plus the per-sprite right-of-fetcher term `max(0, pixels_right_of_obj_left_in_its_tile - 2)` charged once per tile, with each sprite's contribution capped at 11 (so `X=0` yields 11). Sum the distinct-tile contributions; mode 0 is the remainder. STAT mode bits/interrupts and LYC fire at these boundaries.
- [ ] **Step 3: Implement scanline rendering**
Render in **8-pixel tile-row batches** into a `[160]u8` shade buffer: fetch tile id + 2bpp row, expand 8 indices, write the row; window uses its internal line counter; sprites collected during OAM scan (≤10/line), DMG priority by X then OAM index, drawn with per-pixel BG/OBJ priority. Palette mapping uses a **`[4]u32` LUT recomputed only when BGP/OBP0/OBP1 is written** (not per pixel): `0 → 0x009BBC0F`, `1 → 0x008BAC0F`, `2 → 0x00306230`, `3 → 0x000F380F`. No per-pixel function calls.

Window clipping is computed once per line, not per pixel: `wx = WX`; `wx == 0` shifts the window by `SCX % 8`; `1 <= wx <= 6` clips `7 - wx` left pixels; visible start is `max(0, wx - 7)`; `wx >= 167` disables the window. Store `win_start_x`, `win_skip`, `win_visible_len`; render one partial first batch, then full 8-pixel batches.
- [ ] **Step 4: Implement registers**
`LCDC=FF40`, `STAT=FF41`, `SCY=FF42`, `SCX=FF43`, `LY=FF44`, `LYC=FF45`, `DMA=FF46`, `BGP=FF47`, `OBP0=FF48`, `OBP1=FF49`, `WY=FF4A`, `WX=FF4B`.

`ppuWrite` takes `*Bus`. On FF45 write: if the LCD is on, `LY == LYC`, and STAT bit 6 is set, call `busRaiseIrq(bus, 0x02)` immediately. On LCDC bit 7 `0→1`, reset line/dot and enter mode 2, mirroring the disable path.
- [ ] **Step 5: Run the test**
Expected: PASS for mode/LYC/BG/window/sprite synthetic cases, the per-tile mode-3 penalty, LYC-write IRQ, and LCD re-enable mode 2; `emuFramebuffer` is 160x144 RGB32.
- [ ] **Step 6: Commit**
```bash
git add examples/z98/z9gb/ppu.zig examples/z98/z9gb/mmu.zig examples/z98/z9gb/cpu.zig examples/z98/z9gb/timer.zig examples/z98/z9gb/serial.zig examples/z98/z9gb/emu.zig examples/z98/z9gb/tests/tier_dmg.sh
git commit -m "fix(z9gb): correct PPU window, timing and IRQ routing"
```

---

### Task 8: MBC3+RTC, MBC5, and battery saves

**Files:**
- Modify: `examples/z98/z9gb/cart.zig`
- Modify: `examples/z98/z9gb/mmu.zig`
- Create: `examples/z98/z9gb/save.zig`
- Modify: `examples/z98/z9gb/emu.zig`
- Test: `examples/z98/z9gb/tests/tier_dmg.sh`

**Interfaces:**
- Consumes: `Cart`, `Emu` (including the P1 `emuSaveBattery`/`emuLoadBattery` facade stubs, which currently return `error.Io`).
- Produces:
  - `pub fn rtcLatch(c: *Cart, value: u8) void;`
  - `pub fn rtcRead(c: *Cart, reg: u8) u8;`
  - `pub fn rtcWrite(c: *Cart, reg: u8, value: u8) void;`
  - `pub fn saveBattery(e: *Emu, rom_path: []const u8) EmuError!void;`
  - `pub fn loadBattery(e: *Emu, rom_path: []const u8) EmuError!void;`
  - `pub fn deriveSavePath(rom: []const u8, ext: []const u8, out: []u8) usize;`
  - This task extends Task 2's interfaces: `PageKind` gains `.rtc` (the Task 2 enum text is superseded); `Cart` gains `ram_bank: u8` (MBC3 4-bit select: `0x00-0x03` RAM bank, `0x08-0x0C` RTC register).
  The spec facade signatures stay exactly `emuSaveBattery(e: *Emu) EmuError!void` / `emuLoadBattery(e: *Emu) EmuError!void` (spec §8.2): this task fills in their P1 stubs so they call `saveBattery`/`loadBattery` with `e->save_path` when set by `emuSetSavePath`, otherwise with the path derived from the loaded ROM (spec: "`emuSetSavePath` overrides it"). No facade signature churn.

- [ ] **Step 1: Write the failing test**
Tests: MBC3 ROM/RAM bank selection, RTC latch/read with the frozen `rtc_fixed` clock (deterministic delta advancement, halt flag, day wrap 511→0, live-write/latched-read), RTC access gated by the RAM/RTC enable register (disabled reads `0xFF`, writes ignored), RTC-window mapping (`ram_bank` 8-12 maps `0xA0-0xBF` to `.rtc`; 0-3 keeps direct `.cart_ram`), MBC5 9-bit ROM bank and RAM bank, `.sav` round-trip, `.rtc` round-trip (anchor preserved), `.rtc` bytes 24..31 stay zero, short/corrupt `.rtc` rejects `SaveCorrupt`, and a save path with an existing file is not truncated on error.
- [ ] **Step 2: Implement MBC3**
`0x0000-0x1FFF` RAM/RTC enable; `0x2000-0x3FFF` ROM bank (0 maps to 1); `0x4000-0x5FFF` stores `value & 0x0F` in `cart.ram_bank` (0-3 RAM bank, 8-12 RTC register); `0x6000-0x7FFF` latch on `0x00→0x01`. `writeRaw` already calls `rebuildCartPages` after ROM-area writes; extend it to map pages `0xA0-0xBF` to `PageKind.rtc` when `mbc == .mbc3 and ram_bank >= 8`, otherwise to the existing direct `.cart_ram` pages. `readRaw`/`writeRaw` add a `.rtc` case: the selected RTC register is mirrored across `A000-BFFF` (Pan Docs); dispatch to `rtcRead`/`rtcWrite`. Normal cart RAM keeps the direct page-base path. RTC semantics (pinned):
- **Delta accumulation with an anchor:** RTC advances by adding host-elapsed whole seconds to the five counters whenever time is observed (latch/read/write), and re-anchors the host timestamp at that moment — no per-frame wall-clock reads. Writes go to the **live** counters; reads return the **latched copies**.
- **Halt flag** (register 0x0C bit 6) freezes accumulation while set. Day counter is 9 bits and **wraps 511→0** (no carry out).
- **Deterministic headless clock:** the internal `emuSetRtcFixed` seam freezes the RTC epoch so tests/benchmarks are reproducible; Task 9 exposes `--rtc-fixed <unix>` on top of it. Without it, RTC uses real host time and saves record the anchor.
- The `.rtc` header stores the **timestamp anchor** (last host-observed unix seconds) so load re-anchors correctly across sessions.
- [ ] **Step 3: Implement MBC5**
ROM bank 9 bits (`0x2000` low 8, `0x3000` bit 8), RAM bank 4 bits, RAM enable. Bank 0 is valid.
- [ ] **Step 4: Implement save format**
Use the spec's 32-byte `Z98RTC1` header exactly: magic `0..7`, version `8`, counters `9..13`, flags `14`, reserved `15`, **host timestamp anchor** `16..23`, and bytes `24..31` zero — **no CRC**. `.sav` is raw cart RAM. Win9x cannot overwrite via `MoveFileA` (fails if the destination exists) and `CopyFileA` is **not** in the import whitelist (`scripts/win32_cross/check_win9x_imports.sh:26` lists `DeleteFileA`/`MoveFileA`, no `CopyFileA`/`MoveFileExA`). The write sequence is therefore the backup dance, using only whitelisted imports (`std_file_pal.zig:33-34` already declares `DeleteFileA`/`MoveFileA`):
  1. write `PATH.tmp` fully and close it;
  2. `DeleteFileA(PATH.bak)` (ignore missing);
  3. `MoveFileA(PATH, PATH.bak)`;
  4. `MoveFileA(PATH.tmp, PATH)`;
  5. `DeleteFileA(PATH.bak)`.
On failure at 3/4, restore with `MoveFileA(PATH.bak, PATH)` so the previous file survives; never delete `PATH` without a surviving copy. Document the tiny rename window in the README: load-side validation (Step 1's `SaveCorrupt` checks) is the real corruption defense.
- [ ] **Step 5: Run the test**
Expected: PASS; corruption cases return `SaveCorrupt` and do not modify the original.
- [ ] **Step 6: Commit**
```bash
git add examples/z98/z9gb/cart.zig examples/z98/z9gb/mmu.zig examples/z98/z9gb/save.zig examples/z98/z9gb/emu.zig examples/z98/z9gb/tests/tier_dmg.sh
git commit -m "feat(z9gb): add MBC3 RTC, MBC5 and battery saves"
```

---

### Task 9: DMG integration and hard gates

**Files:**
- Modify: `examples/z98/z9gb/main.zig`
- Modify: `examples/z98/z9gb/emu.zig`
- Create: `examples/z98/z9gb/testdata/roms/README.md`
- Create: `examples/z98/z9gb/testdata/roms/manifest.sha256`
- Create: `examples/z98/z9gb/tests/run_blargg.sh`
- Create: `examples/z98/z9gb/tests/run_mooneye.sh`
- Create: `examples/z98/z9gb/tests/run_acid2.sh`
- Modify: `examples/z98/z9gb/tests/tier_dmg.sh`
- Test: `examples/z98/z9gb/tests/tier_dmg.sh`

**Interfaces:**
- Consumes: P2 core.
- Produces: `--serial`, `--frames`, `--rom`, `--save`, `--rtc-fixed <unix>`, and the external ROM runner.

- [ ] **Step 1: Write the failing gate**
`tier_dmg.sh --gates` runs the three gate scripts. Each missing ROM prints `SKIP: <path>` and exits 77; a present ROM must pass. Expected: fails because the scripts and CLI flags do not exist.
- [ ] **Step 2: Add CLI flags**
`--serial` mirrors serial bytes; `--mooneye` enables the `LD B,B` magic breakpoint: execution stops on opcode `0x40`, and the test passes only when the full mooneye Fibonacci signature matches — `B=3, C=5, D=8, E=13, H=21, L=34` (any other register set is a fail; checking `B=3` alone is not sufficient); `--frames N` runs N frames; `--turbo` runs frames as fast as the host allows (no pacing); `--rom PATH` loads and validates; `--rtc-fixed <unix>` calls `emuSetRtcFixed` before load; `--save` writes battery files at exit. No heap.
- [ ] **Step 3: Add the ROM manifest**
`manifest.sha256` lists exact paths and hashes for:
  - `blargg/cpu_instrs/cpu_instrs.gb`
  - `blargg/instr_timing/instr_timing.gb`
  - `blargg/mem_timing/mem_timing.gb`
  - `blargg/interrupt_time/interrupt_time.gb` (CGB-only header `0xC0`; deferred to P4, not a P2 gate)
  - `mooneye/acceptance/timer/div_write.gb`
  - `mooneye/acceptance/timer/tim00.gb`, `tim01.gb`, `tim10.gb`, `tim11.gb`
  - `mooneye/emulator-only/mbc1/bits_bank1.gb`, `bits_bank2.gb`, `bits_mode.gb`, `bits_ramg.gb`
  - `mooneye/emulator-only/mbc1/rom_2Mb.gb`, `rom_4Mb.gb`, `ram_256kb.gb` (mode-1 ROM0 banking + 2-bit upper-bank edges)
  - `mooneye/acceptance/ppu/lcdon_timing-GS.gb`
  - `mooneye/acceptance/ppu/stat_irq_blocking.gb`
  - `mooneye/acceptance/oam_dma/basic.gb`
  - `acid2/dmg-acid2.gb`
`README.md` records the pinned commits from the spec. Task 0 verifies these exact filenames against the pinned Mooneye commit and records any rename in the manifest; a missing filename is a plan STOP, not a silent SKIP. The `mbc1` rows gate the three MBC1 mode-1 edges of Task 1.
- [ ] **Step 4: Add the gate runners**
  - `run_blargg.sh`: Blargg verdicts need minutes of emulated time (`cpu_instrs` = ~11 sub-tests × tens of seconds each ≈ 20,000+ frames); a 600-frame run can never reach one. Run each ROM with `--serial --turbo --frames 200000` (≈56 emulated minutes; turbo makes this minutes of wall time). The emulator exits early when the serial stream reaches a terminal Blargg verdict line (`Passed`, `Passed all tests.`, or `Failed`). PASS requires the exact terminal `Passed` or `Passed all tests.` and no `Failed`; reaching the frame cap without a verdict is FAIL (timeout), never PASS.
  - `run_mooneye.sh`: run each ROM with `--mooneye --frames 60000`; the `LD B,B` breakpoint fires long before the cap. PASS requires the full Fibonacci register signature `B=3, C=5, D=8, E=13, H=21, L=34`; anything else is FAIL.
  - `run_acid2.sh`: compare `--fb-out` against `testdata/golden/dmg-acid2.fb` via `sha256sum` (plus byte-size `92160`).
- [ ] **Step 5: Add the golden**
The golden must be pinned to exact render settings or no external emulator's output can ever hash-match:
  - DMG palette: the four canonical greens rendered as RGB32 `0x009BBC0F`, `0x008BAC0F`, `0x00306230`, `0x000F380F`, i.e. BGP/OBP0/OBP1 = `0xE4` defaults mapped shade 0..3 light-to-dark.
  - Capture frame: frame 120 (2 emulated seconds after `emuReset` with LCD on), CGB disabled (DMG mode), 160x144 little-endian `u32` dump, 92,160 bytes.
Commit `testdata/golden/dmg-acid2.fb` (92,160 bytes) plus `dmg-acid2.sha256`. The golden source is superseded by Task 9.3: derive it from the test author's official `img/reference-dmg.png` and the `$FF/$AA/$55/$00` mapping, not from our emulator. If no golden can be committed, the gate is `SKIP` and P2 closeout cannot claim PASS.
- [ ] **Step 6: Run**
Run `bash examples/z98/z9gb/tests/tier_dmg.sh "$ZIG1" --gates`. Expected: all present gates PASS; absent assets SKIP.
- [ ] **Step 7: Commit**
```bash
git add examples/z98/z9gb/main.zig examples/z98/z9gb/emu.zig examples/z98/z9gb/testdata/roms examples/z98/z9gb/testdata/golden examples/z98/z9gb/tests
git commit -m "test(z9gb): add DMG hard gates and ROM manifest"
```

---

### Task 9.1: CPU/bus timing, STOP, BIT, timer reload and gate verdicts

**Files:**
- Modify: `examples/z98/z9gb/cpu.zig`
- Modify: `examples/z98/z9gb/main.zig`
- Modify: `examples/z98/z9gb/mmu.zig`
- Modify: `examples/z98/z9gb/timer.zig`
- Modify: `examples/z98/z9gb/tests/cpu_test.zig`
- Modify: `examples/z98/z9gb/tests/run_blargg.sh`
- Modify: `examples/z98/z9gb/tests/tier_dmg.sh`
- Test: `examples/z98/z9gb/tests/tier_dmg.sh`

**Interfaces:**
- Consumes: `Cpu`, `Bus`, timer; Task 9 gate runners.
- Produces: STOP as a 2-byte instruction; M-cycle bus timing; interrupt dispatch timing; hardware TIMA reload timing; `BIT` H flag; Blargg terminal-verdict matching. P2 gates: `cpu_instrs`, `instr_timing`, `mem_timing`. `interrupt_time` is CGB-only and deferred to P4.

- [ ] **Step 1: Write the failing gate run**
Run `run_blargg.sh` for the three P2 Blargg ROMs (`cpu_instrs`, `instr_timing`, `mem_timing`). Expected: current FAIL/SIGTRAP/no-verdict.
- [ ] **Step 2: Implement STOP**
`0x10` consumes 2 bytes, advances PC past both, executes in 4 T-cycles, and does not trap. DMG STOP has no speed switch; CGB speed-switch behavior remains P4.
- [ ] **Step 3: Correct the TIMA reload delay**
Pan Docs: TIMA stays `$00` for **one M-cycle = 4 T-cycles** after overflow, then TMA is copied and IF bit 2 is raised. Set the reload delay to `4` T-cycles in `timer.zig`; reads during the window return 0. Update `testOverflow` in `tier_dmg.sh` from `tick(15)`/`tick(1)` to `tick(3)`/`tick(1)` and rename the check to `overflow holds 1 mcycle`.
- [ ] **Step 4: Correct `BIT` H**
`BIT` sets `H=1` and leaves `N=0`; `C` is unchanged. Update the `cpu_test.zig` `BIT` flag expectations from `H=false` to `H=true`.
- [ ] **Step 5: Accept both Blargg terminal verdicts**
`main.zig` must also treat `Passed` and `Passed all tests.` as terminal PASS lines and exit before the frame cap; `run_blargg.sh` must accept the same two terminal verdicts. Remove `blargg/interrupt_time` from the P2 Blargg list because that ROM is CGB-only (header `0xC0`) and deferred to P4. Any `Failed` line or cap without a verdict is FAIL. Do not weaken the gate or skip a ROM.
- [ ] **Step 6: Place bus accesses at M-cycle boundaries**
Replace instruction-atomic post-tick timing: every external bus access is preceded by the correct 4-T-cycle bus time, and internal cycles tick the bus at their instruction-specific points. Do not tick the whole instruction after the fact and do not double-tick. The timer/DIV/IF paths must observe accesses in the order the CPU performs them.
- [ ] **Step 7: Fix interrupt dispatch timing**
Keep the 20-cycle dispatch cost, but place those cycles on the bus at the same points as the hardware sequence (push and vector fetch), so P2 interrupt latency is correct.
- [ ] **Step 8: Run**
Run the three P2 Blargg gates (`cpu_instrs`, `instr_timing`, `mem_timing`) plus `tier_dmg --all` under `-ffast` and `-fsafe`. Expected: all three P2 gates PASS; existing tier stays green. P2 DMG interrupt-latency coverage remains `testInterruptDispatch`, `testEiDelay`, and `testHaltBug` in `tier_dmg.sh`; keep them green. `interrupt_time` is CGB-only, moved to P4 as a hard CGB gate, and is not run in P2.
- [ ] **Step 9: Commit**
```bash
git add examples/z98/z9gb/main.zig examples/z98/z9gb/cpu.zig examples/z98/z9gb/mmu.zig examples/z98/z9gb/timer.zig examples/z98/z9gb/tests/cpu_test.zig examples/z98/z9gb/tests/run_blargg.sh examples/z98/z9gb/tests/tier_dmg.sh
git commit -m "fix(z9gb): correct CPU timing, STOP and timer reload"
```

---

### Task 9.2: PPU STAT line and LCD-on timing

**Files:**
- Modify: `examples/z98/z9gb/ppu.zig`
- Modify: `examples/z98/z9gb/emu.zig`
- Modify: `examples/z98/z9gb/tests/tier_dmg.sh`
- Test: `examples/z98/z9gb/tests/tier_dmg.sh`

**Interfaces:**
- Consumes: PPU, `busRaiseIrq`, Task 9 runners.
- Produces: STAT line state; rising-edge STAT IRQ; LCD-on mode-2 timing. Gates `lcdon_timing-GS`, `stat_irq_blocking`.

- [ ] **Step 1: Write the failing gate run**
Run `run_mooneye.sh` for `lcdon_timing-GS` and `stat_irq_blocking`. Expected: current FAIL/no-breakpoint.
- [ ] **Step 2: Implement the STAT line**
Track the combined STAT condition (mode bits + LYC coincidence) as a line. Raise `busRaiseIrq(bus, 0x02)` only on a `0→1` transition; while the line is high, new source conditions do not re-fire. Clear it when the condition goes low.
- [ ] **Step 3: Correct LCD-on timing**
On LCDC bit 7 `0→1`, reset the line/dot counters and enter the documented mode-2 start at the correct dot; on `1→0`, enter mode 0/VBlank-off state. LYC writes still use the Task 7 immediate-write rule.
- [ ] **Step 4: Run**
Run both Mooneye PPU gates plus `tier_dmg --all` under `-ffast` and `-fsafe`. Expected: both present gates PASS; existing tier stays green.
- [ ] **Step 5: Commit**
```bash
git add examples/z98/z9gb/ppu.zig examples/z98/z9gb/emu.zig examples/z98/z9gb/tests/tier_dmg.sh
git commit -m "fix(z9gb): block STAT interrupts on the line edge"
```

---

### Task 9.3: dmg-acid2 golden from the official reference

**Files:**
- Create: `examples/z98/z9gb/testdata/golden/dmg-acid2.fb`
- Create: `examples/z98/z9gb/testdata/golden/dmg-acid2.sha256`
- Create: `examples/z98/z9gb/testdata/golden/README.md`
- Test: `examples/z98/z9gb/tests/run_acid2.sh`

**Interfaces:**
- Consumes: `dmg-acid2.gb` from `/tmp/z9gb_roms/acid2/dmg-acid2.gb`; Task 9 runner.
- Produces: committed 92,160-byte DMG golden and provenance. Gate `dmg-acid2`.

- [ ] **Step 1: Fetch the official reference**
Download `https://github.com/mattcurrie/dmg-acid2/raw/master/img/reference-dmg.png` to `/tmp`, record its SHA-256, and verify it is 160x144. This is the author's canonical output; do not use our emulator as the source.
- [ ] **Step 2: Map the author's comparison values**
The README pins greyscale/RGB components `$FF`, `$AA`, `$55`, `$00`. Map `$FF→0x009BBC0F`, `$AA→0x008BAC0F`, `$55→0x00306230`, `$00→0x000F380F` (shades 0..3, light-to-dark). Any other value is an error/STOP; do not guess.
- [ ] **Step 3: Emit the golden**
Write 160x144 little-endian `u32` pixels (92,160 bytes) to `testdata/golden/dmg-acid2.fb`; write `dmg-acid2.sha256`; document the source URL, image SHA-256, mapping, and frame-120 settings in `testdata/golden/README.md`. Commit only the derived golden/hash/README, never the PNG or ROM.
- [ ] **Step 4: Run the gate**
Run `run_acid2.sh` with `Z9GB_ROM_DIR=/tmp/z9gb_roms`. Expected: PASS, 92,160 bytes, matching SHA-256.
- [ ] **Step 5: Commit**
```bash
git add examples/z98/z9gb/testdata/golden examples/z98/z9gb/tests/run_acid2.sh
git commit -m "test(z9gb): derive dmg-acid2 golden from official reference"
```

---

### Task 10: P2 closeout

**Files:**
- Modify: `examples/z98/z9gb/README.md`
- Modify: `README.md`, `docs/sf/QUICK_REF.md` (P2 status)
- Test: `examples/z98/z9gb/tests/tier_dmg.sh`

**Interfaces:**
- Consumes: all P2 tasks.
- Produces: recorded P2 evidence and truthful docs.

- [ ] **Step 1: Run the full P2 tier and hard gates**
Run `bash examples/z98/z9gb/tests/tier_dmg.sh "$ZIG1" --all` and then `bash examples/z98/z9gb/tests/tier_dmg.sh "$ZIG1" --gates`. Expected: both PASS; all present hard gates PASS; `dmg-acid2` is not SKIP. A skipped hard gate blocks closeout.
- [ ] **Step 2: Run the corpus and RSS**
Run the corpus dump, `measure_rss.sh`, and the three-run framebuffer determinism check. Expected: dump rc 0; RSS recorded; framebuffer identical.
- [ ] **Step 3: Record evidence**
Write exact commands, rc, PASS/SKIP counts, `dmg-acid2` hash, and `rss_kb` into the task report. Do not claim synthetic ROMs as external suite passes.
- [ ] **Step 4: Update docs**
README: P2 status, supported MBCs, save behavior (including the `.rtc` rename window), gate commands, external ROM setup. Matrix counts remain truthful.
- [ ] **Step 5: Commit**
```bash
git add examples/z98/z9gb/README.md README.md docs/sf/QUICK_REF.md
git commit -m "docs(z9gb): record P2 DMG core evidence"
```
