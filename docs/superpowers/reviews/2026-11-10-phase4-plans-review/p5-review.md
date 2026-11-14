# P5 Review — SM83 Dynarec Plan (2026-11-10-phase4-p5-dynarec-plan.md)

**Reviewer:** independent plan reviewer (review-only; no plan/spec/source edits)
**Date:** 2026-11-10
**Scope:** PLAN 5 of 5 (full SM83 block dynarec + interpreter fallback). Final plan review.
**Inputs:** spec `docs/superpowers/specs/2026-11-10-phase4-project1-gameboy-design.md`; plan `docs/superpowers/plans/2026-11-10-phase4-p5-dynarec-plan.md`; prior reviews p1–p4 in this directory; repo: `sf/src/std_page.zig`, `docs/reference/Language_Spec_Z98.md`, `examples/torrent_example_defects.md`, `scripts/win32_cross/check_win9x_imports.sh`.
**Operator rulings in force:** dynarec must land (M8 required); no predetermined speedup gate; 1 MiB fixed executable code cache separate from 1 MiB stack.

## Status Table

| # | Dimension | Status |
|---|-----------|--------|
| 1 | Objective coverage (M8 vs spec) | DONE | §1 |
| 2 | Interface consistency (P2–P4, DynCtx, CGB, invalidation) | DONE | §2 |
| 3 | Win9x soundness (VirtualAlloc EXECUTABLE, fallback, FlushInstructionCache) | DONE | §3 |
| 4 | Achievability under pure Z98 (byte emission, @intToPtr) | DONE | §4 |
| 5 | Test evidence quality (parity, invalidation, silent-skip risk) | DONE | §5 |
| 6 | Memory model (1 MiB cache accounting, stack, RSS) | DONE | §6 |
| 7 | Dependencies/ordering (P4→P5 contract) | DONE | §7 |
| 8 | Plan structure quality | DONE | §8 |
| 9 | Fact table | DONE | §9 |
| 10 | Caveat list | DONE | §10 |
| — | Verdict | DONE | VERDICT |



## 1. Objective coverage (spec M8 → P5 task mapping)

M8 (spec:37 "A full SM83 block dynarec with interpreter fallback, integrated and measured"; spec:138 "P5: full test-ROM/homebrew parity with the interpreter; no fixed speedup gate"; spec:25 "The dynarec is required").

| Spec requirement | P5 coverage | Verdict |
|---|---|---|
| Full SM83 block dynarec (spec:37, §8.10) | Tasks 1-4 (block IR, x86 emitter, control/CB, cache) | MAPPED but coverage claim unproven (IR too small/unspecified — §2/§5) |
| Interpreter fallback kept as oracle (spec:471-472) | Global Constraints line 21; Task 5 Step 2 dispatch | MAPPED |
| 1 MiB fixed executable code cache, separate from stack (spec:88, :458-460) | Global Constraints 17-18; Task 4 (`CODE_CACHE_BYTES=1048576`); Task 7 Step 2 accounting | MAPPED |
| Direct-mapped 4,096-entry table; block max 4 KiB; flush on MBC bank writes and when full (spec:461-462) | Global Constraints 20; Task 4 Step 2 | MAPPED (wording ambiguity, §6) |
| Translation unit: block until branch/call/ret/HALT/STOP or 64 insns (spec:463-464) | Task 1 Step 2 | MAPPED (HALT/STOP contradiction, §2) |
| ABI `DynCtx{cpu,bus,cycles}`, block = `fn (*DynCtx) u32` cdecl via `@ptrCast`, no inline asm (spec:466-470) | Task 2 Interfaces/Step 2; Task 4 Step 3 | MAPPED, verbatim |
| VirtualAlloc RWX mapping; disable-and-fallback if it fails; not a PASS claim (spec:458-460, :541-543) | Global Constraints 18-19; Task 0 Step 1; Task 5 Step 3 | MAPPED (§3) |
| Full test-ROM/homebrew parity with dynarec on AND off (spec:138, :473) | Task 6 Steps 1-2; Task 5 Step 4 | PARTIAL: test ROMs mapped; **homebrew parity UNMAPPED** (Task 6 names only test-ROM suites; the P3/P4 homebrew subject is itself unpinned — p3-review caveat 4) |
| Integrated and measured (spec:37, :474) | Tasks 5, 7 | MAPPED |
| No predetermined speedup threshold (spec:474; operator ruling) | Global Constraints 23; Task 7 Step 1 "Label all numbers measured" | MAPPED |
| Anti-goal: no "fast" dynarec that fails test ROMs or falls back silently (spec:56) | Global Constraints 19, 21; Task 5 Step 3 records fallback reason | **PARTIAL — vacuous-parity hole (§5 Critical 1)** |
| §5.3 closeout requires present/passing, SKIP never PASS (spec:111-112) | Task 7 Step 4 "PASS or SKIP truthfully" | **CONTRADICTED** — full-SKIP closeout possible (same defect as p4-review Critical 3) |
| §8.10 "returning T-cycles or a stop reason" (spec:469) | Plan pins return = T-cycles; 0 = fallback sentinel | MAPPED as simplification (compatible; blocks never need a stop reason since interrupts/HALT/STOP go to the interpreter) — note only |

**Parity-gate unambiguity and P2-harness inheritance:** Task 6 Step 1 (same ROMs twice, compare serial log + framebuffer hash + save RAM + audio sample count) is a sound parity shape and inherits the P1 full-buffer-hash fix. But the plan never states that the tier runners must carry the **amended P2 verdict semantics** (`--turbo`, run-until-terminal-verdict with generous cap, "cap without verdict = FAIL, never SKIP" — the fix for p2-review Critical 1). It modifies `tier_dmg.sh`/`tier_audio.sh`/`tier_cgb.sh` (Task 6 Files) and says only "PASS or SKIP truthfully; no new failures" (Task 6 Step 2) — the exact weak phrasing p4-review Critical 3 condemned. If those scripts were amended post-review, re-running them is fine, but P5 must say "inherit the amended P2 verdict harness verbatim" or an executor rewriting the runners can silently reintroduce the fixed-frame mistake. Two further gaps: audio parity compares **count, not sample bytes** (content divergence passes), and run lengths for the parity comparison ("for each present ROM") are whatever the tier scripts pin — unstated here.

**Unmapped spec items:**
1. Homebrew parity (spec:138) — no task runs homebrew with dynarec on/off.
2. §5.3 closeout present/passing pressure — Task 7 Step 4 tolerates SKIP-only.
3. Silent-fallback detection for `--dynarec` gate runs (anti-goal spec:56) — see §5.

## 2. Interface consistency (P2-P4 outputs, DynCtx, CGB, invalidation)

**Consumption of P2-P4 (PROVED consistent):**
- `Cpu`/`Bus` from P2 (`blockBuild(cpu: *const Cpu, bus: *Bus, ...)`, `DynCtx{cpu: *Cpu, bus: *Bus, cycles: u32}`) — matches spec §8.10 verbatim (spec:466-468; spec says `CpuState`, P2 names it `Cpu` — trivial name drift only).
- Generated block signature `fn (*DynCtx) u32` cdecl (plan Task 2 Step 2) — spec:469 verbatim. `@ptrCast(fn (*DynCtx) u32, code_ptr)` (Task 4 Step 3) — spec:470 verbatim ("Compiled via `@ptrCast` to a function pointer").
- `EmuConfig.dynarec: bool` (Task 5) — already exists post-P1 amendment (p1 plan:119-120 per p3-review §2); P5 wires it. CLI `--dynarec`/`--no-dynarec` (Task 5) is new and closes the p4-review fact 25 gap (no dynarec CLI existed). **Default state (on/off) is unspecified** (Minor).
- `emuSetDynarec(e: *Emu, on: bool) bool` (Task 5 Produces) is **not in spec §8.2's facade list** — same §11 API-addition drift class as p1-review's `emuSelfTestPattern` note; operator approval or mark internal (Minor).
- Task 5 Files lists `platform/win32.zig` with **no stated reason** — dynarec is core-side; the edit is unmotivated (Minor).

**Contract drift / gaps vs spec and P4:**
1. **CGB double-speed is never mentioned in the plan (Important).** P4 introduces `cpu_cycles`/`dot_cycles` and the p4-review already pinned the open item ("`emuRunFrame` cycle unit under double speed unpinned — P5-visible", p4-review caveat 14). P5 blocks return T-cycles into `DynCtx.cycles`; in double speed a frame is 140,448 CPU T / 70,224 dots. P5 must pin: blocks return **CPU T-cycles**, the dot conversion lives in one named place, and `emuRunFrame`'s return unit is unchanged from whatever P4 pins. Silent on both = the KEY1 flip can desynchronize parity accounting.
2. **Bank-switch invalidation contract (Task 4 Step 2 / Task 5 Step 3): "On any MBC bank register write, `dynarecFlush`"** — matches spec:461-462 ("flush on MBC bank writes"). Two holes: (a) a block containing an MBC-register write **continues executing its stale translation** afterwards (real hardware re-fetches from the new bank; the block must end at writes to `0x0000-0x7FFF`, or the write helper must force early block exit + re-dispatch); (b) **RAM/WRAM/HRAM-executed code is never invalidated** — a translated block from WRAM whose bytes the game later overwrites runs stale code forever (only MBC writes flush). Both are silent wrong-code paths, violating the plan's own Global Constraints line 21 ("No silent wrong-code path"). HDMA needs no cache invalidation (VRAM is never translated) but its mid-block start via `helperIoWrite` drags in the time-sync problem below.
3. **Block-termination contradiction (Important).** Task 1 Step 2 ("stop … at HALT/STOP") and Task 3 Step 3 ("End blocks after taken jumps, CALL, RET, HALT, STOP") disagree on whether HALT/STOP are inside the block, and both conflict with Task 5 Step 2 ("Interrupt/HALT/STOP paths always use the interpreter"). If the emitter ever emits HALT, the HALT bug/EI-delay/wake-up semantics run in generated code. Must be one rule: blocks end **before** HALT/STOP (and before EI/DI if those are interpreter-owned).
4. **`BlockOp` enum cannot represent "full SM83" as listed (Important).** `{nop, ld_rr, ld_rn, ld_mem, alu_r, alu_n, incdec, jump, call, ret, cb, unsupported}` with `BlockInsn{a: u8, b: u8, imm: u16}` leaves EI/DI, RST, DAA/SCF/CCF/CPL, RLCA/RRCA/RLA/RRA, LDH, `LD (a16),SP`, `ADD SP,e8` (signed), `LD HL,SP+e8`, PUSH/POP encoding undefined. Spec §11 delegates "exact dynarec block IR" to the plan — the plan owes a complete 256+256 opcode mapping (Task 3's tests mention PUSH/POP which fit no declared member). If unmapped opcodes silently become `unsupported` → per-instruction interpreter, the dynarec can degenerate into an interpreter wrapper and still pass parity (§5).
5. **Peripheral time-sync at helper calls is unspecified (Critical-adjacent, detailed §5).** `DynCtx.cycles` maintenance *during* the block and whether `helperIoRead`/`helperRead8` tick the bus to the current intra-block cycle point are undefined; interpreter parity for any mid-block LY/TIMA/DIV/STAT read depends on it.

**Trampoline / call-out ABI (PROVED):** generated block is cdecl `fn (*DynCtx) u32`, `DynCtx` passed as stack arg, prologue saves `ebx/esi/edi/ebp`, cycles in `eax` (Task 2 Step 2) — correct cdecl discipline (caller-saved eax/ecx/edx). Helpers are `extern "c"` **cdecl definitions** — legal spelling per `Language_Spec_Z98.md:370` (`extern "c" fn f(...) { ... }` is a cdecl definition; `extern "cdecl"` would be wrong and is not used). Helper addresses embedded via `@ptrToInt` (Task 3 Step 2) — function values are legal operands (`std_gfx_pal.zig:1115` casts `DefWindowProcA` through `@ptrCast(*void, …)`). One emitter detail unpinned: cdecl arg slots are 4 bytes — `u16`/`u8` params (`helperRead8(addr: u16)`) must be pushed as zero-extended 32-bit slots (Minor).

## 3. Win9x soundness (CRITICAL dimension)

### 3.1 VirtualAlloc(PAGE_EXECUTE_READWRITE=0x40) and the fallback path

- **Constant value:** `PAGE_EXECUTE_READWRITE = 0x40` (plan Global Constraints line 18) is the correct Win32 `winnt.h` value. The repo itself defines only `PAGE_NOACCESS=1`, `PAGE_READWRITE=4` (`sf/src/std_page_pal.zig:46-47`); `std_page` has **no executable-page support** (`std_page.zig:103` reserves `PAGE_NOACCESS`, `:118` commits `PAGE_READWRITE` only), so the plan's "std_page-free `VirtualAlloc` externs" (Tech Stack) is the only shape available without touching `sf/src` (which would rotate the seed — correctly avoided, Global Constraints line 24). The plan's Task 0 Step 1 probe is exactly the verification step the flag needs. **Value PROVED; Win9x kernel acceptance remains UNPROVEN on real hardware** (spec risk 8, spec:541-543).
- **Disable-and-fallback: PRESENT and correct.** Global Constraints line 19: "If `VirtualAlloc` fails, dynarec is disabled and the interpreter runs. That is not a dynarec PASS claim." Task 5 Step 3: "On `VirtualAlloc` failure, `dynarecEnabled=false` and the interpreter runs; record the fallback reason." This matches spec:542-543 verbatim in substance. Task 0 Step 4 records "exact results and the Wine version" — honest evidence labeling for the probe. Task 7 Step 3 README duty includes the "real-hardware caveat" and Task 7 Step 1 "Label all numbers measured" — the evidence-hygiene language the anti-goals demand (spec anti-goal 2).
- **Honest label check:** the plan never claims Win98-hardware proof; Wine results are labeled with the Wine version. PROVED honest.

### 3.2 Cache coherency — FlushInstructionCache (gap)

- **`FlushInstructionCache` IS whitelisted**: `scripts/win32_cross/check_win9x_imports.sh:26` (`KERNEL32_9X`) includes `FlushInstructionCache` (and `VirtualAlloc`, `VirtualFree`, `VirtualProtect`, `VirtualQuery` — the full set the dynarec needs; **no whitelist change required by P5**, PROVED).
- **The plan never uses or mentions it (Important).** The repo has a proven wrapper and precedent: `sf/src/std_os.zig:225-226` `flushInstructionCache` → `std_os_pal.zig:65` `extern "stdcall" fn FlushInstructionCache(...)`; `examples/z98/z9dbg/backend_win98.zig:210` calls it after writing code bytes to a process (and `:5` documents it as Win95/98-safe). On uniprocessor P6 (Pentium II) x86 the processor snoops its own writes so self-modifying code is *architecturally* correct without a flush, but Microsoft's documented contract is to flush before executing written code, and the plan's Task 4 Step 3 writes bytes then immediately calls them. Fix is cheap and precedent-backed: call `os.flushInstructionCache(GetCurrentProcess(), …)` after populating a block (both symbols whitelisted), or explicitly document the uniprocessor-snooping argument and keep the flush in the Task 0 probe as evidence. As written it is neither.
- Uniprocessor/self-modifying-code note: single-threaded P2, one core — no cross-modifying-code hazard; the flush is contract hygiene, not a correctness necessity on this target. Rank: Important (documented-contract gap), not Critical.

### 3.3 Memory accounting on Win9x (1 MiB cache vs 1 MiB stack vs 12 MiB RSS)

- The cache is a single `VirtualAlloc(NULL, 1 MiB, MEM_COMMIT|MEM_RESERVE, 0x40)` mapping — 1 MiB fully committed; committed executable pages **count toward RSS** on Win9x once touched. Composition: P4 static ≈ 8.75 MiB + 1.47 MiB DDraw offscreen (p4-review §6) + 1 MiB code cache + entry-table metadata (4,096 entries × {pc u16, code_off u32, len u32, valid} ≈ **48-64 KiB static**, size unstated in the plan) ≈ **11.3 MiB** vs the provisional 12 MiB target — fits but the remaining headroom is thin and the plan's Task 7 Step 1 reports RSS without a bound (report-only is acceptable per spec:474 but must include the cache in the decomposition). Task 7 Step 2 prints `code_cache_bytes=1048576`, `stack_limit=1048576`, `static_bytes` — good shape (spec:87-88 "separate ... Not stack" enforced by construction + the double-close/open tests); **`static_bytes` must include the 4,096-entry table** (unstated).
- "Never a stack array and never in static BSS" (Global Constraints line 17) — the `Dynarec` struct with its entry table *is* static (that is where the metadata lives); the constraint applies to the **code cache**, and the plan's wording ("It is never a stack array and never in static BSS") correctly scopes to the code bytes. PROVED consistent.

### 3.4 No-CRT / import-gate compatibility

- `VirtualAlloc`/`VirtualFree` are plain kernel32 stdcall imports — allowed by the 9x whitelist (`check_win9x_imports.sh:26`) and need no CRT. Task 0 Step 2 runs the import gate and expects PASS "both symbols are already whitelisted" — **PROVED** (the whitelist line literally contains both).
- Prototype supply for the plan's own externs: modules **without** `@cInclude` get C89 old-style `()` declarations auto-emitted (`sf/src/c89_emit.zig:2205-2213` `emitExternDeclFor`), ABI-safe "because every such extern takes only promotion-stable types (pointers, ints)" — `VirtualAlloc(addr: *void, size: usize, typ: u32, protect: u32) *void` qualifies (PROVED feasible). The cleaner proven pattern is the `std_page_prelude.h` / z9play shape (`examples/z98/z9play/platform/audio_win9x_pal.zig:10-11`: prototypes come from a module that `@cInclude`s `<windows.h>`). The plan pins neither ("std_page-free `VirtualAlloc` externs" only). Minor: state which prototype path is used.
- Calling convention: `VirtualAlloc` must be declared `extern "stdcall"` (as `std_page_pal.zig:43` does). The plan doesn't spell it; trivial but must not be left as `extern "c"` (would corrupt the stack on stdcall callees). Minor.
- Generated code and helpers: helpers are ordinary Z98 functions in the no-CRT binary; generated x86 uses no CRT. PROVED compatible.

### 3.5 Trampoline call-out ABI

- Generated block `fn (*DynCtx) u32` cdecl — arg on stack, callee saves `ebx/esi/edi/ebp`, returns cycles in `eax` (Task 2 Step 2) — correct cdecl (Language_Spec_Z98.md:41, :572-586: fn-pointer types carry the convention; `@ptrCast` may retype — the exact trampoline shape). Helpers `extern "c"` cdecl (Task 3 Step 2) — correct Z98 spelling for cdecl **definitions** (Language_Spec_Z98.md:370). PROVED.
- **Stack-alignment hazard (Important, unpinned):** gcc-compiled i686 helpers may assume 16-byte stack alignment at entry (SSE `movaps` in struct copies). The generated prologue/epilogue and every helper call site must keep the documented alignment (push args to a 16-byte boundary before `call`, or build the example with `-mno-sse*` / `-mpreferred-stack-boundary=2`). The plan is silent; this is a real crash class on MinGW builds and invisible under casual Wine testing.

### 3.6 Verdict for §3

Fallback path and honest labeling: PROVED present and spec-shaped. Import gate: PROVED (no whitelist delta needed). The two real gaps are the unused-but-whitelisted `FlushInstructionCache` and the unpinned stack-alignment/ABI hygiene for emitted calls. Real-hardware executable-memory behavior stays unproven exactly as the spec says; the plan handles that honestly.

## 4. Achievability under pure Z98

| Construct the plan needs | Status | Evidence |
|---|---|---|
| x86 emission as byte arrays through `[*]u8` (`Emit{code: [*]u8, len, cap}`) | PROVED | many-item pointers are core types (`Language_Spec_Z98.md:76`); writes are plain indexing; `@ptrCast([*]u8, mapping)` from the `*void` VirtualAlloc return is an established cast shape |
| fn-pointer cast from a code address (`@ptrCast(fn (*DynCtx) u32, code_ptr)`) | PROVED | **exact in-tree precedent**: `examples/z98/lisp_interpreter/eval.zig:123` casts a data pointer to `fn (...) !*value_mod.Value` and calls it; `Language_Spec_Z98.md:575-578` "Explicit `@ptrCast` … stay legal" for retyping fn-pointer signatures; `@intToPtr`/`@ptrToInt` round trips explicitly accepted (:578-580) |
| Function values as addresses (`@ptrToInt` of helpers) | PROVED | `std_gfx_pal.zig:1115` `@ptrCast(*void, DefWindowProcA)` — function name as value; `@ptrToInt` is `Language_Spec_Z98.md:323` |
| `extern "c"` cdecl helper definitions | PROVED | `Language_Spec_Z98.md:370` (body-carrying `extern "c"` = cdecl definition) |
| `extern "stdcall" fn VirtualAlloc(...)` extern declaration | PROVED | `std_page_pal.zig:43` exact precedent; prototype fallback `c89_emit.zig:2205-2213` |
| `@offsetOf(Cpu, ...)` for emitter offsets | PROVED | `Language_Spec_Z98.md:337`; frozen 32-bit layout model pinned on every host compiler (:25) so offsets computed at runtime match the struct the generated code mutates |
| Switch dispatch over `BlockOp` with mandatory `else` | PROVED | `Language_Spec_Z98.md:215` (switch `else` required), enum-member case labels legal (:207) |
| No inline asm | PROVED | language has no `asm`; plan emits bytes only (Global Constraints line 16) |
| Static `Dynarec` struct + 4,096-entry table (~48-64 KiB) | PROVED | static arrays fine (`Language_Spec_Z98.md:703` window) |

**Block linking/invalidation semantics:** the plan uses re-dispatch through `dynarecRunBlock` per block (no direct block-to-block linking) — simplest correct design; each block ends with PC written back and returns cycles. Expressible. **Switch dispatch for block entry:** the plan uses a direct-mapped hash table + trampoline call rather than a giant Z98 `switch` — both are expressible; the table is the better fit for 4,096 entries and matches spec:461. No construct in the plan fails to exist in Z98.

**Residual Z98 risks (all covered by the existing Task 0 probes — good):** the trampoline call through a cast fn pointer under `-fsafe` (Task 0 Step 3) is precisely the unproven-shape probe; the lisp precedent makes success near-certain. `BlockInsn{a,b,imm}` packing and the emitter's widen→mask→cast discipline (amended P2 constraint; shift-loss trap precedent `examples/z98/z9dbg/dwarf_lines.zig:120-122`) are not restated in P5's Global Constraints — the emitter computes x86 displacement arithmetic and flag math where checked-shape traps are plausible; bind the P2 `-fsafe` idiom rule (same omission p4-review caveat 7 flagged).

## 5. Test evidence quality (can an executor fake a pass or fall back silently?)

**Parity methodology (Task 6 Step 1):** same ROMs run with `--no-dynarec` and `--dynarec`; compare serial log, framebuffer hash, save RAM, audio sample count. Strong shape (hash inherits the p1-review fix), deterministic subject, both directions. Gaps: (a) **audio compares count only** — sample *content* divergence (wrong waveform, right length) passes; compare the emitted PCM bytes. (b) run budgets are whatever the tier scripts pin — fine if the amended P2 turbo/verdict harness is inherited verbatim (not stated, §1). (c) homebrew parity absent (§1).

**Invalidation tests (Task 6 Step 3):** "Fill the 1 MiB cache and run a bank-switch-heavy ROM; require correctness after flush" — covers flush-on-full and post-flush correctness. **Missing: the mid-block bank-switch case** the mandate asks about — a block that writes an MBC register and continues (stale-translation hazard, §2 gap 2a), and WRAM-resident code invalidation (§2 gap 2b). Task 6 has no test where a bank write occurs **inside** a translated block, nor where code is copied to WRAM and executed/modified. Both are silent wrong-code paths not exercised anywhere.

**Self-check of emitted code:** Task 2/3/4 unit tests compare emitted-block CPU state and cycle counts against the interpreter under `-ffast` and `-fsafe` — good per-test oracle. No exhaustive coverage test: nothing enumerates **all 256+256 SM83 opcodes** through the emitter (Task 1/2/3 test lists are illustrative subsets). Combined with the small `BlockOp` enum (§2 gap 4), legal opcodes can silently become `unsupported` → per-instruction interpreter → parity still passes → "full SM83 block dynarec" unproven. Fix: an opcode-coverage test asserting every legal opcode has a translation path (or at minimum an emitter matrix over the full primary+CB space).

**Benchmark methodology (Task 7):** "Label all numbers measured" (Global Constraints 23, Task 7 Step 1) — honest, matches the operator ruling (no speedup gate). Weakness: the benchmark ROM is **unnamed** (600 frames of what?), and cache-hit ratio is "if instrumented" — on a bank-switch-heavy game the full-flush policy may make the dynarec *slower* than the interpreter; without a named subject and hit-rate instrumentation the measured numbers can be cherry-picked. Not a gate, so rank Important-lite.

**Silent-SKIP / silent-fallback audit — the decisive question:**

1. **CRITICAL: vacuous parity on `--dynarec` runs.** If `VirtualAlloc` fails (or translation collapses), `dynarecEnabled=false` and the interpreter runs (Global Constraints 19 — correctly *not* counted as a dynarec PASS at the unit level). But **no Task 6/7 gate asserts `dynarecEnabled==true` or that any block was actually translated/executed for the `--dynarec` runs**. Then parity is interpreter-vs-interpreter → exact match → PASS, every suite green, and the "dynarec" evidence is fiction — precisely the spec anti-goal "falls back silently" (spec:56). Task 4 Step 4 checks `dynarecEnabled=true` only in the unit test. Fix (mandatory): every `--dynarec` gate run must print and assert `dynarec_enabled=1` plus a nonzero translated-block/translated-instruction counter (and ideally >0 cache hits for the primary ROMs), else FAIL — never PASS. Same counter defeats the degenerate case where the emitter marks most opcodes `unsupported` (§4).
2. **Mid-block peripheral staleness (Critical).** Blocks execute up to 64 instructions with the bus ticked only after `dynarecRunBlock` returns (Task 5 Step 2 dispatch). A mid-block `helperIoRead` of LY/TIMA/DIV/STAT then reads **stale peripheral state**, diverging from the interpreter (which ticks per instruction). The plan never defines how `DynCtx.cycles` is maintained during execution or whether helpers sync the bus to the current intra-block cycle point. Busy-wait loops escape (JR ends the block) but straight-line IO reads do not. This is a silent divergence class that some parity subjects may not exercise — leaving a wrong-code path the gates can miss. Fix: helpers must tick peripherals to `base + cycles_so_far` before observing time-dependent state (and generated code must maintain the running cycle count), or blocks must be constrained so no time-dependent read occurs mid-block.
3. SKIP policy: missing ROMs → SKIP is inherited from the tier scripts (repo convention, exit 77) — fine at ROM level, but Task 7 Step 4 "P2-P5 gates PASS or SKIP truthfully" lets closeout go green with **all** external ROMs absent — violating spec:111-112 ("closeout requires present/passing"). Same defect as p4-review Critical 3; P5 inherits and must not.
4. Verdict-string pinning / manifest hash verification (p2-review gaps) are again not addressed in P5's runners (inherited; not re-litigated).

**Verdict:** the parity design is honest in shape but has one vacuous-pass hole (silent fallback) and one silent-divergence hole (mid-block time staleness) — both squarely in the spec's anti-goal. Invalidation coverage misses the mid-block bank-switch and WRAM-code cases.

## 6. Memory model

| Item | Bytes | Source |
|---|---:|---|
| Code cache (VirtualAlloc RWX) | 1,048,576 | Global Constraints 17-18; `CODE_CACHE_BYTES` (Task 4) ✓ exact |
| Entry table (4,096 × {pc u16, code_off u32, len u32, valid}) | ≈ 49,152-65,536 (static) | Task 4 Step 2 fields; **size unstated in plan** |
| Stack limit | 1,048,576 (virtual) | spec:87; cache is never stack ✓ |
| P4 static + surfaces (composition) | ≈ 10.2 MiB | p4-review §6 |
| **P5 total (committed/touched)** | **≈ 11.3 MiB** vs 12 MiB provisional | executable pages count once written |

- Exact accounting demanded by the mandate: `4,096` direct-mapped entries ✓ (matches spec:461); metadata ≈ 48-64 KiB must appear in Task 7 Step 2's `static_bytes`. The two "4 KiB" figures are conflated (Minor): Global Constraints "Block max 4 KiB" and `BLOCK_MAX_BYTES=4096` are the **generated-code** cap; Task 1 Step 2's "64 instructions **or 4 KiB of source**" is vacuous — 64 SM83 instructions are at most 192 source bytes. Bump allocation + flush-when-doesn't-fit is consistent with 4,096 entries × up to 4 KiB = 16 MiB worst-case aggregate > 1 MiB mapping (flush handles it; Task 4 Step 1 tests the full-cache flush).
- Direct-mapped key = `pc` alone is sound **only because** bank writes flush the whole cache (spec:461-462) — keying without bank identity would alias bank 1/bank 2 at `0x4000` otherwise. Correct but load-bearing on the flush rule (which is exactly the rule with the mid-block hole, §2/§5).
- Stack rule respected by construction (no large locals anywhere in the plan); RSS re-measured in Task 7 Step 1 (report-only, consistent with spec:474). Inherited p1-review caveat (no stack-use *measurement*, spec:5.2 "report … separately") still open — P5 at least reports cache separately, which is the new region.

## 7. Dependencies / ordering

- **Internal order 0→1→2→3→4→5→6→7 is linear**; no inversions. Task 2 consumes Task 1's `Block`; Task 4 consumes emitter+builder; Task 5 consumes cache; gates last. TDD shape real (Step 1 failing test in every task).
- **P4→P5 contract:** (a) **CGB double-speed cycle unit unpinned on both sides** (p4-review caveat 14; P5 silent — §2 gap 1) — must be pinned before Task 5 touches `emuRunFrame`. (b) **HDMA**: no cache invalidation needed (VRAM is data, never translated), but HDMA started mid-block via `helperIoWrite` inherits the time-sync contract (§5 gap 2) since `hdmaTick(dots)` consumes the dot domain; note it. (c) P5's Task 6 edits `tier_cgb.sh`/`tier_audio.sh` — depends on P4/P3 gate fixes landing first (p3/p4 reviews: harness/oracle fixes are REQUIRED, not optional); P5 parity re-runs those gates, so broken P3/P4 gates propagate (already cross-flagged p4-review caveat 12). If P3/P4 are not amended, P5's "run all suites with dynarec on" inherits non-functional runners.
- `emuAudioSamples` (spec §8.2) — p3-review Gap B (unproduced) is still open in the plan set; Task 5 Step 1 parity compares "APU sample count", so P5 depends on it (or on `apuSamples` directly — plan should name which).
- Task 5's unexplained `platform/win32.zig` edit (§2) is the only file whose necessity is unclear.
- No seed rotation ✓ (files touch `examples/z98/z9gb/**` only; `sf/src/std_page.zig` is read-only — consistent with p3-review fact 31).

## 8. Plan structure quality

Template compliance (Files / Interfaces / TDD failing-test-first / Expected / scoped commit):

| Task | Files | Interfaces | TDD+Expected | Commit | Notes |
|---|---|---|---|---|---|
| 0 probes | temp only ✓ | yes | concrete (Wine version recorded; "any crash is a STOP") | n/a | best probe task in the series; trampoline probe under `-ffast`/`-fsafe` is exactly right |
| 1 block IR | yes | exact sigs | concrete forms listed | yes | IR encoding under-specified (§2 gap 4); "4 KiB of source" vacuous (§6) |
| 2 ALU emitter | yes | exact sigs | compare-to-interpreter matrix ✓ | yes | `DynCtx`/prologue/epilogue pinned; arg-slot widths unpinned |
| 3 control/CB/helpers | yes | exact sigs | concrete | yes | "spills live CPU state" — cycles/PC maintenance unpinned (§5 gap 2); HALT/STOP end-rule contradicts Task 5 |
| 4 cache/trampoline | yes | exact consts ✓ | open/distinct/flush/close/double-close ✓ | yes | `code_ptr` type unstated; "any invalid block" undefined |
| 5 integration | yes | `emuSetDynarec` (§11 drift) | parity test first ✓ | yes | dispatch/invalidation have the two silent-path holes (§2/§5) |
| 6 parity gates | yes | — | run-twice compare ✓ | yes | no dynarec-enabled assertion; no mid-block bank-switch test; closeout "PASS or SKIP" weak |
| 7 perf/closeout | yes | — | measured labels ✓ | yes | benchmark ROM unnamed; no bound on RSS (report-only is spec-consistent) |

Vague/unverifiable steps flagged: Task 4 Step 3 (`code_ptr` type, "any invalid block flushes and falls back" — "invalid" undefined); Task 6 Step 1 (run length per parity subject; compare method for audio — count only); Task 7 Step 1 (unnamed ROM; "cache-hit ratio if instrumented" makes an optional out of the most diagnostic number); Task 5 Step 2 ("at instruction boundaries" is right but the intra-block peripheral contract is missing).

Positive structure notes: Task 0's probe-before-build discipline is exemplary; every task commits scoped; Global Constraints enumerate the memory/ABI/fallback invariants; Review Focus names exactly the right subsystems (cache ownership, block boundaries, emitter flags, fallback, parity); "no seed rotation" explicit; Expected outputs are concrete where written.

## 9. Fact table

| # | Claim (plan location) | Verdict | Evidence |
|---|---|---|---|
| 1 | `PAGE_EXECUTE_READWRITE = 0x40` (Global Constraints 18) | PROVED (value) | Win32 `winnt.h` constant; repo defines only `PAGE_NOACCESS=1`/`PAGE_READWRITE=4` (`sf/src/std_page_pal.zig:46-47`) — plan must define 0x40 itself, which it does |
| 2 | `VirtualAlloc`/`VirtualFree` "already whitelisted" (Task 0 Step 2) | PROVED | `scripts/win32_cross/check_win9x_imports.sh:26` `KERNEL32_9X` contains both (also `VirtualProtect`, `VirtualQuery`, `FlushInstructionCache`) |
| 3 | Executable-memory behavior on real Win9x | INCOMPLETE (honestly labeled) | spec:541-543 (risk 8); Wine probe (Task 0) is functional evidence only; plan never claims hardware proof |
| 4 | Disable-and-fallback on `VirtualAlloc` failure is present (Global Constraints 19, Task 5 Step 3) | PROVED | plan text; matches spec:542-543 |
| 5 | `FlushInstructionCache` used to keep the code cache coherent (implicit) | **DISPROVED (absent)** | whitelisted (fact 2) and precedented (`sf/src/std_os.zig:225-226`, `sf/src/std_os_pal.zig:65`, `examples/z98/z9dbg/backend_win98.zig:210`) but never mentioned in the plan |
| 6 | Code cache separate from the 1 MiB stack / not in BSS (Global Constraints 17) | PROVED by construction | `VirtualAlloc` mapping (Task 4); Task 7 Step 2 prints the accounting |
| 7 | Direct-mapped 4,096 entries, block max 4 KiB, flush on MBC writes and when full (Global Constraints 20) | PROVED | matches spec:461-462 verbatim; worst-case 4,096×4 KiB = 16 MiB > 1 MiB handled by flush |
| 8 | `@ptrCast(fn (*DynCtx) u32, code_ptr)` is expressible in Z98 (Task 4 Step 3) | PROVED | `examples/z98/lisp_interpreter/eval.zig:123` exact shape; `Language_Spec_Z98.md:575-580` |
| 9 | `@ptrToInt` on helper function values (Task 3 Step 2) | PROVED | `Language_Spec_Z98.md:323`; fn-as-value precedent `sf/src/std_gfx_pal.zig:1115` |
| 10 | `extern "c"` helpers = cdecl ABI (Task 3 Step 2) | PROVED | `Language_Spec_Z98.md:370` (cdecl definitions); plan's spelling correct (`extern "c"`, not `extern "cdecl"`) |
| 11 | `@offsetOf(Cpu, …)` usable for emission (Task 2 Step 3) | PROVED | `Language_Spec_Z98.md:337`; layout pinned on all host compilers (:25) |
| 12 | `std_page`-free VirtualAlloc externs buildable no-CRT (Tech Stack) | PROVED | old-style prototype fallback `sf/src/c89_emit.zig:2205-2213` (ptr/int args only — VirtualAlloc qualifies); prelude pattern `examples/z98/z9play/platform/audio_win9x_pal.zig:10-11`; must be `extern "stdcall"` (`std_page_pal.zig:43`) — plan doesn't spell the convention |
| 13 | No inline asm / pure Z98 constraints (Global Constraints 15-16) | PROVED | language has no `asm`; matches spec §5.1 |
| 14 | No seed rotation; P5 touches only the example (Global Constraints 24) | PROVED | all Files under `examples/z98/z9gb/`; `sf/src/std_page.zig` read-only (p3-review fact 31 pattern) |
| 15 | `EmuConfig.dynarec` produced by P5 (Task 5) | PROVED (already exists) | post-P1 amendment (p1 plan:119-120 per p3-review §2); P5 wires it + adds CLI |
| 16 | `emuSetDynarec` is a spec API (Task 5 Produces) | **DISPROVED** | absent from spec §8.2 facade list — §11 amendment class (p1-review `emuSelfTestPattern` precedent) |
| 17 | `DynCtx{cpu, bus, cycles}` + block `fn (*DynCtx) u32` cdecl (Task 2) | PROVED | spec:466-470 verbatim |
| 18 | "End blocks after … HALT, STOP" (Task 3 Step 3) vs "HALT/STOP paths always use the interpreter" (Task 5 Step 2) | **DISPROVED (self-contradictory)** | the two rules cannot both hold; see §2 gap 3 |
| 19 | `BlockOp`/`BlockInsn{a,b,imm}` covers full SM83 (implied by "full SM83 block dynarec", Global Constraints 21) | INCOMPLETE | enum lacks EI/DI/RST/DAA/SCF/CCF/CPL/RLCA-group/LDH/LD(a16)SP/ADD SP,e8/PUSH/POP encodings; no 256-opcode coverage test |
| 20 | Parity gates prove dynarec correctness (Task 6) | **DISPROVED as sufficient** | `--dynarec` runs can silently run the interpreter (no enabled/translation-counter assertion) → vacuous PASS (§5 gap 1) |
| 21 | Bank-switch invalidation complete (Task 5 Step 3) | **DISPROVED (incomplete)** | mid-block MBC write leaves stale translation live; WRAM/HRAM code writes never flush (§2 gap 2) |
| 22 | Generated blocks return exact interpreter cycles (Task 4 Step 4) | PROVED as test design | per-block cycle equality is asserted; audio-count parity follows if cycles match |
| 23 | CGB double-speed handled (implicit) | **DISPROVED (silent)** | plan text never mentions KEY1/double speed; cycle unit contract unpinned (p4-review caveat 14) |
| 24 | D16 (`examples/torrent_example_defects.md:8,16`) affects P5 | PROVED NOT RELEVANT | D16 = assignment-expression/switch parity deferral; P5 uses plain exhaustive switches + assignments; no exposure |
| 25 | No fixed speedup gate; measured labels (Global Constraints 23) | PROVED | operator ruling honored; "Label all numbers measured" (Task 7 Step 1) |
| 26 | Benchmark subject identified (Task 7 Step 1) | **DISPROVED** | 600 frames of an unnamed ROM; cache-hit ratio optional |
| 27 | Closeout satisfies spec:111-112 present/passing (Task 7 Step 4) | **DISPROVED** | "PASS or SKIP truthfully" permits all-SKIP green closeout (p4-review Critical 3 shape) |
| 28 | Task 0 probes cover the unproven shapes (fn-pointer trampoline under `-ffast`/`-fsafe`, VirtualAlloc, import gate) | PROVED | plan text; matches the exact verification needs |

## 10. Caveat list (Win9x-implementation and general)

1. **Vacuous parity via silent fallback (Critical):** `--dynarec` gate runs must assert `dynarec_enabled=1` and a nonzero translated-execution counter, else interpreter-vs-interpreter parity passes with zero dynarec evidence (spec anti-goal :56). Same counter closes the "everything `unsupported`" degenerate case.
2. **Mid-block peripheral staleness (Critical):** helpers must sync bus/peripherals to the intra-block cycle point (`DynCtx.cycles` maintenance during the block is unspecified); otherwise mid-block LY/TIMA/DIV/STAT reads diverge from the interpreter and parity ROMs may not catch it.
3. **Invalidation incompleteness (Critical/Important):** end blocks at writes to `0x0000-0x7FFF` (MBC registers) or force re-dispatch after them; decide the WRAM/HRAM code policy (flush on writes to translated RAM regions, or translate ROM-resident PC only and fall back otherwise). "No silent wrong-code path" (Global Constraints 21) currently has two holes.
4. **`FlushInstructionCache` unused (Important):** whitelisted (`check_win9x_imports.sh:26`) with in-tree precedent (`std_os.zig:225`, `z9dbg/backend_win98.zig:210`); call it after cache writes or document the uniprocessor-snooping argument explicitly.
5. **Interrupt-latency drift (Important):** interrupts are checked per block, not per instruction — up to 63 instructions of IME-recognition delay vs the interpreter; timing subjects (Mooneye `stat_irq_blocking`, `interrupt_time`) may diverge with dynarec on. State the policy (accept + let parity gates judge, or split blocks around EI/IME-on regions).
6. **HALT/STOP block-rule contradiction (Important):** Task 1/3 vs Task 5 disagree; pin "blocks end before HALT/STOP (and EI/DI if interpreter-owned)".
7. **Full-SM83 coverage unproven (Important):** `BlockOp` enum + no 256-opcode emitter-coverage test leave legal opcodes free to degrade silently to `unsupported`.
8. **CGB double-speed contract silent (Important):** pin blocks return CPU T-cycles and the `emuRunFrame` unit against P4's `cpu_cycles`/`dot_cycles` (p4-review caveat 14).
9. **Homebrew parity unmapped (Important):** spec:138 gate includes homebrew; benchmark ROM unnamed (Task 7) — pin subject + sha (inherited p3/p4 vapor-gate shape).
10. **Closeout without teeth (Important):** "PASS or SKIP truthfully" (Task 7 Step 4) violates spec:111-112; require the pinned suites present/passing or operator sign-off.
11. **Audio parity compares count only (Minor→Important):** compare sample bytes.
12. **Emitted-call stack alignment (Important):** pin 16-byte alignment discipline for helper calls (or `-mno-sse*`/`-mpreferred-stack-boundary=2`); MinGW helpers can crash on misalignment.
13. **Win9x executable memory remains unproven on hardware (accepted risk):** handled honestly (fallback + labeled evidence); operator hardware sign-off stays the operator's (spec:541-543).
14. **Minor:** `emuSetDynarec` §11 API drift; `platform/win32.zig` edit unexplained; `extern "stdcall"` convention for the VirtualAlloc externs unpinned; arg-slot widths (u8/u16 pushes) unpinned; "4 KiB of source" vacuous; entry-table size missing from `static_bytes`; `code_ptr` type / "invalid block" undefined; default dynarec state unspecified; `-fsafe` widen→mask→cast idiom not bound (p2/p4 inherited).

---

## VERDICT

**NEEDS FIXES**

The plan's architecture matches spec §8.10 almost verbatim, its probe-first Task 0 is the strongest in the series, the Z98 emission story is fully precedented (the lisp `@ptrCast(fn …)` and `std_os.flushInstructionCache` precedents settle the two hardest achievability questions), the Win9x fallback path and evidence labels are honest, and the import gate needs zero whitelist changes. But three silent-failure holes sit exactly on the spec's anti-goal ("fails test ROMs or falls back silently"): `--dynarec` gates can pass vacuously with the dynarec disabled, mid-block peripheral reads can diverge with no test forced to notice, and bank-switch/RAM-code invalidation is incomplete — while "full SM83" coverage rests on an IR enum that cannot express the opcode set it claims. These are gate-and-contract fixes, not redesigns.

### Caveats by severity

**Critical:**
1. Vacuous-parity hole: no gate asserts `dynarec_enabled` + translated-execution counters on `--dynarec` runs; silent `VirtualAlloc` failure or silent `unsupported` collapse yields interpreter-vs-interpreter PASS (spec anti-goal :56).
2. Mid-block peripheral time-sync undefined (`DynCtx.cycles` maintenance + helper bus-sync contract); stale LY/TIMA/DIV/STAT reads diverge silently.
3. Invalidation incomplete: mid-block MBC-register writes leave stale translations live; WRAM/HRAM self-modifying code is never flushed — both violate "No silent wrong-code path" (Global Constraints 21).

**Important:**
4. `FlushInstructionCache` whitelisted and precedented but unused; add it or document the uniprocessor-x86 argument.
5. HALT/STOP block-termination rules contradict across Tasks 1/3/5.
6. `BlockOp` IR too small/unspecified for "full SM83"; no exhaustive opcode-coverage test.
7. CGB double-speed cycle unit unpinned (P4→P5 contract; p4-review caveat 14 open).
8. Interrupt-check granularity is per-block; timing-ROM drift unstated and unmitigated.
9. Homebrew parity (spec:138) unmapped; benchmark ROM unnamed.
10. Closeout "PASS or SKIP truthfully" voids spec:111-112 present/passing pressure.
11. Emitted-call stack alignment / cdecl arg-slot widths unpinned (MinGW crash class).
12. Audio parity compares sample count, not sample bytes; amended P2 verdict harness (turbo/until-verdict/timeout=FAIL) must be explicitly inherited by the Task 6 runners.

**Minor:**
13. `emuSetDynarec` spec-API drift (§11 approval); unexplained `platform/win32.zig` edit; `extern "stdcall"` unpinned for the VirtualAlloc externs; "4 KiB of source" vacuous; entry-table size missing from `static_bytes`; `code_ptr`/"invalid block" undefined; default dynarec state unspecified; `-fsafe` widen→mask→cast idiom unbound; `Emit` cap-check semantics on overflow unstated.

### Top operator decisions

1. **Silent-fallback counter (mandatory fix shape):** require `dynarec_enabled=1` + nonzero translated-block/insn counters on every `--dynarec` gate run (recommended), or accept a single explicit "dynarec unsupported on this host" SKIP-with-reason that blocks closeout?
2. **RAM-code policy:** translate ROM-resident PC only (WRAM/HRAM PCs fall back to the interpreter — cheapest correct), or implement write-invalidation for translated RAM regions?
3. **Mid-block bank writes:** terminate blocks at writes to `0x0000-0x7FFF` (recommended), or accept documented divergence risk on self-bank-switching code?
4. **Interrupt granularity:** accept up-to-63-instruction IME delay and let parity gates judge, or split blocks around IME-on/EI regions for tighter timing?
5. **Benchmark subject:** which named ROM + sha for the Task 7 measurements, and should cache-hit ratio be instrumented (not optional) given full-flush-on-bank-write thrash risk?
