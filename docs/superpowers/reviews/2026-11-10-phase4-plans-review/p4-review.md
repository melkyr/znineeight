# P4 Review — CGB (M7) Plan

**Reviewer:** independent plan reviewer
**Date:** 2026-11-10
**Plan under review:** `docs/superpowers/plans/2026-11-10-phase4-p4-cgb-plan.md`
**Spec (authority):** `docs/superpowers/specs/2026-11-10-phase4-project1-gameboy-design.md`
**Prior reviews:** `p1-review.md`, `p2-review.md`, `p3-review.md` (same dir; findings not duplicated)
**Mode:** REVIEW-ONLY. No plan/spec/source edits. Findings appended incrementally.

## Status Table

| # | Dimension | Status | Section |
|---|---|---|---|
| 1 | Objective coverage | DONE | §1 |
| 2 | Interface consistency | DONE | §2 |
| 3 | Win9x soundness | DONE | §3 |
| 4 | Achievability under pure Z98 | DONE | §4 |
| 5 | Test evidence quality | DONE | §5 |
| 6 | Memory model | DONE | §6 |
| 7 | Dependencies/ordering | DONE | §7 |
| 8 | Plan structure quality | DONE | §8 |
| 9 | Fact table | DONE | §9 |
| 10 | Caveat list | DONE | §10 |

---
## 1. Objective coverage (spec M7 → P4 task mapping)

M7 (examples/project1_phase4.txt:346): "CGB mode detection, palettes, double-speed, WRAM banking | Passes cgb-acid2, runs CGB homebrew". Spec §5.4 P4 gates: `cgb-acid2` golden, `cgb_sound`, CGB benchmark numbers.

| Spec / M7 requirement | P4 coverage | Verdict |
|---|---|---|
| §8.2 `EmuConfig.cgb` + `EmuError.CgbRequired` handling (amended P1 provides both: p1 plan:119-120) | Task 1 Step 3 | MAPPED |
| CGB mode detection (header flag 0x80/0xC0, M7 "CGB mode detection") | Tasks 0-1 (`CgbMode` enum, `cgbMode`) | MAPPED (mode matrix gap, §8) |
| 16 KiB VRAM banking (VBK FF4F) | Task 1 | MAPPED |
| 32 KiB WRAM banking (SVBK FF70, C000-CFFF fixed, D000-DFFF switchable, 0→1) | Task 1 | MAPPED (shapes PROVED vs Pan Docs, §9) |
| §8.6 CGB palettes (BG/OBJ CRAM, BCPS/BCPD/OCPS/OCPD, auto-increment) | Task 2 | MAPPED (mask/lockout gaps, §4/§9) |
| §8.6 "VRAM bank 1 attributes … and priority rules in P4" | Task 2 Step 3 | **BROKEN**: attribute bit layout misstated (bits 6-5 called "palette"; they are Y/X flip), flips never mentioned anywhere, priority **rules** (the three-flag BG/OBJ truth table, LCDC bit 0 CGB semantics, CGB OAM-order sprite priority) mapped nowhere (§9 facts 9-12) |
| Double speed (KEY1) + STOP | Task 3 | MAPPED but register semantics reversed (§9 facts 4-5) |
| §8.8 "double-speed changes the APU clock divisor" | Task 3 | MAPPED but internally contradictory (timer must be 2x, APU 1x; plan lumps both under one divisor, §9 fact 6) |
| HDMA/GDMA (FF51-FF55) | Task 4 | MAPPED (read/abort semantics inverted, §9 facts 14-15) |
| §5.4 `cgb-acid2` framebuffer golden | Task 5 Step 1 | MAPPED but gate cannot execute as written (no CGB CLI flag) and golden provenance unpinned (below) |
| §5.4 `cgb_sound` "full gate" | Task 5 Step 2 | **BROKEN**: wrong oracle channel + fixed-budget anti-pattern (below) |
| §5.4 "CGB benchmark numbers" (M7 "runs CGB homebrew") | Task 5 Step 3 | **BROKEN**: ROM unnamed ("user-supplied homebrew … from the manifest" — no such manifest row), measurement method undefined (below) |
| §5.2 "P4/P5 re-measure" RSS | Task 6 Step 2 | MAPPED (weak: which ROM, no bound, §6) |
| §5.3 closeout "requires present/passing" | Task 6 Step 1 | **CONTRADICTED**: "CGB gates PASS or SKIP truthfully" lets closeout go green with every hard gate SKIP (below) |
| "No new std modules and no seed rotation in P4" | Global Constraints | MAPPED (PROVED consistent: P4/P5 touch `examples/` only, p3-review fact 31) |
| "CGB is additive: DMG mode and all P2/P3 gates must keep passing" | Global Constraints; Task 6 Step 1 re-runs all tiers | MAPPED (good) |

**Hard-gate unambiguity:**

1. **No CGB invocation exists anywhere (Critical).** `EmuConfig.cgb` is wired in Task 1 Step 3 but **no plan (P1–P5) defines a CLI flag to set it** (P2 CLI: `--serial/--mooneye/--frames/--turbo/--rom/--save`, p2:373; P3 CLI: `--windowed/--scale/--audio/--no-audio/--turbo`, p3:223). Both CGB gate ROMs are **CGB-only (header flag 0xC0 — verified from ROM bytes, §9 facts 2-3)**, so under the plan's own wiring a default-DMG run returns `CgbRequired` and the gates can never execute. Task 5's runners ("Run `cgb-acid2.gbc` headless for 120 frames", "Run `cgb_sound.gbc` with `--serial --frames 1800`") never state an invocation that enables CGB mode.
2. **`cgb_sound` oracle is wrong (Critical).** The plan's gate scans `--serial` for `Passed`. The Blargg sound-test framework's print path (`cgb_sound/source/common/shell.s` `print_char_nocrc` = `write_text_out` + `console_print`) writes text to **cart RAM ($A004 string, $A000 result with `$DE $B0 $61` signature)** and to the **screen console**; `console.s` touches only nametable/SCY — **no SB/SC writes exist in the framework** and the pinned readme documents only screen + `$A000` output (contrast: `cpu_instrs`' readme explicitly documents the serial mirror used by P2's Blargg harness). `require Passed` on a serial log can never fire. The correct oracle is the `$A000` memory protocol (`$80` = running, `0` = passed, `n` = first failed test #n) — and the plan defines no memory-read hook.
3. **`cgb_sound` run semantics repeat the fixed-budget anti-pattern (Critical).** `--serial --frames 1800` (= 30.09 emulated s, asserted not measured) with no `--turbo`, no early exit on terminal verdict, and no "cap without verdict = FAIL" rule — the exact shape p2-review Critical #1 condemned and the amended P2 harness (p2 plan:388: `--serial --turbo --frames 200000` + early exit + timeout=FAIL) fixed; p3-review already cross-flagged this P4 line (p3-review §2 cross-plan flag). A correct APU can false-FAIL at the cap or the executor silently raises the number.
4. **`cgb-acid2` capture settings: partially pinned.** Frame count **120** ✓ (Task 5 Step 1, matches the amended spec's pinned-harness "capture frame 120", spec §5.3). Palette: not applicable — CGB palettes are loaded by the ROM itself via CRAM (plan doesn't say this, but nothing pins an external palette, so no palette trap like the dmg-acid2 one). **Mode: not pinned** (see #1). **Capture provenance: not pinned at all** — Task 5 Files "Create: `testdata/golden/cgb-acid2.fb`" never says from what (reference emulator? self-render?). A self-generated golden makes the gate circular; p2-review's dmg-acid2 fix (pin capture procedure or self-render + eyeball vs official reference) is not restated. Compare method (`cmp` of 92,160 B vs `sha256sum` of `.sha256`) also unstated.
5. **Benchmark gate is not a gate (Critical).** "Use a user-supplied homebrew CGB ROM from the manifest" — the spec §5.3 manifest tracks only Blargg/Mooneye/SameSuite/2×acid2; **no homebrew row exists** (same DISPROVED claim as p3-review fact 32, new instance for CGB). "User-supplied" also contradicts "from the manifest". No SKIP rule (unlike Steps 1-2), no measurement method (wall via what? CPU = user+sys? frames/sec = 600/wall?), and Wine-windowed numbers must not be presented as Win98/Pentium II numbers (spec §5.3/anti-goal 2). "No estimate is labeled measured" is good language, but with no named ROM the gate can vanish entirely.
6. **Closeout pressure is absent (Critical).** Task 6 Step 1 "CGB gates PASS or SKIP truthfully" + unnamed benchmark ROM ⇒ a full P4 closeout can go green with cgb-acid2, cgb_sound, and the benchmark all SKIP — direct violation of spec §5.3 "milestone closeout requires present/passing".

**Unmapped spec items:**
1. §8.6 **priority rules** — the BG-attr/OAM-attr/LCDC-0 truth table and CGB sprite priority mode (Pan Docs `Tile_Maps`/`OAM`) appear in no step; cgb-acid2 is precisely a priority/attribute test.
2. Attribute **X/Y flip** bits — never mentioned (misnamed as "palette" in Task 2 Step 3).
3. CRAM Mode-3 lockout (writes ignored / reads $FF while PPU reads CRAM — Pan Docs `Palettes`) — not modeled; "every CGB register has a documented read/write mask" (Global Constraints) is unmet for KEY1/VBK/SVBK/HDMA5 read masks.
4. OPRI (FF6C) / DMG-vs-CGB object priority modes — absent (may be acceptable if pinned as post-boot default, but unstated).
5. The CGB CLI surface (`--cgb` or equivalent) — assigned to no task.

**Verdict:** feature decomposition covers M7's nouns, but three of the four hard-gate deliverables (cgb_sound gate, benchmark, closeout integrity) are broken as specified, and the CGB priority/attribute core that cgb-acid2 exercises is misstated or unmapped.

---
## 2. Interface consistency (P2/P3 → P4 → P5, spec API)

**Consumption of P2/P3 outputs (names checked against the amended plans):**
- P2 `Bus` (`busInit/read8/write8/read16/write16/ioRead/ioWrite/busTick`, p2 plan:115-121) and `Cart` (`cartLoad/cartRead/cartWrite`, p2:72-74) — Task 1 "Consumes: P2 `Bus`/`Cart`" ✓ exact names.
- P3 APU (`apuReset/apuTick/apuRead/apuWrite/apuSamples`, p3 plan:183-187) — Task 3 modifies `apu.zig`; the double-speed divisor change is internal to `apuTick(a, cycles: u32)` (CPU cycles in) so **no P3 API change is needed** ✓. Contract to pin: samples per emulated frame must stay ≈735 i16-stereo at 44.1 kHz in double speed (spec §8.8: sample clock driven by the CPU counter + divisor change) — untested in the plan (Task 3 Step 1 "APU frame sequencer follows the CGB clock" is not an assertion of this invariant).
- P1/P3 `Platform` table + `emuFramebuffer` consumed unchanged by the benchmark ✓.
- Amended P1 already produces `EmuConfig{cgb, serial_log, turbo, dynarec}` and `EmuError` incl. `CgbRequired` (p1 plan:119-120) — Task 1 Step 3 consumes both consistently ✓ (p1-review drift findings resolved upstream).
- All IO-wiring tasks (1-4) correctly list `mmu.zig` in Files ✓ — P3's `mmu.zig`-omission lesson (p3-review Gap A) is not repeated.

**Produces for P5 (cross-plan):**
- P5 consumes `Cpu`/`Bus` internals (`blockBuild`, `helperRead8/Write8/IoRead/IoWrite`, `DynCtx`, p5 plan:66-134) and modifies `cpu.zig`/`emu.zig`/`tier_cgb.sh` (p5:192-193, 228). P4's additions are additive fields/registers in the same files — no signature conflict, sequential plans. ✓
- **Unpinned cycle contract (Important, cross-plan):** spec §8.10 dynarec blocks return "T-cycles"; Task 3 Step 3 introduces `cpu_cycles` + `dot_cycles` but never says which `emuRunFrame` (spec §8.2 "T-cycles executed") returns in double speed (a frame = 70,224 dots = 140,448 CPU T). P5's `DynCtx.cycles` and parity accounting must agree with whatever P4 pins; as written the meaning flips silently with KEY1. Pin: `emuRunFrame` returns CPU T-cycles and the dot conversion happens at one named place (frame loop), re-read after every speed switch (safe because switches only occur via STOP, a P5 block terminator per spec §8.10).
- P5 parity re-runs `cgb-acid2`/`cgb_sound` "with dynarec on" (p5:238) and edits `tier_cgb.sh` — P4's runner scripts therefore must accept a dynarec on/off switch (P5 adds `emuSetDynarec`, p5:204; CLI flag unspecified in both plans — flag for P5's review, note here that P4's runners are the shared subject).
- `emuAudioSamples` (spec §8.2) remains unproduced by any plan (p3-review §1/§2 gap; P4 touches `emu.zig` in Task 1 and still doesn't add it) — P5 "APU sample count" parity (p5:236) stays blocked. Cross-plan note only; not re-litigated.

**Spec API exactness / shape issues in P4's Produces blocks:**
1. `pub fn ppuCgbFramebuffer(p: *const Ppu) []const u32` (Task 2) — the spec has **one** 160×144 u32 framebuffer (spec §5.2) exposed as `emuFramebuffer` (spec §8.2). A second "CGB framebuffer" accessor suggests either a second 92,160 B buffer (unbudgeted, spec-violating duplication) or a redundant alias. Clarify: same buffer, or drop the function.
2. `cgbPaletteRead(p: *Ppu, addr: u16) u8` taking the IO address is fine as an internal hook (routed from `mmu.ioRead`), consistent with P2's "registers are owned by their modules" (p2 plan:222).
3. `CgbMode = enum(u8) { dmg, cgb_compatible, cgb_only }` + `cgbMode(c: *const Cart)` — internal type, no spec conflict. But the **mode matrix is under-specified**: 0xC0+`cfg.cgb=false` → `CgbRequired` ✓; 0x80+true → CGB ✓; 0x80+false → DMG ✓; 0xC0+true → CGB (implied); **0x00+true (DMG cart with CGB enabled) is never stated** (real hardware runs DMG-compat mode with KEY0/BGP palettes; the plan's "DMG mode" would lose the CGB-hardware-dmg-compat semantics). Also "0x80 runs in CGB mode with DMG compatibility" (Task 1 Step 1) is wrong terminology — a 0x80 cart on CGB runs **full CGB mode**; "DMG compatibility" is the 0x00-cart-on-CGB case.
4. `hdmaWrite(bus, addr, value)` / `hdmaTick(bus, dots)` — `dots` correctly places HDMA in the dot domain (hardware keeps HDMA at normal speed in double-speed mode, Pan Docs KEY1: HDMA "keeps operating as usual") ✓ good design choice.
5. `cgbSpeedSwitch(bus) bool` / `cgbIsDoubleSpeed(bus)` on `*Bus` — fine; who calls `cgbSpeedSwitch` (cpu.zig STOP handler) is unstated but low-risk.

**Verdict:** consumes P2/P3 exactly and stays spec-neutral on public APIs; the real interface holes are the `emuRunFrame` cycle-unit contract (P5-visible), the unexplained `ppuCgbFramebuffer`, and the unfinished mode matrix.

---
## 3. Win9x soundness (double-speed + banking on 32-bit / 32 MB)

- **New imports: none.** All P4 work is emulator-internal (cart/mmu/emu/ppu/cpu/timer/apu + tests). `scripts/win32_cross/check_win9x_imports.sh` is untouched (P3's `GetAsyncKeyState` delta remains the only whitelist change in the phase). No COM/Win32 surface is added. PROVED safe.
- **Memory growth (recomputed):** VRAM 8 KiB→16 KiB (+8,192), WRAM 8 KiB→32 KiB (+24,576), CRAM 64+64 B (+128), KEY1/HDMA/VBK/SVBK regs ≈ +10 B. **Total ≈ +32.9 KiB** over P3's static ≈ 8.72 MiB (p3-review §6) → ≈ **8.75 MiB static**; + DDraw offscreen 1.44 MiB ≈ **10.2 MiB** vs the provisional 12 MiB RSS target — comfortable. If `ppuCgbFramebuffer` turns out to be a second framebuffer (§2), add 92,160 B — still fits, but should not exist. 32 MB machine: unbothered (+33 KiB). PROVED.
- **Stack safety:** Global Constraints restate "1 MiB stack remains a stack limit; CGB buffers are static" ✓. Hot paths added: HDMA 16-byte block copies (≤16 B locals or static scratch), palette conversion (inline integer math), attribute fetch (per-pixel index math). Nothing resembling a large local; HDMA length is capped at 2,048 B total but moves in 16 B blocks. PROVED by construction; still no measurement step (inherited p1-review caveat 7 — not re-litigated).
- **32-bit cleanliness:** all quantities are u8/u16/u32 (addresses, banks, dots, CPU cycles); `u64` only for long-run cycle counters (carrier-clean, `Language_Spec_Z98.md:25`). HDMA source/dest masks fit u16. PROVED.
- **Double-speed on Win9x:** pure arithmetic; no timing dependency on the host. The one soft interaction: double-speed CGB homebrew doubles emulated work per frame (140,448 CPU T/frame); on a Pentium II the windowed benchmark may fall below 59.7 fps — that is a **measured outcome to report**, not a design defect, but any "full speed on Win98" claim must rest on the operator's hardware sign-off (spec §5.3/anti-goal 2). The plan's benchmark runs headless + windowed-under-Wine; Wine numbers are functional evidence only and must be labeled as such (§5).
- **Save/RTC paths:** P4 adds no file I/O; the inherited `MoveFileA` overwrite bug (p2-review caveat 3) is untouched by P4 and does not worsen.

**Verdict:** no new Win9x exposure; +33 KiB static is noise against the budget. The only Win9x-adjacent risk is benchmark-claim hygiene (Wine ≠ Win98).

---
## 4. Achievability under pure Z98

Constructs P4 needs, checked against `docs/reference/Language_Spec_Z98.md`:

- Banked arrays + index registers (`[16384]u8`, `[32768]u8`, 128 B CRAM) — plain static arrays; array-size window `:703` easily holds. PROVED.
- HDMA state machine (registers, 16-byte blocks, mode flag, length counter) — structs + loops + switches with mandatory `else` (`:215`). PROVED expressible. `hdmaTick(bus, dots: u32)` arithmetic is trivial in u32.
- Double-speed: two counters + a divisor; the split `cpu_cycles`/`dot_cycles` design (Task 3 Step 3) is the right shape and matches hardware (Pan Docs KEY1: CPU/timer 2x, PPU/HDMA/APU 1x; Rendering.md: "dots remain the same regardless of Double Speed mode"). PROVED expressible — but see the semantic contradiction in §9 fact 6.
- Palette math: BGR555 → RGB32 via `(c << 3) | (c >> 2)` per 5-bit channel — plain integer ops. PROVED (and the plan's `0x7FFF → 0x00FFFFFF` test value recomputes correctly, §5).
- Attribute priority rules: nested if/else over 3 flags + sprite tie-break — expressible; no language obstacle. The problem is not Z98, it is that the rules are not written down (§1).
- `STOP` opcode + KEY1 write path — plain CPU/IO handling; P5's block terminator rule (spec §8.10 "until … HALT/STOP") composes. PROVED.

**`-fsafe` checked-arithmetic discipline (mandate check): NOT bound by this plan (Important).** The amended P2 constraints (p2-review caveat 6 / §4) mandate widen→mask→cast for wrap-around code and dual `-ffast`+`-fsafe` test runs; P3's review flagged the same omission for P3. P4's Global Constraints restate stack/heap/golden/SKIP rules but **never mention checked arithmetic**, and no P4 step requires tests under `-fsafe` (P2 amended and P3 Task 4 Step 5 both do). P4 is full of exactly the shapes that trap under `-fsafe` (`Language_Spec_Z98.md:23,67` runtime checks; overflow/shift-loss traps per `:463`-family rules; shift-loss precedent `examples/z98/z9dbg/dwarf_lines.zig:120-122`):
- HDMA length decode `((HDMA5 & 0x7F) + 1) * 16` — `128 * 16 = 2048` overflows a `u8`; `(x << 4)` on `u8` is a lost-bit trap. Needs u16 widen.
- BGR555 extraction/replication `(v << 3)` — safe only if `v` is masked to 5 bits first and carried in a ≥8-bit type with proven no-loss; naive `color << 3` on the raw u16 loses bits.
- Timer double-speed ticks (u16 divider wrap — p2-review caveat 4 shape) and the dot/CPU counters (70,224/140,448 per frame) wrap points.
- SVBK/VBK/KEY1 read masks (`reg | 0xFE` etc.) are fine, but any `+1`/`<<` on masked fields follows the same rule.
Fix: one Global Constraints line binding the amended P2 `-fsafe` idioms + "tests pass under both `-ffast` and `-fsafe`" on Tasks 1-4.

**Verdict:** everything is expressible in pure Z98 and the HDMA-in-dots design is hardware-correct; the plan simply omits the checked-arithmetic contract its own arithmetic needs.

---
## 5. Test evidence quality (recomputed)

**Arithmetic (all recomputed):**
- VRAM `[16384]u8` = 2 × 8 KiB ✓; WRAM `[32768]u8` = 8 × 4 KiB ✓; C000-CFFF fixed bank 0 + D000-DFFF switchable ✓ (Pan Docs SVBK). CRAM 64 B BG + 64 B OBJ ✓.
- Palette color `0x7FFF` → channels `31<<3 | 31>>2 = 255` each → `0x00FFFFFF` ✓ (Task 2 Step 1 expectation correct).
- HDMA length decode: `HDMA5 & 0x7F` ∈ 0x00-0x7F → length = (x+1)×16 ∈ **0x10-0x800 bytes** ✓ (Pan Docs HDMA5; plan's "16-byte blocks" and "length-1" consistent). Source mask `0xFFF0` ✓; dest `0x1FF0` within 0x8000-0x9FFF ✓ (Pan Docs: only bits 12-4 respected).
- Golden size 160×144×4 = **92,160 B** ✓ (Task 5 Step 1).
- `--frames 1800` = 1,800 × 70,224 / 4,194,304 = **30.09 emulated s** — asserted, not derived from any reference run (§1 gate 3).
- Benchmark 600 frames = 42,134,400 T ≈ **10.05 emulated s** (600 × 70,224); in double speed = 84,268,800 CPU T. Target rate 4,194,304/70,224 = **59.73 Hz** (not 60) — the plan states no fps expectation at all, so no arithmetic error, but also no acceptance criterion to verify ("record numbers" only).
- Double-speed frame = 70,224 dots / 140,448 CPU T ✓ consistent with Pan Docs ("2 dots per Double Speed M-cycle").

**Is the benchmark methodology real?** No (Critical, §1 gate 5): exact ROM **absent** (unnamed "user-supplied homebrew … from the manifest"; no manifest row exists), measurement method absent (wall/CPU via `/usr/bin/time` like `tier_perf.sh`? where is frames/sec computed and asserted?), and measured-vs-estimated labeling is only a slogan ("No estimate is labeled measured") with nothing to label. The one honest element: it does record RSS/wall/CPU like P3's `tier_perf.sh` (p3:262) — reuse that script's method and pin a ROM + sha.

**Oracle strength per gate:**
- `cgb-acid2` hash gate: strong **once runnable and once the golden has provenance** (byte-exact 92,160 B compare / sha256, both created in Task 5). Currently: no CGB invocation (§1), no capture procedure, and a self-generated golden would make the gate circular.
- `cgb_sound` gate: **non-functional as designed** (wrong oracle channel + fixed budget, §1 gates 2-3). Additionally the verdict bytes are unpinned: the framework's A=0 exit prints an empty string and sets `$A000=0` (shell.s `exit` prints "" for code 0, "Failed"/"Failed #n" otherwise) — so "require `Passed`" may not even match the multi-ROM's screen text; the reliable contract is the `$A000` status byte + `$DE $B0 $61` signature (readme, verified in source).
- Benchmark: unverifiable (above).

**Fake-pass / silent-SKIP audit:**
- "Missing ROM or golden = `SKIP`" (Task 5 Step 1) / "Missing ROM = `SKIP`" (Step 2) match the spec §5.3 SKIP policy and repo convention (exit-77, p1-review fact 7) ✓.
- **But the whole gate set can silently SKIP**: unnamed benchmark ROM (no SKIP rule at all for Step 3), and Task 6 closeout explicitly accepts "PASS or SKIP truthfully" — so zero external assets ⇒ green P4 closeout, violating spec §5.3 "closeout requires present/passing". Same failure mode p3-review condemned for the homebrew gate; here it reaches the milestone itself.
- Manifest hash verification of the gate ROMs (p2-review gap) is again not implemented in any runner; Task 5 "Modify manifest.sha256" adds rows but nothing checks them.
- Task 5 Step 1's "compare `--fb-out` to the committed golden" — `cmp` vs `sha256sum` unstated (P2's `run_acid2.sh` uses `sha256sum` + size, p2:390 — should mirror).

**Verdict:** recomputed numbers are correct; the evidence system around them is broken — one gate cannot observe its ROM, one gate has no subject, and closeout has no teeth.

---
## 6. Memory model

Composition delta vs P3 (recomputed):
| Item | Bytes |
|---|---:|
| VRAM growth (8 KiB → 16 KiB) | +8,192 |
| WRAM growth (8 KiB → 32 KiB) | +24,576 |
| CRAM (64 BG + 64 OBJ) | +128 |
| KEY1/HDMA1-5/VBK/SVBK regs | +~10 |
| **P4 total** | **+32.9 KiB** |

- P3 static ≈ 8.72 MiB → P4 ≈ **8.75 MiB**; + DDraw offscreen 1,474,560 B ≈ **10.2 MiB** vs the provisional 12 MiB (spec §5.2) — ~1.8 MiB headroom before code/stack/driver surfaces. PROVED comfortable.
- Spec §5.2 "P4/P5 re-measure": Task 6 Step 2 runs `measure_rss.sh` + `tier_perf.sh` ✓ — but says nothing about **which ROM** is loaded (P1's harness runs ROM-less, p1-review §6; p2-review caveat 17 already demands a loaded-ROM measurement). "Record RAM/CPU with CGB enabled" needs a named CGB ROM (the benchmark ROM, once pinned) and a bound (or explicit "reported, not gated"). Spec §5.2's "report stack, cache, static, and driver surfaces separately" remains unmet (inherited; P4 at least should report the +32.9 KiB static delta).
- Conditional: `ppuCgbFramebuffer` as a second buffer would add 92,160 B unbudgeted (§2) — resolve before closeout accounting.
- Stack: unchanged, safe by construction (§3).

**Verdict:** fits the budget with room to spare; the measurement step is unanchored (no ROM, no bound).

---
## 7. Dependencies / ordering

- Internal order **0 → 1 → 2 → 3 → 4 → 5 → 6** is linear; no task consumes an artifact only a later task produces. Checks:
  - Task 2 (palettes/attrs) consumes VRAM bank 1 from Task 1 ✓ (order correct).
  - Task 3's clock split touches `ppu.zig`? — no: Task 3 lists cpu/timer/apu/mmu; PPU dot consumption is kept as-is ("Do not double PPU speed"), and Task 2's rendering rides P2's `ppuTick`. ✓
  - Task 4 (HDMA) needs VRAM banks (Task 1 ✓) and PPU mode-0 hooks (P2 `ppuTick`, listed in Files ✓).
  - Task 5 gates need Tasks 1-4 ✓.
- TDD ordering is real (each Step 1 is a failing test first) ✓.
- **Two soft forward references:**
  1. Task 5's golden "Create: `testdata/golden/cgb-acid2.fb`" depends on a capture procedure that no task defines — the gate cannot be built deterministically from the plan alone (§1).
  2. Task 0 Step 3's escalation ("if the sequence is unclear, STOP") is fine as policy but points at "the hardware docs used by the test ROMs" with no citation — Pan Docs KEY1 (incl. the 2050-M-cycle STOP stall) is the obvious authority and is not named.
- P4 correctly lands before P5; P5's parity suite (p5:238) consumes P4's runners unchanged — so P4's gate defects propagate to P5 parity (cross-plan flag, §2).
- Task 6 re-runs all five tiers last ✓; no seed rotation (PROVED, p3-review fact 31) so no ordering hazard vs the seed fixed-point.

**Verdict:** ordered correctly; the only missing predecessor is the unpinned golden capture source.

---
## 8. Plan structure quality

Template compliance (Files / Interfaces / TDD failing-step-first / Expected / scoped commit) matches the P1-P3 standard:

| Task | Files | Interfaces | TDD+Expected | Commit | Notes |
|---|---|---|---|---|---|
| 0 probes | temp only | yes | expectations present | n/a | Step 3 "hardware docs" uncited; "STOP" as escalation verb collides with the STOP opcode being built in Task 3 |
| 1 banking/mode | yes (+`mmu.zig` ✓) | exact sigs | concrete | yes | mode matrix incomplete (§2); "CGB mode with DMG compatibility" terminology wrong |
| 2 palettes/attrs | yes (+`mmu.zig` ✓) | exact sigs | concrete values | yes | **bit layout garbled** (§9 fact 9); "writes masked to 6 bits" ambiguous; `ppuCgbFramebuffer` unexplained |
| 3 double speed | yes | exact sigs | partially concrete | yes | Step 3 divisor rule contradicts Step 1 test + hardware (§9 fact 6); "one STOP-length stall" uncited |
| 4 HDMA | yes (+`mmu.zig`, `ppu.zig` ✓) | exact sigs | concrete | yes | completion/abort read semantics inverted (§9 facts 14-15); GDMA CPU-stall simplification undocumented |
| 5 gates | yes | — | concrete but wrong oracles | yes | no CGB invocation; cgb_sound oracle/budget broken; benchmark subject unnamed; golden provenance absent |
| 6 closeout | yes | — | concrete | yes | "PASS or SKIP truthfully" guts spec §5.3 closeout pressure |

**Vague / unverifiable steps (flagged):**
1. Task 0 Step 3: which "hardware docs"? (Pin Pan Docs `CGB_Registers`/`Palettes`/`Tile_Maps`/`OAM` or the GB CPU manual.)
2. Task 2 Step 2: "reads return the latched byte; writes masked to 6 bits" — is the 6-bit mask on the **index** registers (correct: BGPI/OBPI address = bits 0-5) or on **palette data** (wrong: data is full 8-bit)? Reads auto-increment? (Hardware: writes increment, **reads do not** — untested.)
3. Task 2 Step 3: attributes sentence self-contradicts ("bits 6-5 palette" vs "bit 0-2 CGB palette") and omits flips and the priority rules; sprite sentence ("same palette/bank fields with OBP") doesn't match OAM byte 3's actual layout.
4. Task 3 Step 2: "the required delay (documented as one `STOP`-length stall)" — the documented value is 2050 M-cycles (8200 T) with DIV freeze and mode-dependent PPU locking (Pan Docs KEY1); "one STOP-length" is circular. Tolerable as an approximation only if explicitly labeled.
5. Task 3 Step 3: "timer/APU consume CPU cycles with the speed divisor" vs Step 1 "timer increments at the doubled CPU clock" — mutually exclusive readings; pin: timer = undivided CPU cycles (2x), APU = divided (1x).
6. Task 5 Step 1: golden from where? compare how? run with what mode flag?
7. Task 5 Step 2: `$A000` vs serial oracle; per-ROM verdict string; budget derivation.
8. Task 5 Step 3: ROM identity/sha; measurement commands; missing-ROM behavior.
9. Task 6 Step 2: RSS with which ROM; assert or report-only?

**Positive structure notes:** Global Constraints are crisp (additive-CGB, masks policy, no-seed-rotation); Review Focus maps to the right subsystems; commit blocks scoped; TDD shape real; `hdmaTick(dots)` and the split-clock design show real hardware-modeling care.

**Verdict:** skeleton is as strong as P1-P3; the weak text is concentrated exactly where the gates live (Tasks 2-5).

---
## 9. Fact table

| # | Claim (plan location) | Verdict | Evidence |
|---|---|---|---|
| 1 | `cgb-acid2` release v1.1, file `cgb-acid2.gbc`, 32,768 B (Task 5, spec §5.3) | PROVED | GitHub releases API asset `size: 32768` at tag v1.1 (verified) |
| 2 | cgb-acid2 can run in DMG/default mode (implied by Task 5's unstated invocation) | **DISPROVED** | downloaded ROM bytes at 0x143 = **0xC0** (CGB-only); plan's own Task 1 wiring returns `CgbRequired` without CGB mode |
| 3 | `cgb_sound.gbc` exists (Task 0 Step 2, Task 5 Step 2) | PROVED with naming drift | upstream path is `cgb_sound/cgb_sound.gb` at pinned commit `c240dd7d…`, **65,536 B**, cart type 0x02 (MBC1+RAM), header 0x143 = **0xC0** (verified from ROM bytes); no `.gbc` name upstream |
| 4 | "KEY1 bit 0 is current speed; writing bit 7 requests a switch" (Task 3 Step 2) | **DISPROVED** | Pan Docs KEY1 + pseudocode (`KEY1 = $01` arms; `KEY1_BIT7` = current speed); hardware.inc `KEY1F_DBLSPEED=$80`, `KEY1F_PREPARE=$01`. Bit roles are exactly reversed |
| 5 | "Clear bit 7 after the switch" (Task 3 Step 2) | **DISPROVED** | Pan Docs: armed bit 0 clears automatically after STOP; bit 7 flips to the new speed |
| 6 | "timer/APU consume CPU cycles with the speed divisor" (Task 3 Step 3) | **DISPROVED** (timer) / PROVED (APU) | Pan Docs KEY1: double-speed = CPU, **Timer/Divider**, Serial, OAM DMA 2x; PPU, **HDMA**, **all sound timings** 1x. Timer must consume undivided CPU cycles; only the APU divides. Contradicts the plan's own Step 1 test ("timer increments at the doubled CPU clock") |
| 7 | "APU frame sequencer follows the CGB clock" (Task 3 Step 1) | INCOMPLETE | hardware: APU stays 1x absolute (Pan Docs KEY1); spec §8.8 "double-speed changes the APU clock divisor" is the 1x statement. "CGB clock" is ambiguous — pin 512 Hz sequencer + 44.1 kHz output unchanged in double speed |
| 8 | Speed-switch delay = "one `STOP`-length stall" (Task 3 Step 2) | INCOMPLETE | Pan Docs: CPU stops **2050 M-cycles (8200 T)** after STOP; DIV does not tick; PPU memory-lock freeze is mode-dependent. No "STOP-length" unit is defined anywhere |
| 9 | BG attributes: "bit 7 priority, **bits 6-5 palette**, bit 3 bank, bit 0-2 CGB palette" (Task 2 Step 3) | **DISPROVED** (bits 6-5) / self-contradictory | Pan Docs `Tile_Maps` BG Map Attributes: bit 7 priority, bit 6 **Y flip**, bit 5 **X flip**, bit 4 ignored, bit 3 bank, bits 2-0 palette. Plan lists palette twice (6-5 and 0-2) and never mentions flips |
| 10 | Sprite attributes "use the same palette/bank fields with OBP" (Task 2 Step 3) | **DISPROVED** as stated | Pan Docs `OAM` byte 3: bit 7 priority (BG-over-OBJ when set), 6 Y-flip, 5 X-flip, 4 DMG palette, 3 bank, 2-0 CGB palette — different bit map than BG attrs; OBP naming applies to DMG mode only |
| 11 | X/Y flip rendering implemented anywhere in P4 | **UNMAPPED** | no step mentions flips; cgb-acid2 exercises them |
| 12 | BG/OBJ priority rules (§8.6 "priority rules in P4") | **UNMAPPED** | Pan Docs `Tile_Maps` truth table (LCDC bit 0 × OAM attr 7 × BG attr 7) + `OAM` CGB drawing priority = OAM order (+ OPRI FF6C) — none appear in any task; cgb-acid2's core subject |
| 13 | HDMA masks: source `0xFFF0`, dest `0x1FF0` into VRAM, HDMA5 = length/16-1 + mode bit 7 (Task 4 Step 2) | PROVED | Pan Docs HDMA1-5: source low 4 bits ignored; dest only bits 12-4 respected; length = ($00-$7F)→$10-$800 bytes |
| 14 | "completion clears bit 7 of HDMA5" (Task 4 Step 1) | **DISPROVED** | Pan Docs: reading FF55 returns remaining length; **a value of $FF indicates completion**; bit 7 read 1 = not active, 0 = active. Completion **sets** bit 7 (idle reads 0xFF) |
| 15 | "writing bit 7 during HBlank DMA stops it" (Task 4 Step 1) | **DISPROVED** as phrased | Pan Docs: terminate by **writing zero to bit 7**; writing with bit 7 set is the HBlank-DMA mode/start encoding |
| 16 | "General DMA runs immediately" (Task 4 Step 2) | DISPROVED-as-accuracy / acceptable simplification | Pan Docs: GDMA halts CPU until done (~8 M-cycles per 16-byte block; 8 µs/block in both speeds); ignoring the stall is a common emulator shortcut but must be documented (cgb-acid2 timing edge) |
| 17 | Palette RAM 64 B BG + 64 B OBJ; index bit 7 auto-increment; `0x7FFF → 0x00FFFFFF` (Task 2) | PROVED | Pan Docs `Palettes` (BGPI/BGPD/OBPI/OBPD = plan's BCPS/BCPD/OCPS/OCPD aliases); conversion recomputed ((31<<3)\|(31>>2)=255). Caveats: reads do **not** auto-increment (untested); CRAM Mode-3 lockout unmodeled; "writes masked to 6 bits" ambiguous (§8) |
| 18 | CRAM reads/writes work at any time (implied) | **DISPROVED** | Pan Docs: during Mode 3 CRAM writes ignored, reads return $FF |
| 19 | "Every CGB register has a documented read/write mask" (Global Constraints) | INCOMPLETE | VBK read = bank \| 0xFE (Pan Docs) unmentioned; SVBK/KEY1/HDMA5 read masks unmentioned; HDMA5 read semantics wrong (fact 14) |
| 20 | SVBK 32 KiB, 8×4 KiB banks, C000-CFFF fixed, D000-DFFF switchable, 0→1 (Task 1 Step 2) | PROVED | Pan Docs FF70 verbatim |
| 21 | `cgb_sound` gate oracle: `--serial … require Passed` (Task 5 Step 2) | **DISPROVED** | framework source: `print_char_nocrc` = `write_text_out` (cart RAM $A004 + `$DE $B0 $61` signature at $A001-3, status at $A000) + `console_print` (nametable/SCY); **no SB/SC writes** in `shell.s`/`console.s`/`printing.s`; pinned readme documents screen + $A000 only (contrast cpu_instrs readme's documented serial mirror). Also framework A=0 exit prints "" not "Passed" |
| 22 | `--frames 1800` suffices for `cgb_sound` (Task 5 Step 2) | **INCOMPLETE / pattern DISPROVED** | 30.09 emulated s asserted, not measured; readme: "many tests need to run for a while"; repeats the fixed-budget anti-pattern (p2-review C#1, p3-review C#1); amended harness (turbo/until-verdict/timeout=FAIL) not used |
| 23 | cgb-acid2 capture at frame 120 (Task 5 Step 1) | PROVED as pin / INCOMPLETE as procedure | matches amended spec §5.3 "capture frame 120 in the plan's harness"; capture source/emulator/mode unpinned; ROM's own v1.1 "software breakpoint for automated testing" (release notes) is an alternative completion signal never mentioned |
| 24 | Benchmark ROM "a user-supplied homebrew CGB ROM from the manifest" (Task 5 Step 3) | **DISPROVED** | spec §5.3 manifest pins 5 suites only (Blargg/Mooneye/SameSuite/dmg-acid2/cgb-acid2); no homebrew row exists anywhere (same claim shape DISPROVED as p3-review fact 32) |
| 25 | A CGB mode switch exists at CLI level (implied by Task 5 runners) | **DISPROVED** | grep of P1-P5 CLI surfaces (p2:373 `--serial/--mooneye/--frames/--turbo/--rom/--save`; p3:223 `--windowed/--scale/--audio/--no-audio/--turbo`) — no `--cgb` anywhere; `EmuConfig.cgb` is settable only in code |
| 26 | VRAM `[16384]u8`, WRAM `[32768]u8` (Task 1 Step 2) | PROVED | recomputed (2×8 KiB, 8×4 KiB); +32.9 KiB total P4 growth (§6) |
| 27 | Golden `92,160` bytes (Task 5 Step 1) | PROVED | 160×144×4 = 92,160 |
| 28 | "No new std modules and no seed rotation in P4" (Global Constraints) | PROVED | P4/P5 Files touch `examples/z98/z9gb/**` only; p3-review fact 31 |
| 29 | `tier_cgb.sh` is the spec's tier (Task 5) | PROVED | spec §8.11 line 484 |
| 30 | `measure_rss.sh` / `tier_perf.sh` exist by P4 (Task 6 Step 2) | PROVED | P1 creates `measure_rss.sh` (p1:178); P3 creates `tier_perf.sh` (p3:249) |
| 31 | `-fsafe` widen→mask→cast idioms bind P4 (implicit via amended P2) | **DISPROVED** (plan is silent) | P4 Global Constraints contain no checked-arithmetic rule and no dual-mode test requirement; needed for HDMA length math, palette shifts, timer wrap (§4) |
| 32 | "0x80 runs in CGB mode with DMG compatibility" (Task 1 Step 1) | **DISPROVED** as terminology | 0x80 carts run full CGB mode on CGB hardware; "DMG compatibility" mode is the 0x00-cart-on-CGB case (Pan Docs KEY0/CGB_Registers) |
| 33 | `cgb-acid2` v1.1 "software breakpoint for automated testing" usable as completion signal | PROVED (external fact, unmapped in plan) | release notes v1.1 (verified); plan uses fixed 120 frames instead — deterministic, acceptable, but the breakpoint is the ROM's designed hook |

---
## 10. Caveat list (Win9x-implementation and general)

1. **cgb_sound gate cannot work as written** — wrong output channel (serial) and unfixed-budget harness; expect permanent FAIL-on-present-ROM or silent harness fiddling until the `$A000` oracle + amended turbo/verdict runner exist.
2. **No CGB CLI flag** — both hard-gate ROMs are CGB-only (0xC0, verified); without `--cgb` (or header-driven auto-mode) the gates die at `CgbRequired`.
3. **Closeout has no teeth** — "PASS or SKIP truthfully" + unnamed benchmark ROM ⇒ P4 can close green with zero hard gates executed; spec §5.3 forbids this.
4. **Register semantics reversed/inverted** — KEY1 bits (Task 3), HDMA5 completion/abort (Task 4): implementers copying the plan text will build hardware that fails every real ROM that touches these registers.
5. **CGB priority/attribute core misstated or absent** — flips unmapped, BG attr bits 6-5 mislabeled, priority truth table / CGB sprite priority / LCDC bit 0 semantics missing — cgb-acid2 will fail and the failure will look like a golden mismatch rather than a spec gap.
6. **Clock-divisor contradiction** (timer 2x vs "speed divisor") — double-speed timer tests and `cgb_sound` timing both land on this; pin the per-subsystem divisor table before Task 3 starts.
7. **`-fsafe` idioms not bound** — HDMA length math `(x+1)*16`, palette `<<3`, divider wraps will trap or be mis-written; bind the amended P2 rule and run tests under both modes.
8. **cgb-acid2 golden provenance** — frame 120 pinned, source-of-truth not; a self-generated golden is circular. Decide: reference-emulator capture (pin emulator+settings) or self-render + eyeball against the official reference image (p2 recipe).
9. **Benchmark is vapor** — pin exact ROM + sha + measurement commands; label Wine numbers as Wine (anti-goal 2: no unqualified Win98 claims); real-hardware perf sign-off stays the operator's (spec §5.3).
10. **Win9x reality inherited, not worsened** — P4 adds no imports/threads/allocations; +33 KiB static is fine on 32 MB. Windowed CGB under Wine proves function only (DDraw7-needs-DX6+, 55 ms `Sleep` pacing — p3-review caveats 2-3 — unchanged by P4).
11. **STOP stall approximation** — "one STOP-length" vs documented 2050 M-cycles + DIV freeze; if cgb-acid2 (mode-3 register writes per its v1.1 notes) or SameSuite CGB tests get pulled in, this approximation is a suspect.
12. **Cross-plan (P5):** parity re-runs P4's gates (p5:238) — broken gates propagate; `emuRunFrame` cycle-unit under double speed must be pinned for `DynCtx.cycles`; `emuAudioSamples` still unproduced (p3-review gap) though P4 edits `emu.zig`.

---
## VERDICT

**NEEDS FIXES**

The plan's decomposition, file discipline (every IO task lists `mmu.zig`), storage arithmetic, HDMA-in-dots design, and additive-CGB constraint are sound. But the hard-gate layer is broken end to end: `cgb_sound` watches an output channel the ROM never writes and repeats the fixed-budget anti-pattern already declared Critical twice in this review series; both CGB gates run CGB-only ROMs with no CGB invocation defined in any plan; the benchmark subject does not exist; closeout explicitly tolerates SKIP, voiding spec §5.3's closeout pressure; and the CGB register/attribute semantics the gates depend on are reversed or missing (KEY1 bits, HDMA5 completion/abort, BG attr flips/priority rules).

### Caveats / risks by severity

**Critical:**
1. `cgb_sound` gate is non-functional as designed: `--serial … require Passed` but the Blargg sound framework outputs only screen + `$A000` memory protocol (no SB/SC writes — verified in `shell.s`/`console.s`/`printing.s` and the pinned readme); plus `--frames 1800` with no turbo/early-exit/"no verdict = FAIL" repeats p2-review Critical #1 / p3-review Critical #1 (already cross-flagged at p3-review §2). Fix: `$A000` oracle hook (or verify serial in one reference run) + the amended P2 harness verbatim + pinned verdict bytes.
2. No CGB CLI/invocation exists (P1-P5): both gate ROMs are flag-0xC0 CGB-only (verified), so Task 5's runners die at `CgbRequired` under the plan's own mode wiring. Add `--cgb` (or header-driven auto mode) and pin the exact runner command lines.
3. P4 closeout can go green with every hard gate SKIP ("CGB gates PASS or SKIP truthfully", unnamed benchmark ROM) — violates spec §5.3 "closeout requires present/passing".

**Important:**
4. KEY1 bit semantics reversed (bit 0 = armed, bit 7 = current speed — Pan Docs/hardware.inc) and "clear bit 7 after the switch" wrong (armed bit 0 clears; speed bit flips).
5. HDMA5 semantics inverted: completion reads **0xFF with bit 7 set** ("clears bit 7" is wrong); abort = **write 0 to bit 7** ("writing bit 7 stops it" is wrong).
6. BG attribute bits 6-5 are Y/X flip, not palette (plan self-contradicts); flips, the BG/OBJ priority truth table (LCDC bit 0 × OAM bit 7 × BG attr bit 7), CGB OAM-order sprite priority and LCDC bit 0 CGB semantics are unmapped — cgb-acid2's core subject (Pan Docs `Tile_Maps`/`OAM`).
7. Double-speed divisor contradiction: timer must run 2x (undivided CPU cycles), APU 1x; Task 3 Step 3's "timer/APU … with the speed divisor" contradicts both hardware and the plan's own Step 1 test. Pin a per-subsystem table (CPU/Timer/Serial/OAM-DMA 2x; PPU/HDMA/APU 1x).
8. `-fsafe` checked-arithmetic idioms (widen→mask→cast) and dual `-ffast`/`-fsafe` test runs are not bound, though HDMA length math, palette shifts, and divider wraps need them (amended P2 constraint should bind).
9. cgb-acid2 golden provenance unpinned (frame 120 ✓, mode/invocation/source ✗); a self-generated golden makes the gate circular.
10. Benchmark: pin exact ROM + sha + measurement commands; label Wine numbers as Wine (spec §5.3/anti-goal 2).

**Minor:**
11. `cgb_sound.gbc` naming vs upstream `blargg/cgb_sound/cgb_sound.gb` (65,536 B, MBC1+RAM, flag 0xC0); manifest path convention unstated; runner hash verification (inherited gap) still absent.
12. STOP stall "one STOP-length" uncited (documented: 2050 M-cycles + DIV freeze + mode-dependent PPU locking); CRAM Mode-3 lockout unmodeled; register read masks incomplete vs the plan's own Global Constraint.
13. `ppuCgbFramebuffer` — second framebuffer or alias? (spec §5.2 has one 92,160 B buffer). Mode matrix omits `cfg.cgb=true` + DMG ROM; "0x80 … with DMG compatibility" terminology wrong.
14. GDMA "runs immediately" (no CPU stall) should be documented as an accuracy simplification; RSS re-measurement needs a named ROM and a bound; `emuRunFrame` cycle unit under double speed unpinned (P5-visible).

### Top operator decisions

1. **`cgb_sound` oracle + harness:** add an `$A000`-out CLI hook and adopt the amended turbo/until-verdict runner (recommended), or first do one reference run to prove/refute any serial output?
2. **CGB invocation:** add `--cgb` to the CLI in P4 Task 1/5 (recommended), or auto-detect mode from the header flag and make `EmuConfig.cgb` an override only?
3. **Closeout policy:** require cgb-acid2 + cgb_sound + benchmark present/passing at P4 closeout (spec §5.3), or accept truthful-SKIP with operator sign-off as a spec amendment?
4. **Benchmark ROM + golden provenance:** which exact homebrew CGB ROM + sha (manifest row) and which reference capture for `cgb-acid2.fb` (or self-render + eyeball vs the official reference image, p2 recipe)?
5. **Attribute/priority semantics:** expand Task 2 Step 3 to the full Pan Docs bit maps + priority truth table before execution, or add a dedicated Task 2b? (cgb-acid2 cannot pass without them.)

