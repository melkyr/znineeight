# Algorithm/Architecture Review — Phase 4 Game Boy Emulator Plans (2026-11-10)

**Reviewer:** independent algorithm-architecture reviewer (review-only)
**Scope:** algorithms and data structures ONLY in spec §8 and plans P2–P5. Plan
completeness, task structure, testing process, docs, and Win9x process concerns
are out of scope (see p1–p5-review.md; their process findings ignored).
**Constraint set (assumed verified):** pure Z98; per-module C translation units,
gcc `-std=c89 -pedantic -O2`, no LTO (verified `build_target.sh:5-21`); 32-bit
x86 Pentium II-class Win98; 4.19 MHz DMG / 8.38 MHz CGB double speed; 12 MiB
RSS; 1 MiB stack; 1 MiB dynarec code cache.
**Method:** VERDICT per section (optimal / standard-but-not-optimal / naive /
wrong), 2-8 lines reasoning, reference practice cited (Gambatte, SameBoy,
binjgb, MAME GB, Pan Docs/TCAGBD, DOSBox dynamic core, Pokemon Stadium GB
Tower JIT). In-repo facts cited file:line. Unverifiable claims marked
UNVERIFIED.

---

## 1. CPU interpreter: 256-case switch + OP_LEN/OP_CYCLES tables + packed flags + u16/u32 intermediates

**VERDICT: optimal (within constraints).**

- Switch dispatch is the right choice here. gcc -O2 turns a dense `u8` switch
  into a jump table; a function-pointer table adds call/ret per instruction and
  blocks fall-through; both cost more on a P6 than `jmp *table(,%eax,4)`.
  Computed-goto/threaded dispatch is **unavailable**: emitted C is `-std=c89
  -pedantic` (`build_target.sh:5`), which rejects GCC label-as-value, and Z98
  has no computed goto. Per-op microcode adds an indirection layer with no
  upside at 4.19 MHz.
- 256-case primary + nested `0xCB` switch is exactly the Gambatte/SameBoy/binjgb
  shape; module-scope opcode constants (p2:135, p2:193) are a Z98 case-label
  limitation, not an algorithmic cost.
- Packed flags in F bits 7..4 (p2:131) matches hardware, makes PUSH AF/DAA
  direct, and is what every accurate core does; u16/u32 intermediates are
  required anyway by the `-fsafe` idiom (p2:23) and are the standard way to
  compute half-carry.
- One unpinned detail that the gates depend on: **where inside an instruction
  side effects land** (instruction-granularity models must still apply a DIV/
  TIMA/TAC write at the correct M-cycle offset for Mooneye `tim*`/`div_write`).
  The plan never pins the convention. Important detail, not a design flaw.

## 2. MMU/bus: page-descriptor table {kind, base}

**VERDICT: standard-but-not-optimal; one internal inconsistency to fix.**

- Page-descriptor table with direct `base[addr & 0xFFF]` deref for ROM/WRAM/
  cart-RAM beats flat if-chains (MAME GB style) on a P6 and is the right shape
  for the dynarec to mirror inline. Bank switches rewriting 2–4 entries, never
  copying bank data (p2:79, p2:124), is correct and optimal. Notably `read8`
  never nests into `cartRead` — the right no-LTO hot-path structure.
- **Inconsistency:** "256-entry 4 KiB page table indexed by `addr >> 12`"
  (p2:124) cannot both hold — `addr >> 12` selects 16 entries; 256×4 KiB would
  be a 1 MiB map for a 64 KiB space. "Rewrite 2–4 entries per bank switch"
  confirms 4 KiB pages (ROMX=4 pages, RAM=2). Harmless ~2 KiB waste if
  over-allocated, but the implementer must pin the intent.
- 4 KiB granularity forces page 0xF (`F000-FFFF`) to be a mixed page (echo tail
  `F000-FDFF`, OAM `FE00-FE9F`, unusable, IO, HRAM, IE) that must sub-route
  through `io`-class code. That puts **HRAM (the post-boot stack region) and
  echo-resident stacks on the slow path** — costly in the dynarec fast path
  (see §10b). A 256-byte page table (256 entries — matching the stated entry
  count) separates OAM/IO/HRAM cleanly and lets echo pages alias WRAM bases
  directly. Alternatively keep 4 KiB pages and give `F800-FDFF`/`FF80-FFFE`
  explicit fast kinds.
- Echo `E000-FDFF` → `C000-DDFF` and CGB WRAM-bank coupling for the `F000-FDFF`
  tail are correctly handled by the rewrite rule ("2–4 entries"); FEA0-FEFF
  `0xFF` reads are standard (p2:222).

## 3. Cartridge/MBC/RTC: cached windows, fixed 128 KiB RAM, MBC1 5+2-bit, MBC3 RTC, MBC5 9-bit

**VERDICT: standard-but-not-optimal; MBC1 mode-1 edges and RTC semantics under-pinned.**

- Cached window pointers with no bank-data copies (p2:79) is the standard fast
  design (Gambatte/SameBoy both cache bank bases). Fixed `[131072]u8` with
  `ram_size` prefix is correct for MBC5 max; MBC3 ≤32 KiB, MBC1 ≤32 KiB. MBC5
  bank 0 valid in ROMX (p2:337) — correct, unlike MBC1.
- MBC1 (p2:86) wording "Mode 0/1 selects 32 KiB ROM banking or 8 KiB RAM
  banking" under-specifies three known hardware edges: (a) in mode 1 the 2-bit
  register also banks the **ROM0 window** (`0000-3FFF`) — `rom0_ptr` exists in
  the interface, good, but the mode-1 rule is not stated; (b) the 2-bit
  register contributes to **ROMX bits 5-6 in both modes** (banks 0x20/0x40/0x60
  remap); (c) the 5-bit register alone can never select 0x20/0x40/0x60. These
  are exactly what Mooneye `acceptance/mbc1/*` tests — and the gate manifest
  (p2:383-388) pins **no** MBC1 tests, so a wrong mode-1 model passes silently.
  Important gap.
- MBC3 RTC latch `0x00→0x01` (p2:335) is correct. "Host wall time when enabled"
  is a real-world-standard approach (real RTC runs off its own crystal; matches
  day/night games across power cycles) and beats tick-per-frame for realism —
  **but** it breaks the deterministic headless backend (spec §8.3) for
  RTC-bearing carts, and the `.rtc` format (spec:423-433) stores no timestamp,
  so the only coherent implementation is delta-accumulation (add
  host-elapsed deltas to counters; re-anchor on load). Neither the anchor
  semantics nor a headless freeze/inject hook is pinned. Also worth pinning:
  halt flag, day carry 511→0, writes go to live counters while reads return
  latched copies.
- UNVERIFIED which pinned ROM would catch RTC latch/write subtleties (none of
  the manifest entries are RTC tests).

## 4. DMG PPU: scanline renderer, 8-pixel batching, palette LUT, sprite rules, mode-3 penalty model

**VERDICT: standard (right accuracy/speed tradeoff); one formula inconsistency.**

- Scanline + penalty-model mode-3 length is the correct tradeoff given the
  spec's explicit non-goal of pixel FIFO (spec:190-191) and the gated test set
  (`dmg-acid2`, `lcdon_timing-GS`, `stat_irq_blocking`). FIFO-level accuracy is
  only needed for the tests that are deliberately out of scope.
- 8-pixel tile-row batching with `SCX` fine-scroll, `[4]u32` palette LUT
  recomputed only on BGP/OBP writes (p2:300) is standard scanline practice and
  correct (palette writes are rare; no per-pixel calls). Sprite selection must
  be **first 10 by OAM order** with draw priority by X-then-OAM (DMG); p2:300
  says "collected during OAM scan (≤10/line), DMG priority by X then OAM" —
  correct as written (sort for drawing, not for selection). Window internal
  line counter (p2:300) is the right mechanism (increment on rendered window
  lines only — the classic off-by-one; pin WY-latch and WX<7 behavior).
- **Formula inconsistency:** the OBJ penalty `6 + max(0, pixels_in_tile - 2)`
  gives 12 for an OBJ at X=0 (8 pixels in tile) while the same sentence says
  X=0 costs 11 (p2:298). Either clamp to 11 (`min(11, …)`) or the pixel count
  term differs; the exact Pan Docs revision formula must be pinned verbatim —
  UNVERIFIED which text revision is intended. Unlikely to fail the pinned gates
  (they do not measure mode-3 length to 1 cycle) but it is a real 1-cycle/obj
  drift source.
- Known scanline edges to keep explicit: sprites with X=0 (DMG hide/clip
  behavior), OBJ at WX boundary, window over sprite priority per scanline
  (the `dmg-acid2` golden exercises several of these).

---

## 5. Timers/interrupts/OAM DMA: delta divider, TIMA falling-edge, EI delay, HALT bug, byte-per-M-cycle DMA

**VERDICT: standard; two known glitch edges and one window missing.**

- Delta-bit divider (16-bit counter, TIMA on selected-bit falling edge, no
  per-cycle loops) is the correct method — it is the TCAGBD model and what
  Gambatte/binjgb-class cores implement analytically. DIV-is-high-byte and
  full-divider reset on DIV write (p2:261) is right (the `div_write` gate pins
  it). TAC enable + clock select as bit selectors is correct.
- **Missing edges (both real hardware, both cheap):** (a) the DIV-write reset
  can itself produce a falling edge and thus a spurious TIMA increment; (b) a
  TAC write that changes the selected bit can glitch an extra increment (the
  muxed-signal falling edge). Plan says neither. TCAGBD/Pan Docs document both;
  UNVERIFIED which pinned ROM covers the TAC glitch (the manifest's
  `tim00/tim01/tim10/tim11` pin TAC rates, not write glitches). Important if
  the Mooneye subset is to be the accuracy ceiling.
- TIMA overflow "reloads TMA and sets IF" instantly (p2:261): hardware keeps
  TIMA at 0 for 4 M-cycles before the reload and IF raise. The pinned gates may
  not see it; note as accuracy ceiling, implement the delayed window if
  `tima_reload`-class tests ever land.
- EI delay / `DI` cancels pending EI / RETI immediate (p2:263-264) and the HALT
  bug as "set `halt_bug`, do not halt" (p2:263) are the correct semantics; the
  HALT bug must manifest as the PC double-fetch of the next byte in the fetch
  path — worth one explicit test. Interrupt dispatch (20 cycles, vectoring,
  IF-bit clear order) is standard.
- OAM DMA: one byte per M-cycle for 160 M-cycles from `FF46<<8`, CPU restricted
  to HRAM for the duration with `0xFF` reads/ignored writes elsewhere
  (p2:223-224) is exactly hardware behavior and the right fidelity level —
  it is what the `oam_dma/basic` gate and the HRAM wait-loop games require.
  Instant-copy would be wrong; per-source-cycle bus contention modeling would
  be overkill. P4's rule "OAM DMA length scales with cpu_cycles in double
  speed" (p4:148) is correct.

## 6. APU: per-channel dividers, 512 Hz sequencer, 16.16 fixed-point resampler, LUT mixing, DC blocker, ring

**VERDICT: standard (Gambatte/SameBoy-class architecture); trap checklist not enumerated.**

- Per-channel period decremented by elapsed cycles, 512 Hz frame sequencer with
  length (256 Hz steps) / envelope (64 Hz) / sweep (128 Hz) on sequencer steps
  (p3:197), 16.16 fixed-point 44.1 kHz accumulator at ~95.1 T-cycles/sample
  (4194304/44100 = 95.108…), integer mixing through duty[4][8] / volume LUTs /
  wave-nibble LUT, one-pole integer DC blocker, power-of-two ring
  (p3:198-201) — this is the standard emulator shape and each piece is right.
  No float, no per-T-cycle mixing, no host-time clocking: all correct for the
  constraint set. P4's "APU derives from dot_cycles" (p4:148) matches Pan Docs
  double-speed rules (spec:452-453).
- Reference comparison: Gambatte does the same event/delta scheduling plus an
  analog-capacitor high-pass; SameBoy adds analog modeling. The one-pole DC
  blocker is an acceptable integer approximation; `dmg_sound` tests register
  semantics, not the analog waveform, so it is sufficient for the gate.
- Accuracy traps the plan does not enumerate (each is a known Blargg
  sub-test): sweep shadow-register + the "negate after enable disables
  channel" DMG quirk; noise LFSR width-7 feedback into **bit 6** (not 7);
  wave-RAM read-during-playback garbage on DMG; per-register NRxx read masks
  and NR52 power-off read values; length-counter extra-clock quirk on writes
  at sequencer boundaries; envelope period 0 = 8. The gate will catch most of
  these, but the implementer should carry the checklist. Important-nit level.

## 7. CGB rendering: palette LUT on write, per-tile-row attributes, three-flag priority, OAM-order sprites, CRAM lockout

**VERDICT: correct and optimal.**

- BGR555→RGB32 conversion on palette write into a 64-entry LUT (32 BG + 32
  OBJ) with 5-bit channel replication (p4:112-113) is the right data structure
  (SameBoy/Gambatte precompute likewise); per-pixel conversion would be naive.
  Mode-3 CRAM lockout (writes ignored, reads open-bus/`0xFF`-class) matches
  Pan Docs VRAM-access rules.
- Attribute fetch once per 8-pixel tile row, reusing priority/y-flip/x-flip/
  bank/palette (p4:115) is optimal for a scanline renderer and correct
  (attributes are per-tile). Bit layout (7 pri, 6 yf, 5 xf, 3 bank, 2-0 pal,
  4 ignored) is correct per Pan Docs.
- The three-flag BG/OBJ truth table as stated is **correct**: color 0 → OBJ;
  LCDC.0 clear → OBJ; else OBJ behind BG if either BG-attr bit 7 or OAM-attr
  bit 7 is set, OBJ wins only when both clear; OAM bit 7 semantics ("grants
  OBJ priority when clear") are right, and OBJ-vs-OBJ (OAM order on CGB,
  X-then-OAM on DMG) resolves before BG priority — matches hardware.
- `OPRI` FF6C bit 0 selecting CGB OAM-order vs DMG X-priority is the correct
  shape. UNVERIFIED whether retail CGB allows writing OPRI at runtime (docs
  disagree); modeling it R/W is harmless. HDMA semantics (p4:174-176) match
  Pan Docs: general-purpose halts CPU, HBlank 16 B/block, VBlank pause, FF55
  read remaining-1/`0xFF`, abort by clearing bit 7, HALT pauses, dest masks —
  with the documented mid-transfer VRAM-bank caveat; state-of-the-art cores
  emulate the caveat, acceptable to document instead.

## 8. Display scaling: hardware stretch Blt + software NN fallback

**VERDICT: optimal for era DirectDraw windowed.**

- Hardware stretch `Blt` from a 160x144 system-memory offscreen to the clipped
  primary is the standard windowed-DirectDraw presentation and the right
  primary path; `Blt` (not `BltFast`) is mandatory because `BltFast` ignores
  clipper regions and breaks with an obscured window — the plan/spec forbid
  `BltFast` (spec:328), which is correct. Lock only the source, honoring pitch
  (p3:87): matches the `std_gfx_pal.zig` precedent (Lock-free there, but the
  same DDSCL_NORMAL + clipper + Blt shape at `sf/src/std_gfx_pal.zig:1038-1044`).
- Software nearest-neighbour into a 640x576 staging offscreen + 1:1 `Blt` as
  the one-shot fallback (p3:87) is right: CPU NN scale 160x144→640x576 is
  ~230K pixel writes — trivial even on a PII — and avoids locking the primary
  (slow and fragile on Win9x drivers). Manual scale into a locked primary
  (rejected) and per-axis stretch (irrelevant at integer scales) are correctly
  not chosen.
- Caveats to document, not redesign: stretch `Blt` quality is driver-dependent
  (integer scales 160x{2,3,4} sample exactly, so no fractional artifacts);
  some Win9x drivers fall back to the HEL software blt for stretching (slower
  but fine at this resolution); 32 bpp source in an 8/16 bpp desktop is
  converted by the HAL. `DDERR_SURFACELOST` → `Restore` retry is the right
  recovery.

---

## 9. Audio output: DirectSound 4,096-frame ring, two-span free-region Lock, waveOut fallback

**VERDICT: standard practice; one spec/plan conflict and one arithmetic error.**

- The single-threaded pattern — looping secondary buffer, `GetCurrentPosition`
  refill, Lock **only the free region as ≤2 wrapped spans**, never block, write
  silence across underrun gaps, `DSBCAPS_GETCURRENTPOSITION2 |
  DSBCAPS_GLOBALFOCUS`, `DSSCL_PRIORITY` (p3:157-162) — is exactly the standard
  era DirectSound refill loop and is right for a single-threaded emulator.
  Silence-on-gap (not rewind, not clear-whole-buffer) is correct.
- **Conflict:** spec:372-373 pins a **2,048-stereo-frame** buffer (8,192 B,
  46.4 ms); P3 Task 3 Step 2 says **4,096 frames ≈ 85 ms** (p3:158) — 4,096
  frames at 44.1 kHz is 8,192 *stereo frames* = 16,384 B = **92.9 ms**, so the
  "85 ms" label is wrong under either reading. For a 59.7 Hz frame (735
  samples, 16.8 ms) a 3-frame (~50 ms) buffer is the sweet spot: 46 ms is
  tight under Win9x scheduling stalls (mitigated by `timeBeginPeriod(1)` +
  prefill-at-open), 93 ms is safe but adds 2+ frames of audio latency.
  Resolve spec-vs-plan (spec change = operator approval per spec:591-592) and
  fix the arithmetic. Prefill the buffer with one buffer of silence/samples at
  `Play` time to avoid an initial underrun.
- `waveOut` 2×2,048-frame (~46 ms) fallback with `WHDR_DONE` polling and
  silence-fill (p3:162) is the right shape and matches the proven in-tree
  z9play pattern (`examples/z98/z9play/player.zig:15-20` — there 2×0.5 s, much
  larger; 46 ms is workable since the emulator refills every frame).
- Power-of-two ring arithmetic via masks is right; latency-wise the design is
  bounded and non-blocking, which beats any callback-thread alternative under
  the single-thread constraint.

## 10. Dynarec (P5)

### (a) Register allocation BC→ebx DE→esi HL→edi SP→ebp; A/F in Cpu; PC at block end

**VERDICT: standard and correct; conservative on A/F.**
Callee-saved pairs surviving cdecl helper calls without spills is exactly why
this allocation is right (helpers are plain cdecl C, `p5:145`); HL→edi is the
highest-value assignment (HL is the implicit memory-pointer register), SP→ebp
is safe for generated code (no host frame). PC write-back at block end is
correct given block-end dispatch. Weak spot: **A/F in `Cpu` memory** — A is the
hottest SM83 register; every ALU op costs extra loads/stores. State of the art
keeps A (and F) in caller-saved regs with reload around helper calls; eager
flag computation into `Cpu.f` is the pragmatic choice (lazy host-EFLAGS across
helper calls is error-prone), so keep eager flags but cache A in ecx/edx.

### (b) Inline page-table fast path + helper for io/vram/oam/echo

**VERDICT: right idea; slow-path allocation is wrong for the hot stack path.**
Mirroring the interpreter's page table inline in generated code
(`p5:114`) with direct `base[addr & 0xFFF]` for rom0/romx/wram/cart_ram is the
standard JIT fast path and removes the no-LTO call chain. But with the 4 KiB
page shape of §2, HRAM (post-boot `SP=0xFFFE`) and echo-resident stacks fall
into the io/echo helper class — PUSH/POP/CALL/RET are the most frequent memory
ops in GB code, so a helper call per stack op is a serious tax. Fix: finer
pages (256 B) or explicit hram fast kind; **echo needs no helper at all** —
`E000-FDFF` is a pure WRAM alias and can be mapped to direct bases (with CGB
bank coupling). Reserve helpers for io/oam (VRAM could be direct-with-mode-3-
check). Also, a per-access `kind` multi-way switch could be a single
fast/slow flag test.

### (c) Cache: direct-mapped (rom_bank, pc), 4,096 entries, per-slot replacement, per-bank invalidation, arena reset

**VERDICT: standard (DOSBox-dynamic-core class); one keying edge.**
Keying by `(rom_bank, pc)` instead of PC alone is correct and necessary
(`p5:25`, `p5:183`); direct-mapped single-probe lookup is optimal for a 4,096
entry table; bump arena + full reset when exhausted is the standard simple
policy (dead bytes after slot collision until reset are fine). Per-bank
invalidation as a table scan is O(4096) per MBC write — acceptable, though
generation counters per bank are the O(1) standard. **Edge:** MBC1 mode-1 ROM0
banking (§3) means ROM0 blocks keyed as `bank=0` can alias across different
ROM0 mappings; the key or invalidation must cover the ROM0 mapping state (any
0x4000-0x5FFF write in mode 1 must invalidate bank-0 entries). ROM-only
translation (no RAM-executed code) correctly eliminates self-modifying-code
invalidation — a good call.

### (d) Block chaining with bank/PC guard through patch slots

**VERDICT: standard; the missing half is call/return linking.**
Guarded direct-jump linking through per-entry patch slots (`p5:187`) is the
correct design (identical to DOSBox dyn / PPSSPP block linking) and the
bank/PC revalidation guard is the right invalidation discipline. **Missing:**
CALL ends the block and RET is an indirect jump ending the block, so every
call/return round-trips the C dispatcher + cache lookup — the dominant control
flow in GB code pays the maximum cost. State-of-the-art links CALL→callee
block and caches return targets (per-RET-site 1-entry cache or shadow return
stack), e.g. DOSBox's call/return optimization and the Pokemon Stadium
"GB Tower" SM83→MIPS JIT. A guarded 1-entry RET cache is cheap and safe.

### (e) Block-end rules (HALT/STOP/EI/DI/RETI/IO/cart writes, 64-insn cap)

**VERDICT: correct and appropriately conservative — except the interrupt-drift hole.**
Ending at EI/DI/RETI/IO/cart writes bounds IME/IF/peripheral observation
drift; the 64-insn cap bounds interrupt-service drift (`p5:81`). Cart-write
block end + bank invalidation prevents stale translation after MBC switches
(`p5:21`). **Hole:** if IF becomes pending mid-block (timer overflow charged by
a cycle-syncing helper, `p5:22`), dispatch waits for block end — up to 64
instructions late versus the interpreter's per-instruction check. `interrupt_time`
is a pinned Blargg ROM (p2:386) and P5 parity requires all gates pass with
dynarec on; the plan itself notes the drift is gated but offers no mechanism.
Fix: after any cycle-charging helper, emit a pending-interrupt test that jumps
to the block epilogue (early exit, dispatcher services the interrupt). This is
the single most important dynarec correctness item.

### (f) BlockOp IR (op, a, b, imm) with unsupported-op block-end

**VERDICT: adequate, not state-of-the-art.**
A thin 3-operand IR lowering straight to emission is fine at this scale; the
256+CB coverage test forces completeness (unsupported-op → block end →
interpreter is a correct fallback). State-of-the-art would add flag-liveness
(elide redundant flag writes), load/store coalescing for `LD (HL),n` runs, and
PC-relative constant folding — worth doing only if measurements demand it (no
speedup gate exists). The declared enum under-covers the ISA (DAA/SCF/CCF/CPL,
rotates, RST, LDH, `LD (a16),SP`, `ADD SP,e8`, PUSH/POP have no home) — that
is a documentation/plan gap already flagged in p5-review; the algorithm shape
itself is fine.

**What a state-of-the-art SM83 dynarec would add within pure Z98 byte
emission:** (1) helper-triggered early exit on pending interrupts; (2) call
linking + 1-entry RET target cache; (3) HRAM/echo direct fast path; (4) A in a
host register across the block; (5) fast/slow page flag instead of multi-way
kind switch; (6) bank-generation counters for O(1) invalidation. Nothing here
requires asm or compiler features — all are emitter/IR/data-structure choices.

## 11. Cross-cutting: hot-path memory strategy vs no-LTO codegen

**VERDICT: consistent; one place to restructure, no place where the plan loses badly.**

- Static big arrays, no heap (8 MiB ROM + 128 KiB cart RAM + 16 KiB VRAM +
  32 KiB WRAM + 92 KiB framebuffer + 1.47 MiB offscreen + 1 MiB code cache +
  audio ring + ~64-96 KiB cache table ≈ 11 MiB) fits the 12 MiB budget
  tightly but coherently; large state never on the 1 MiB stack (spec:89-101).
- No-LTO cost analysis: per-access `read8` is one cross-TU call but its body
  is self-contained (page base deref, no nested `cartRead`) — the right shape
  (p2:124). The **one fight point**: `busTick` per instruction implies three
  cross-TU calls (`timerTick`/`ppuTick`/`apuTick`) on every instruction
  (~200-400K instr/s on DMG). Each component is bulk-tick-safe (scanline PPU,
  delta timer, accumulator APU), so consider one combined peripherals tick or
  per-scanline flush where coherence allows — call overhead, not correctness.
  The dynarec sidesteps the whole chain by inlining the page fast path (good).
- PPU 8-pixel batching keeps its inner loop inside `ppu.zig`; APU mixing is
  self-contained; palette LUTs convert at write time — all avoid cross-TU
  chains in inner loops. The interpreter is fast enough at 4.19 MHz on a PII
  regardless; the dynarec exists for headroom, and its design (§10) is where
  the no-LTO thinking is correctly applied.

---

## Overall verdict

**Sound engineering. No fundamentally wrong algorithm choices; most pieces are
standard Gambatte/SameBoy/DOSBox-class practice correctly adapted to pure Z98
on a PII.** The set is not naive anywhere; it is state-of-the-art in the
dynarec cache/ABI discipline and the bus design, and standard-but-conservative
in the interpreter/APU edge semantics. The real risks are: (1) dynarec
interrupt-service drift vs the `interrupt_time` gate and parity requirement;
(2) the page-table granularity ambiguity that puts the GB stack on the dynarec
slow path; (3) under-specified MBC1-mode-1/timer-glitch/RTC edges that the
pinned gates do not all cover. Fix the Critical/Important items below and the
algorithm set is optimal within the constraint set.

## Ranked algorithm changes worth making

**Critical**
1. Dynarec: emit helper-triggered early block exit when a cycle-charging helper
   leaves IF&IE pending — otherwise interrupt dispatch drifts up to 64 insns
   and `interrupt_time`/P5 parity can fail. Touches P5 Task 1 Step 2 (block-end
   rules), Task 2 Step 3 / Task 3 Step 2 (helper contract).
2. MMU page table: pin the table shape (16×4 KiB as literally written vs
   256×256 B matching the "256-entry" count) and make HRAM + echo direct-mapped
   (echo = WRAM alias) in the dynarec fast path; helpers only for io/oam.
   Touches P2 Task 2 Step 2 (Bus design) and P5 Task 2 Step 3 (fast path).

**Important**
3. MBC1 mode-1 edges (ROM0 banking via the 2-bit register, 2-bit→ROMX bits 5-6,
   0x20/0x40/0x60 remap) spelled out; add Mooneye `acceptance/mbc1/*` to the
   manifest; dynarec cache key/invalidation must cover ROM0 mapping state.
   Touches P2 Task 1 Step 3, Task 9 Step 3; P5 Task 4 Step 2.
4. Dynarec call/return linking: chain CALL→callee and add a guarded 1-entry RET
   target cache so call-heavy code stops paying a dispatcher round-trip per
   call/ret. Touches P5 Task 4 Step 4.
5. Timer glitches: model DIV-write and TAC-write falling-edge TIMA increments
   and the 4-M-cycle TIMA reload window. Touches P2 Task 6 Step 2.
6. RTC: pin delta-accumulation semantics (host-elapsed deltas into counters,
   re-anchor on load — the `.rtc` format has no timestamp field) and freeze or
   inject the clock in the headless backend to preserve determinism. Touches
   P2 Task 8 Step 2.
7. DirectSound buffer: resolve spec 2,048 frames (46 ms) vs P3's 4,096 frames
   ("85 ms" is wrong; it is 92.9 ms); recommend ~50 ms (3 frames) with prefill.
   Touches P3 Task 3 Step 2 (and spec §8.4 if the plan side wins).
8. APU quirk checklist carried into implementation: sweep negate/re-enable
   quirk, noise LFSR width-7 feedback to bit 6, DMG wave-RAM read-during-
   playback, NRxx read masks/NR52 power-off values, length extra-clock.
   Touches P3 Task 4 Step 2.

**Minor**
9. Pin the exact Pan Docs mode-3 OBJ penalty formula and clamp to 11 at X=0
   (the plan's `6 + max(0, px-2)` yields 12). Touches P2 Task 7 Step 2.
10. Dynarec: cache A (optionally F) in a host register across the block with
    reload around helper calls. Touches P5 Task 2 Step 2.
11. Pin the intra-instruction M-cycle offset at which DIV/TIMA/TAC writes land
    (Mooneye `tim*` sensitivity). Touches P2 Task 2/Task 6.
12. Page entries: fast/slow flag instead of multi-way kind switch per access;
    per-bank generation counters instead of invalidation scans. Touches P2
    Task 2; P5 Task 4 Step 2.

## Already good, leave alone

- 256-case switch + nested CB switch + module-scope OP_LEN/OP_CYCLES + packed
  F bits + u16/u32 intermediates (optimal under C89/Z98; threaded dispatch is
  unavailable).
- Page-descriptor bus shape: one index + kind dispatch + direct base deref,
  bank switches rewrite 2-4 entries, no bank-data copies; interpreter never
  nests into cart accessors.
- Cached cart window pointers; fixed 128 KiB RAM with `ram_size` prefix; MBC5
  bank-0-valid; MBC3 latch 0x00→0x01.
- Delta-divider timer core (edge-counting, no per-cycle loops); EI delay /
  DI-cancel / RETI; HALT bug as non-halt + double-fetch; interrupt dispatch
  shape.
- OAM DMA at one byte per M-cycle with all-but-HRAM bus block (correct fidelity
  level).
- APU: 512 Hz frame sequencer; 16.16 fixed-point 95.1 cycles/sample
  accumulator; duty/volume/nibble LUTs; integer one-pole DC blocker;
  power-of-two ring with masked indices; dot-based clocking under CGB double
  speed.
- CGB: palette-write BGR555→RGB32 64-entry LUT; per-tile-row attribute fetch;
  three-flag BG/OBJ priority truth table; OAM-order sprite priority + OPRI;
  CRAM mode-3 lockout; HDMA general/HBlank semantics with documented
  mid-transfer VRAM-bank caveat.
- Display: hardware stretch `Blt` from a system-memory 160x144 offscreen +
  software NN fallback into staging; `Blt` not `BltFast` (clipper correctness);
  integer-only scales; `Restore` retry on `DDERR_SURFACELOST`.
- Audio: two-span free-region Lock; silence-gap underrun fill; non-blocking
  write; `GETCURRENTPOSITION2|GLOBALFOCUS`; waveOut double-buffer fallback
  (z9play-proven pattern).
- Dynarec: `(rom_bank, pc)` keying (not PC-only); cdecl callee-saved pair
  caching; ROM-only translation (no SMC invalidation); interpreter as oracle
  with explicit unsupported-op fallback; bump arena + full reset; block-end at
  EI/DI/RETI/IO/cart writes + 64-insn cap; `FlushInstructionCache`;
  anti-vacuous counters.
- Cross-cutting: static arrays / no heap throughout; PPU inner loop and APU
  mixing kept single-TU; dynarec fast path removes the no-LTO call chain where
  it matters.
