# P2 Review — Headless DMG Core (M1–M4) Plan

**Reviewer:** independent plan reviewer
**Date:** 2026-11-10
**Plan under review:** `docs/superpowers/plans/2026-11-10-phase4-p2-dmg-core-plan.md`
**Spec (authority):** `docs/superpowers/specs/2026-11-10-phase4-project1-gameboy-design.md`
**Prior review:** `docs/superpowers/reviews/2026-11-10-phase4-plans-review/p1-review.md`
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
## 1. Objective coverage (spec → P2 task mapping)

| Spec requirement | P2 coverage | Verdict |
|---|---|---|
| SM83 CPU full (spec §8.5) | Tasks 2–4 | MAPPED, gaps below |
| MMU 64 KiB + IO routing (§8.5) | Task 5 | MAPPED |
| OAM DMA explicit (§8.5) | Task 5 | MAPPED |
| HALT bug (§8.5) | Task 6 | MAPPED |
| **EI delay (§8.5)** | **no task mentions it** | **UNMAPPED** |
| Interrupt dispatch (§8.5) | Task 6 Step 3 | MAPPED (20 T-cycles correct) |
| **Post-boot state A=0x01 F=0xB0 … PC=0x0100, LY=0x91 (§8.5)** | **never stated in any step; `cpuInit` values unspecified** | **UNMAPPED** |
| MBC1 (§8.7) | Task 1 | MAPPED |
| MBC3+RTC (§8.7) | Task 8 | MAPPED |
| MBC5 (§8.7) | Task 8 | MAPPED |
| Scanline PPU, modes, STAT/LYC (§8.6) | Task 7 | MAPPED |
| Timer DIV/TIMA/TMA/TAC (§8.8) | Task 6 | MAPPED (model gaps below) |
| Serial harness (§8.9) | Tasks 6, 9 | MAPPED |
| `.sav`/`.rtc` + atomic persistence (§8.7) | Task 8 | MAPPED |
| **§8.2 facade: `emuLoadRom`, `emuReset`, `emuSetButtons`, `emuTakeSerial`, `emuSetSavePath` exact sigs** | only analogues with drifted names (Task 8 `saveBattery(e, rom_path)`, Task 6 `serialTake(s, out)`) | **UNMAPPED as spec'd** |
| **`emuRunFrame` rewiring from P1 constant 70224 to real stepping** | no step owns the frame loop | **UNMAPPED** |
| Hard gates (§5.4): cpu_instrs, Mooneye timer/PPU subset, dmg-acid2 golden, synthetic DMG boot tests | Task 9 (+ Task 1 minimal.gb) | MAPPED but ambiguous (see §5) |
| STOP opcode (excluded from cpu_instrs but dispatched) | absent from Task 3 list | UNMAPPED (low risk) |

**Hard-gate unambiguity (paths / signatures / SKIP):**
- ROM paths: listed exactly (Task 9 Step 3) but only as *local* manifest paths; upstream layout differs and Mooneye `.gb` files are build artifacts (see §9). Ambiguous acquisition.
- Pass signatures: Blargg "checks for `Passed`" — no exact expected string per ROM, no rule for "neither string within budget" (must be FAIL, not SKIP). Mooneye "requires `B=3`" — weaker than upstream contract (§5).
- SKIP policy: `SKIP: <path>` + exit 77 — matches repo convention, unambiguous. PROVED consistent.

**Verdict:** coverage is broad but five spec items are genuinely unmapped (post-boot state, EI delay, spec-signature facade functions, `emuRunFrame` rewire, STOP), and three gated behaviors (STAT IRQ blocking, TIMA reload delay, LCD-on timing) are demanded by the gate ROMs but specified in no step.

---
## 2. Interface consistency (P1 → P2 → P3, spec signatures)

**Exact-match (PROVED):**
- Framebuffer 160x144 `u32` 0x00RRGGBB — P2 Task 7 shade mapping writes into `Emu.fb`; spec §8.2 `emuFramebuffer` unchanged; P3 `present_fn(*void, []const u32)` consumes it. Consistent.
- `CartError`/`EmuError` members used by P2 (`BadHeader`, `UnsupportedMbc`, `RomTooLarge`, `Io`, `SaveCorrupt`) all exist in spec §8.2 sets.
- `Bus` shape (`read8/write8/read16/write16/ioRead/ioWrite/busTick`) is an internal P2 type; P3 Task 4 consumes "Bus I/O, CPU cycle counter" — compatible (`Cpu.cycles: u64`).

**DRIFT vs spec §8.2 (Important — spec §11 requires operator approval for public-API changes):**
1. **The spec's Emu facade is never produced.** `emuLoadRom`, `emuReset`, `emuSetButtons`, `emuTakeSerial`, `emuSetSavePath`, `emuSaveBattery`, `emuLoadBattery` appear in no P2 task's Produces block. Instead the plan ships module-level `cartLoad`, `serialTake(s, out)`, `saveBattery(e, rom_path)`, `loadBattery(e, rom_path)`, `deriveSavePath(...)`. Task 9 adds `--rom`/`--save` CLI but never declares the facade functions behind them. P3 consumes `emuSetButtons` (poll_fn mapping, p3 Task 5) and the spec's save API — P2 as written hands P3 a different surface.
2. **Save API shape mismatch:** spec `emuSaveBattery(e: *Emu) EmuError!void` + `emuSetSavePath(e, path)` (path state on Emu) vs plan `saveBattery(e: *Emu, rom_path: []const u8)` (path derived per call). Not reconcilable without a wrapper the plan never names.

**P1 consumption (cross-plan; detail in p1-review.md, not re-derived here):** P2 Task 0 "Run the P1 loader stub" and "Consumes: `Emu` fixed ROM buffer" still reference artifacts P1 does not produce (p1-review findings 5–6, caveats 6). P2 inherits the blocker; its plan text was not adjusted. Also P2 Task 1's `git add testdata/synth/minimal.gb` hits P1's recursive `*.gb` ignore (p1-review caveat 4) — P2 adds no `!synth/` negation.

**P3/P5 consumption (flag only):** APU I/O range `FF10-FF3F` behavior in P2 `ioRead/ioWrite` is unspecified ("APU registers are owned by their modules" — but the APU is P3); P3 needs a defined stub/hook. P5 `DynCtx` (`p5` Task 2) consumes `*Cpu` fields — compatible with P2's `Cpu` struct as specified.

**Verdict:** internal P2↔P3 data formats are consistent; the spec §8.2 facade is systematically absent and one save-API shape drifts.

---

## 3. Win9x soundness

- **Allocation/stack/width:** all large state static by constraint; PPU shade buffer is 160 B; `u64` cycles counter is carrier-clean (`Language_Spec_Z98.md:14,25`). No hot-path heap. PROVED sound by construction.
- **File I/O whitelist:** `std.file` Win32 path uses `CreateFileA/ReadFile/WriteFile/SetFilePointer/DeleteFileA/MoveFileA/FlushFileBuffers` (`sf/src/std_file.zig:10,157,387,393-401`) — every symbol is in `KERNEL32_9X` (`scripts/win32_cross/check_win9x_imports.sh:26`). PROVED. No import outside the whitelist is needed for ROM/save/RTC I/O.
- **`temp file + rename` save pattern — DISPROVED on Win9x (Important):** `std.file.rename` maps to `MoveFileA` (`std_file.zig:399`), and Win32 `MoveFileA` **fails when the destination exists**. Updating an existing `.sav`/`.rtc` therefore always errors on Win9x. `MoveFileExA` (MOVEFILE_REPLACE_EXISTING) is **not** in the KERNEL32 whitelist. The plan's "on any failure keep the previous file" policy collides with this: the rename failure is deterministic, not exceptional. Needs delete-then-rename (loses atomicity) or a whitelist amendment.
- **RTC wall clock:** `std_time.wallClockUnix()` (`std_time.zig:116`) → `GetSystemTimeAsFileTime` (`std_time_pal.zig:53`) — whitelisted (check_win9x_imports.sh:26). PROVED. But RTC driven by host wall time makes RTC-dependent tests nondeterministic (see §5/§10) and diverges from the "deterministic headless backend" spec goal (§2) for any test touching RTC.

**Verdict:** no whitelist violations; the rename-overwrite semantics are a real Win9x bug in the save design.

---

## 4. Achievability under pure Z98

Checked against `docs/reference/Language_Spec_Z98.md`:

- 256-case switch + nested 0xCB switch with mandatory `else`: legal (`:215`); case labels from module-scope consts required — plan Task 4 Step 3 mandates exactly that (`:207` forbids local-const case labels). PROVED.
- `else => unreachable` (`Task 2 Step 4`): legal but traps on reach in **both** `-fsafe`/`-ffast` (`:216`, `:353`); the language doc explicitly recommends `else => {}` or a real fallback. Acceptable only because the 256-case dispatch is exhaustive; any missed opcode becomes a hard trap, not a diagnostic.
- DAA, flags, ALU with `u16` intermediates, MBC banking, RTC latch state machine: all expressible with plain integer ops + structs. No tagged unions, no generics, no methods. PROVED.
- **Checked arithmetic/shifts — plan under-specifies the required idioms (Important):**
  - `-fsafe` traps on integer overflow of `+ - *` (`:463`) and on shifts that lose bits (`examples/z98/z9dbg/dwarf_lines.zig:120-122`: "Z98's `<<` is a checked shift; a lost bit would otherwise trap"). Every SM83 wrap-around (INC 0xFF→0x00, ADD overflow, `RLCA/SLA/SRL/SWAP`, all CB shifts) must be written widen→mask→cast. The plan says "use `u16` intermediates" for add/sub only; shifts/rotates get no such rule.
  - **Task 5 Step 3's literal `value << 8` on a `u8` is invalid** as written (shift-count ≥ width / total bit loss → trap or reject). Must widen to `u16` first.
  - The timer's 16-bit divider increments every T-cycle and wraps at 0xFFFF constantly — a bare `u16` `+ 1` traps under `-fsafe`. Needs a `u32` counter with masked high byte. Not stated.
  - Tests are required to pass under both `-ffast` and `-fsafe` (Task 2 Step 5) — good — but only if the implementer knows these idioms. Plan should pin them.
- `u64` cycles field, error unions, slices, fn-pointer `Platform` (P1): all established. PROVED.
- Fixtures: `gen_synth_roms.c` built by `gcc` at test time — precedent `examples/z98/z9git/tests/gen_repos.sh:190`; `cpu_test.zig` built with `zig1` per existing `tests/*.zig` patterns. PROVED buildable.

**Verdict:** everything is expressible; three concrete shift/overflow expressions in the plan text are not valid Z98 under `-fsafe` as written.

---
## 5. Test evidence quality (recomputed)

**Arithmetic (all recomputed):**
- Golden size 160×144×4 = **92,160 B** — plan Task 9 Step 5 correct. PROVED.
- 8 MiB = 8,388,608; "8 MiB accepted, 8 MiB+1 rejects `RomTooLarge`" (Task 0 Step 2) matches spec §8.7. PROVED.
- `minimal.gb` program encodings at 0x0150: `31 FE FF` (LD SP,0xFFFE), `AF` (XOR A), `EA 00 C0` (LD (0xC000),A), `C3 50 01` (JP 0x0150); header bytes 0x0147=0x00, 0x0148=0x00 → 32 KiB, 0x0149=0x00 → RAM 0. Expected `cart ok mbc=0 rom=32768 ram=0` consistent. PROVED.
- 600 frames = 600 × 70,224 T = **42,134,400 T ≈ 10.05 emulated seconds**. PROVED arithmetic — see budget finding below.
- Mode timing 80 + 172 + 204 = 456 T/line, 154 lines, 70,224 T/frame ✓.
- `.rtc` 32 B layout matches spec §8.7 exactly (8+1+1+1+1+1+1+1+17 = 32). PROVED.
- TAC select 00/01/10/11 → 4096/262144/65536/16384 Hz ✓ (Task 6 Step 1 order matches hardware).

**Blargg oracle — real but budget-broken (Critical):**
- Upstream readme (pinned commit) confirms serial mirror: "Everything printed on screen is also sent to the game link port by writing the character to SB, then writing $81 to SC" — the serial harness is a genuine pass oracle. PROVED.
- But the same readme states: "**Some sub-tests take half minute to complete.**" One slow sub-test ≈ 1,800 frames; `cpu_instrs` runs 11 sub-tests and takes on the order of 2–3 emulated minutes (~7,000–11,000 frames). The plan's uniform `--frames 600` (10 emulated s) for all four Blargg ROMs **cannot reach the verdict** on a correct emulator. Either the gate false-FAILs forever or an executor silently raises the budget. Per-ROM budgets must be derived from measured runtimes (or run-until-verdict with a large cap), and "verdict absent at budget exhaustion = FAIL (not SKIP)" must be stated.
- Exact verdict strings are **not pinned**. Upstream readme admits "there is no well-defined way for an emulator test rig to programmatically find the result"; the failure output is "the number of failed tests" (may not contain the literal `Failed`). Spec §8.9's "scan for `Passed`; `Failed` is a fail" is unverified against the actual bytes. Runner should pin per-ROM expected strings from one reference run and treat absence-of-`Passed` as FAIL. (INCOMPLETE.)
- `instr_timing.gb`/`mem_timing.gb`/`interrupt_time.gb` are quick (~seconds) — 600 frames is plausibly enough there; budget is wrong at least for `cpu_instrs` (and `mem_timing` at 64 KiB needs MBC1 — which Task 1 provides, ordering OK).

**Mooneye oracle — weaker than upstream (Important):**
- Upstream protocol (README, pinned commit): pass = **Fibonacci 3/5/8/13/21/34 in B/C/D/E/H/L** + `LD B,B`; fail = `0x42` in all six + `LD B,B`. The plan (and spec §8.9) check **B=3 only**. This discriminates the two standard outcomes (fail always sets B=0x42) but false-passes any abnormal stop on `LD B,B` with B=3. Recommend checking the full six-register signature — cheap and matches upstream.
- "stop on `0x40`" is correct (`LD B,B` = 0x40); the quit sequence emits `LD B,B` twice — stopping at the first is correct (registers already set).
- Upstream: "the serial interrupt doesn't need to be implemented since the mechanism uses busy looping to wait for the transfer to complete" — the plan's SC bit-7 clearing satisfies this. PROVED.
- Frame budget 600 for the 8 pinned Mooneye ROMs is plausible (acceptance tests finish in seconds) but is asserted, not measured.

**dmg-acid2 golden — provenance/palette trap (Important):**
- Asset facts PROVED: release `v1.0`, `dmg-acid2.gb`, **32,768 B** (GitHub releases API).
- Spec §5.3 says goldens are committed "as 160x144 RGB32 **hashes**"; the plan commits a full 92,160-byte `dmg-acid2.fb` + `.sha256` (Task 9 Step 5). Superset of spec — harmless but is a spec-wording deviation.
- "captured from a known-good emulator" is unverifiable and palette-fragile: Task 7 hardcodes shade→RGB `0→0x009BBC0F, 1→0x008BAC0F, 2→0x00306230, 3→0x000F380F` (classic GB-green). If the golden was captured with any other palette (grayscale, different greens), the hash **never** matches. The golden must be produced with the exact plan palette (or comparison palette-normalized), and the capture procedure (emulator + config + frame count) must be pinned. Also **no frame count is specified** for the acid2 capture (run_acid2.sh uses `--fb-out` but not how many frames to run first).

**Fake/silent-skip audit:**
- Missing ROM → `SKIP: <path>`, exit 77: matches repo convention (`examples/z98/z9torr/tests/tier4_wine.sh:24,42-52`). PROVED.
- "a present ROM must pass" (Task 9 Step 1) and "Do not claim synthetic ROMs as external suite passes" (Task 10 Step 3) block the classic fake-pass routes. Good.
- Residual risk: a runner that greps `Passed` over a serial log that never reached the verdict — must be FAIL. Not stated explicitly (Minor).
- Hash-check of user ROMs against `manifest.sha256` is stated in Global Constraints but no step implements hash verification in the runners (Task 9 Step 4 only greps output). Gap: wrong-version ROMs can be run undetected (Minor-Important).

**Verdict:** oracle directions are sound and repo-consistent, but the Blargg frame budget is provably too small and the acid2 golden provenance/palette is unpinned.

---

## 6. Memory model

- Static footprint with max ROM: ROM 8 MiB + fb 92,160 + P1 headless snapshot 92,160 + serial log 4,096 + save RAM (header-driven, up to 128 KiB) + WRAM 8 KiB + VRAM 8 KiB + OAM/HRAM ≈ **8.4 MiB** static + code/stack → under the 12 MiB provisional RSS target with headroom for P3's 1.4 MB surface. Structurally sound. PROVED by composition with spec §5.2 table (ROM 8 MiB, fb 92,160 B, stack 1 MiB separate — plan's Global Constraints restate all three correctly).
- Task 0 probes the 8 MiB boundary ✓ and Task 10 runs `measure_rss.sh` ✓ — but P1's `measure_rss.sh` runs **without a ROM** (p1-review §6). P2 closeout must measure RSS **with a max-size ROM loaded** or the number stays meaningless. Plan does not say so. (Important-lite; the spec §5.2 "report stack, cache, static separately" split is still unmet — inherited from P1.)
- `Cart = struct { /* fixed arrays */ }` + `cartLoad(c, bytes: []const u8)` — plan should state the ROM buffer is the shared `Emu` 8 MiB array (pointer/slice), not a second copy inside `Cart` (would double ROM to 16 MiB and bust the budget). Ambiguous as written (Minor-Important).
- Stack: no large locals mandated; PPU uses a 160-entry shade buffer (fine). PROVED sound.

**Verdict:** fits the spec table; two accounting ambiguities (ROM ownership, RSS-with-ROM).

---

## 7. Dependencies / ordering

- **Tasks 2–4 depend on a type produced in Task 5 (Important):** `cpuStep(cpu: *Cpu, bus: *Bus)` and `cpuSetBus` reference `Bus`, which Task 5 ("MMU, IO routing") defines. Task 2's "Consumes: `Cart`/MMU read/write callbacks" contradicts its own signature. Either `Bus` is defined in Task 1/2 as a facade and filled in later, or CPU tests need a stub bus — the plan specifies neither. As written Tasks 2–4 cannot compile against the stated interface.
- Task 0 "Run the P1 loader stub" depends on a P1 artifact that does not exist (p1-review findings 5–6). Inherited blocker; P2 text was not adjusted.
- Task 1 (cart/MBC1) before Task 8 (MBC3/5) before Task 9 (gates) — fine; gates need MBC1 only (`cpu_instrs.gb`/`mem_timing.gb` are 64 KiB MBC1 ROMs — PROVED sizes via API).
- Milestones M1–M4 (project1_phase4.txt:340-343) are never referenced; all milestone demonstrables (cpu_instrs for M1, dmg-acid2 for M3, Mooneye timer for M4) collapse into Task 9. Task-level TDD gives per-step verification, but milestone-level independent verification happens only at the end. (Minor.)
- Tasks are otherwise linear; no forward references besides `Bus`.

**Verdict:** one real ordering inversion (`Bus`), one inherited P1 blocker.

---

## 8. Plan structure quality

Template compliance (Files / Interfaces / TDD+Expected / commit):

| Task | Files | Interfaces | TDD+Expected | Commit | Notes |
|---|---|---|---|---|---|
| 0 probes | temp | yes | expectations present | n/a | depends on nonexistent P1 loader |
| 1 cart/MBC1 | yes | exact sigs | red/green + exact stdout | yes | good; `.gitignore` collision (inherited) |
| 2 ALU/DAA | yes | exact `Cpu` struct | red step ok | yes | **no golden expected values** for ALU/DAA cases |
| 3 loads/stack | yes | ok | lists opcodes | yes | overlap with Task 2's `0x00-0x3F` claim (INC/DEC/LD split is ambiguous across 2/3) |
| 4 CB | yes | ok | boundaries listed | yes | fine |
| 5 MMU/DMA | yes | exact sigs | concrete | yes | `FF46` owner conflicts with Task 7 register list; `value << 8` invalid Z98 (§4) |
| 6 timer/interrupt/serial | yes | exact sigs | concrete counts | yes | DIV-write semantics missing though `div_write.gb` is gated |
| 7 PPU | yes | exact sigs | concrete | yes | palette fixed — must match golden (§5) |
| 8 MBC3/5+save | yes | exact sigs | concrete | yes | "RTC latch/read after host seconds" is nondeterministic |
| 9 gates | yes | CLI flags | runners specified | yes | budgets/palette/strings gaps (§5) |
| 10 closeout | yes | — | concrete | yes | good truthfulness language |

Vague/unverifiable steps: Task 2 golden values absent (executor-written tests could encode wrong expectations — mitigated only by later Blargg gate); Task 8's wall-clock-dependent RTC test; run_acid2 frame count; `manifest.sha256` hash-verification step missing from runners; RAM-size code table absent (so `cartRamSize` expectation `ram=0` only tests the zero case).

**Verdict:** structure is strong (consistent with P1 quality); the weak spots are missing golden values and the RTC nondeterminism.

---

## 9. Fact table

| # | Claim (plan location) | Verdict | Evidence |
|---|---|---|---|
| 1 | Blargg `retrio/gb-test-roms` commit `c240dd7d…` exists | PROVED | GitHub tree at that commit (1 commit repo) |
| 2 | `blargg/cpu_instrs/cpu_instrs.gb` exists (manifest path) | PROVED | upstream `cpu_instrs/cpu_instrs.gb`, **65,536 B** (contents API) |
| 3 | `blargg/instr_timing/instr_timing.gb` | PROVED | `instr_timing/instr_timing.gb`, 32,768 B |
| 4 | `blargg/mem_timing/mem_timing.gb` | PROVED | `mem_timing/mem_timing.gb`, 65,536 B (MBC1 needed) |
| 5 | `blargg/interrupt_time/interrupt_time.gb` | PROVED | `interrupt_time/interrupt_time.gb`, 32,768 B |
| 6 | Blargg output mirrored to serial (SB/SC=$81) | PROVED | cpu_instrs readme at pinned commit |
| 7 | `--frames 600` suffices for Blargg gates | **DISPROVED** | readme: "Some sub-tests take half minute to complete"; 600 frames ≈ 10 emulated s |
| 8 | Blargg verdict strings are `Passed`/`Failed` | INCOMPLETE | readme: no programmatic result contract; failure text is "the number of failed tests" — exact bytes must be pinned from a run |
| 9 | Mooneye commit `31510e12…` exists | PROVED | GitHub tree (49 commits) |
| 10 | Mooneye ROM paths `acceptance/timer/{div_write,tim00,tim01,tim10,tim11}`, `acceptance/ppu/{lcdon_timing-GS,stat_irq_blocking}`, `acceptance/oam_dma/basic` | PROVED (source names) | listings at pinned commit (`.s` sources; `.gb` are build artifacts) |
| 11 | Mooneye `.gb` obtainable at pinned commit | **INCOMPLETE** | repo ships sources + Makefile (RGBDS); prebuilt binaries at gekkio.fi track **main**, not the pinned commit — manifest hashes are the only real pin; build recipe undocumented |
| 12 | Mooneye pass = `B=3` | PROVED-as-spec / weaker-than-upstream | upstream README: Fibonacci 3/5/8/13/21/34 in B–L; fail = 0x42×6 |
| 13 | Mooneye needs no serial interrupt (busy loop) | PROVED | upstream README |
| 14 | `dmg-acid2` v1.0 / `dmg-acid2.gb` / 32,768 B | PROVED | GitHub releases API asset size |
| 15 | Golden committed as raw 92,160 B `.fb` + sha256 | PROVED plan text / spec says "hashes" | spec §5.3 wording deviation (superset) |
| 16 | Z98: mandatory switch `else`, no local-const case labels, no tagged-union payload stores, checked shifts/overflow, `u64` exists | PROVED | `Language_Spec_Z98.md:215,207,55,463,14`; shift-loss trap `examples/z98/z9dbg/dwarf_lines.zig:120-122` |
| 17 | `value << 8` (Task 5) / unchecked `u16` divider wrap expressible in Z98 `-fsafe` | **DISPROVED** | shift-count/lost-bit + overflow checks trap (fact 16) |
| 18 | Win9x save "temp + rename" works | **DISPROVED** | `std_file.zig:399` uses `MoveFileA`; Win32 `MoveFileA` fails if dest exists; `MoveFileExA` not whitelisted (`check_win9x_imports.sh:26`) |
| 19 | RTC wall time available on Win9x no-CRT | PROVED | `std_time_pal.zig:53` `GetSystemTimeAsFileTime`, whitelisted |
| 20 | Save/ROM I/O imports within whitelist | PROVED | `std_file.zig` CreateFileA/ReadFile/WriteFile/SetFilePointer/DeleteFileA all in `KERNEL32_9X` |
| 21 | `testdata/synth/minimal.gb` committable in Task 1 | **DISPROVED** | `testdata/.gitignore` `*.gb` recursive (p1-review fact 18; P2 adds no negation) |
| 22 | "P1 loader stub" / "Emu fixed ROM buffer" (Task 0/1) | **DISPROVED** | P1 ships neither (p1-review findings 5–6) |
| 23 | Matrix counts truthful (Task 10) | PROVED | README.md:57,208,519,598 anchors; P2 adds no example dir |
| 24 | Exit-77 SKIP convention | PROVED | `examples/z98/z9torr/tests/tier4_wine.sh:24`; matches spec §5.3 |
| 25 | `gen_synth_roms.c` buildable in test tier | PROVED | precedent `examples/z98/z9git/tests/gen_repos.sh:190` (gcc), `z9zstddecomp/tests/gen_fixtures.c` |
| 26 | M1–M4 milestone labels (plan header implies M1–M4) | PROVED as external ref | `examples/project1_phase4.txt:340-343`; plan itself never uses them |
| 27 | SameSuite pinned but unused in P2 manifest | PROVED consistent | spec §5.4 gates for P2 don't require it |
| 28 | TAC frequencies, 456/154/70224, mode 3=172 min, 20-cycle interrupt dispatch | PROVED | hardware-standard values; arithmetic consistent |
| 29 | `.rtc` 32-byte `Z98RTC1\0` layout | PROVED | matches spec §8.7 byte-for-byte |
| 30 | Post-boot CPU state (A=0x01…PC=0x0100, LY=0x91) implemented | **INCOMPLETE/UNMAPPED** | spec §8.5 requires it; no plan step sets `cpuInit` values or initial LY |

---
## 10. Caveat list (Win9x-focused and general)

1. **Blargg gate budget is unachievable as written** — `--frames 600` (≈10 emulated s) vs `cpu_instrs` runtime of minutes (readme: "Some sub-tests take half minute"). Hard gate cannot go green on a correct emulator; expect ad-hoc budget fiddling or a silently relaxed gate.
2. **dmg-acid2 golden provenance is palette-fragile** — Task 7 hardcodes GB-green shades; a golden "captured from a known-good emulator" with any other palette never matches. Capture procedure, palette, and frame count must be pinned.
3. **Win9x battery save update is broken by design** — `MoveFileA` fails when destination exists; the second `--save` on a machine with an existing `.sav` errors. Delete-then-rename loses atomicity; `MoveFileExA` needs a whitelist amendment (spec §5.1 forbids new static imports but the whitelist script is operator-editable).
4. **Z98 `-fsafe` traps in hot paths** — SM83 code wraps constantly; every `u8` shift/rotate, `u16` divider tick, and `value << 8` must use widen→mask→cast. Tests are required under `-fsafe`, so this bites at Task 2, not at the gate.
5. **RTC from host wall time** breaks headless determinism for anything touching `.rtc`; test "RTC latch/read after host seconds" is inherently nondeterministic. Consider an injectable clock offset.
6. **Serial interrupt "after 8 cycles"** — ambiguous units (spec says 8 T-cycles); hardware is 4096 T for 8 bits at normal speed. Harmless for Blargg/Mooneye (neither depends on the latency) but do not let it leak into P3 timing claims.
7. **Post-boot state drift** — real ROMs (and some Mooneye tests) assume the documented DMG post-boot register file; `cpuInit` values unspecified means emulator boot state is whatever the implementer guesses.
8. **Wrong-version test ROMs can be run undetected** — manifest hashes are declared but no runner verifies them; a stale `cpu_instrs.gb` could produce misleading gate evidence.
9. **CPU-instruction coverage split between Tasks 2 and 3 is ambiguous** (`0x00-0x3F` claimed by both for INC/DEC/LD vs jumps/LD16) — risk of double-implementation or gaps at the boundary.
10. **P2 cannot close out green without P1 fixes** (loader stub, `.gitignore` negation) — schedule risk if P1 is not amended first.
11. **`mem_timing.gb` is 64 KiB (MBC1)** — fine for gate ordering (Task 1 first) but note it exercises banking in the gate set; a no-MBC-only cart implementation would pass Task 1's test and fail the gate.
12. **`Cart` ROM storage ambiguity** — if `Cart` copies ROM instead of referencing the shared 8 MiB `Emu` buffer, static memory doubles and the 12 MiB RSS target is bust; state ownership explicitly.

---

---

## VERDICT

**NEEDS FIXES**

The architecture, task decomposition, TDD shape, and most fact claims are solid. But the hard gates as specified cannot pass on a correct emulator (Blargg frame budget), one gate is palette-fragile (dmg-acid2 golden), the spec's Emu facade is systematically absent, and there is a task-ordering inversion. Several fixes also need operator sign-off (spec API, Win9x import whitelist).

### Caveats / risks by severity

**Critical:**
1. `run_blargg.sh` `--frames 600` (≈10 emulated s) cannot reach the verdict for `cpu_instrs` (upstream readme: "Some sub-tests take half minute to complete"; total runtime ~2–3 emulated minutes). The P2 hard gate is unachievable as written. Fix: per-ROM budgets measured against a reference run (or run-until-verdict with a large cap) and an explicit "verdict absent = FAIL, never SKIP" rule.

**Important:**
2. dmg-acid2 golden "captured from a known-good emulator" is not pinned to the plan's fixed shade→RGB palette (Task 7: `0x009BBC0F` etc.) nor to a frame count; hash can never match a golden captured with a different palette. Pin the capture procedure (emulator + palette + frame) or generate the golden with the plan's own renderer after visual comparison to the official reference.
3. Spec §8.2 Emu facade never produced: `emuLoadRom`, `emuReset`, `emuSetButtons`, `emuTakeSerial`, `emuSetSavePath`, `emuSaveBattery`, `emuLoadBattery` appear in no task's Produces; plan ships `saveBattery(e, rom_path)` instead of spec's `emuSaveBattery(e)` + `emuSetSavePath`. Spec §11 drift → operator approval or exact restoration.
4. Task ordering inversion: Tasks 2–4 declare `cpuStep(cpu: *Cpu, bus: *Bus)` but `Bus` is produced by Task 5. Tasks 2–4 cannot compile as written; move a Bus facade earlier or stub it.
5. Win9x save-update bug: `std.file.rename` → `MoveFileA` (`sf/src/std_file.zig:399`) fails when the destination exists, so updating an existing `.sav`/`.rtc` always errors on Win9x; `MoveFileExA` is not in the KERNEL32 whitelist (`scripts/win32_cross/check_win9x_imports.sh:26`). Choose delete-then-rename or amend the whitelist.
6. Z98 `-fsafe` idioms under-specified for a wrap-heavy core: `value << 8` on `u8` (Task 5 Step 3) is invalid; `u16` divider ticks and all SM83 shift/rotate bit-loss trap under checked arithmetic (`Language_Spec_Z98.md:463`; `examples/z98/z9dbg/dwarf_lines.zig:120-122`). Mandate widen→mask→cast in the plan; tests run under `-fsafe`.
7. Spec §8.5 post-boot register state (A=0x01…PC=0x0100, LY=0x91) and EI delay are unmapped to any task step.
8. Mooneye oracle checks `B=3` only; upstream contract is Fibonacci 3/5/8/13/21/34 in B–L (fail = 0x42×6). Weaker check can false-pass abnormal stops; use the full signature.
9. Inherited P1 blockers unaddressed: Task 0's "P1 loader stub" / "`Emu` fixed ROM buffer" don't exist (p1-review findings 5–6), and Task 1's `git add testdata/synth/minimal.gb` is blocked by P1's recursive `*.gb` ignore (p1-review caveat 4) with no `!synth/` negation added here.
10. `div_write.gb` is a hard gate but DIV-write semantics (divider reset, falling-edge TIMA bump) are never specified in Task 6.

**Minor:**
11. RAM-size header table absent — only `ram=0` is ever tested; `cartRamSize` behavior for 2K/8K/32K/128K unverified.
12. Serial interrupt "after 8 cycles" — ambiguous units vs spec's "8 T-cycles"; harmless for gates, misleading for later timing work.
13. Task 2/3 opcode-range overlap (`0x00-0x3F` claimed by both).
14. `FF46`/DMA ownership split between Task 5 and Task 7 register lists.
15. `manifest.sha256` hash verification is promised (Global Constraints) but no runner implements it.
16. Blargg verdict strings unpinned; upstream has no programmatic result contract — pin exact per-ROM strings from a reference run.
17. RSS evidence still ROM-less (P1 `measure_rss.sh` runs with no ROM); P2 closeout must measure with a max-size ROM loaded.
18. RTC test "after host seconds" is nondeterministic; consider an injectable clock offset to keep the headless tier deterministic.
19. `Cart` ROM storage must reference the shared 8 MiB `Emu` buffer, not copy it (12 MiB RSS budget).
20. Milestones M1–M4 (project1_phase4.txt:340-343) are never referenced in the plan; all milestone demonstrables collapse into Task 9 — no mid-plan independently verifiable milestone gate.

### Top operator decisions

1. **Gate budget policy:** raise per-ROM frame budgets (and add "no verdict = FAIL"), or switch the Blargg runner to run-until-verdict with a cap? Re-derive from a reference emulator run.
2. **dmg-acid2 golden provenance:** capture with which palette/emulator/frame? Committing a golden produced by the plan's own renderer after eyeballing the official reference image is the safest option.
3. **Spec §8.2 facade:** approve the plan's drifted save/serial/rom API shapes as a spec amendment, or require the exact `emu*` signatures in P2?
4. **Win9x save overwrite:** accept delete-then-rename (non-atomic) or whitelist `MoveFileExA`?
5. **P1 prerequisites:** amend P1 first (loader stub, `!synth/` gitignore negation, `Emu` ROM buffer) or restate P2 Task 0/1 to be self-contained?
