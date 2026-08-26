# zig1 Memory Refactor — Roadmap (≤16 MiB pool, no-OOM)

**Date:** 2026-08-26
**Status:** CONCLUSION / ROADMAP (the committed deliverable of the zig1 memory-refactor investigation plan; the refactoring itself is a future execution plan)
**Branch:** zig1_start
**Inputs:** `.superpowers/sdd/task-ROADMAP-report.md` sections I-1..I-5 (shared investigation report, incl. review-fix audit notes); design doc `2026-08-26-zig1-memory-roadmap-design.md`; plan `2026-08-26-zig1-memory-roadmap-plan.md`.

## Goal

Conclude the zig1 memory investigation with a **prioritized refactoring roadmap** for the hard operator target:

> zig1 self-compiles under a **16 MiB pool** on a P3/P4 **Windows 98 host with 32 MB physical RAM**; compilation must **never make Windows report "out of memory"**. I/O tricks (page file, partial AST/LIR disk dump) are in scope to evaluate. The deliverable is the roadmap, not the refactoring.

Every number below traces to the shared report; the governing evidence section is cited per claim (e.g. "I-1", "I-2", "I-3 Step 2", "I-4 Step 3", "I-5 Step 2"). The canonical measurement log `/tmp/za7/out.log` (self-compile, `--track-memory --markers`) is the shared anchor used by I-1, I-2, I-4 and I-5; its `track-memory` line byte-matches the memory-comparison design doc figures.

---

## 1. Current state (measured)

Anchor measurement (canonical log; I-1 / I-2):

```
track-memory: perm=1977K mod=16383K scr=2012K pool=83210K type_db=245K total=20372K
```

- **Pool cumulative peak = 83,210 K (≈81.3 MiB)** — the monotonic bump high-water of every byte ever allocated from the pool. (I-1, I-2)
- **Live working set `total` = 20,372 K (19.9 MiB)** = `perm 1,977 K + mod 16,383 K + scr 2,012 K`; `type_db 245 K` separately. (I-1, I-2)
- **Target = 16 MiB = 16,384 K.** Pool is **5.08×** the target; live is **24.3 % over** it. (I-2 review fix #2)
- **Gap = 83,210 − 20,372 = 62,838 K ≈ 61.4 MiB** of never-reclaimed pool bytes. (I-2)

**The two drivers (I-1 + I-2):**

1. **32-byte structs** (constant-factor live waste). At self-compile: `AstNode` = 32 B × **180,020** = **5.76 MB** (I-1 Step 3); `LirInst` = 32 B × ~110–130 K insts ≈ **3.5–4.2 MB** (I-1 Step 3, LIR estimate); `Token` = 20 B emitted (≈330 K total lexed, ≈15 K live ≈ 0.3 MB live peak — scratch, per-module reset; I-1 Step 3). AST + LIR together ≈ 11 MB of the 16 MiB module arena (I-1 anchor, design doc).
2. **Geometric segment doubling** (pool-side overshoot). The module arena chain reached **65,532 K (64 MiB, 13 grows 4K→32 MiB, last segment 32 MiB)** for **16,383 K live = 4.0×** (I-2 Step 2, review fix #1). Per-arena chain totals: module 65,532 K / scratch 8,188 K / import_scratch 4,289 K / perm 4,092 K / type_db 1,020 K / parser 12 K — computed Σ ≈ 83,208 K closes to the measured 83,210 K within ≈0.002 % (I-2 Step 2). The module arena alone is **78.8 % of the pool and 78.2 % of the gap** (I-2). Plus ≈ **4.2 MiB** of never-reclaimed per-`@import` scratch arenas (`parser.zig:672-676`; 217 grows across ≈320 fresh chains; I-2 Step 3 #2).

**Why the gap is waste, not data:** `pool` reports the cumulative bump high-water; each tier's live `view.peak` is the largest single-segment utilization, not the chain sum (I-2 Step 1). The pool model is exactly `Σ over arenas of (segment-chain bodies + 16 B SandSegment headers)` (I-2 Step 2). The 61 MiB gap is geometric-doubling overshoot (module 49 MiB + scratch 6.2 MiB + perm 2.1 MiB + type_db 0.8 MiB) plus never-returned import arenas (4.2 MiB) (I-2 Step 2 waste table).

**The measurement tripwire is dead:** `checkCombinedPeak` (`allocator.zig:216-228`) does `_ = alloc;` (discards `max_mem`) and gates `pool.peak` against `POOL_SIZE` (256 MiB), not the 16 MiB budget — so the current 83 MiB compile passes silently and `--max-mem` is never enforced (`main.zig:142`, `:914-917`; I-2 Step 3, I-4 Step 3). On Win98 the OS would kill the process before the compiler's own check ever fires (I-4 Step 3).

**Marker volume (orthogonal, I-5):** 1,728 marker call sites / 1,289 string-literal sites = **5,346 B** rodata (≈6.6 KB incl. NULs, ≤0.74 % of the smaller binary; I-5 Step 2). `--markers` self-compile floods fd 2: **82,436,444 B / 7,364,565 lines ≈ +27.08 s wall** (M4−M1; ≈21 s system time in unbuffered write syscalls; I-5 Step 2). ≥98.7 % of the log is ~15 per-node debug codes (measurement set = 33,793 lines = 0.46 %; I-5 Step 1). Markers allocate nothing — **zero pool bytes** (I-5 Step 4).

---

## 2. The ≤16 MiB / no-OOM frame

The target is the **pool** (cumulative committed high-water), and the pool can never be smaller than the live total. Therefore ≤16 MiB pool is reachable **only in sequence** (I-2 Step 4, I-4 Step 4):

1. **Live compaction** (I-1 structs) pulls `total` 20,372 K → ≈16.5–17 MiB;
2. **Arena geometry + reclaim** (I-2) pulls the pool from 83 MiB down to ≈ live + margin;
3. A final **~1 MB live slice** (AST side arrays + token value union) or a spill crosses below 16 MiB.

Arithmetic anchors (I-4 review fix #1, I-1 review fix #6):

- Live gap to target: 20,372 − 16,384 = **3,988 K ≈ 3.9 MiB**.
- AstNode 32→24 B: 180,020 × 8 = 1,440,160 B = **1.44 MB** (32→20 B would be ≈2.16 MB).
- LirInst 32→20 B: 12 B × ~110–130 K ≈ **1.3–1.5 MB** (32→16 B stretch ≈ 1.7–2.1 MB).
- Combined 24 B-AstNode + 20 B-LirInst ≈ **2.7–3.0 MB** → live lands ≈ **16.5–17 MiB** — still above 16 MiB, hence the final ~1 MB slice (AST side arrays ≈ 0.75–0.9 MB, I-1 Step 4) or a spill (I-4 Step 4).

**No-OOM is a bounded-demand guarantee, not an absolute one** (I-4 Step 3): on 32 MB physical the OS commits the pool against RAM + paging file; today 83 MB committed cannot be held in RAM. A compiler whose committed high-water is bounded ≤16 MiB cannot, by itself, force a Windows "out of memory" on a 32 MB host with a ≥16 MiB paging file. The OS environment (paging-file size, other processes) is outside the compiler's control. The pool is a static 256 MiB BSS (`allocator.zig:184-185`) the OS demand-pages for free, so a compiler-side spill only helps if it *returns* pool bytes (I-4 Step 2 point 5). See §4.

---

## 3. Prioritized roadmap

All items are zig0-dialect-legal (I-3 Step 1 toolkit: plain structs, `union(enum)` 4-B tag, u32/u64 + shift/mask, arrays, out-of-line value tables; **no** packed structs, bitfields, `anytype`, `@Type`). Estimates are pool-reduction (MB) at self-compile; live-side savings reduce both the live total and the pool floor by the same bytes.

| # | item | pool ↓ (MB) | live ↓ (MB) | zig0-compat | risk | effort | evidence |
|---|---|---|---|---|---|---|---|
| 0 | **Budget tripwire** (`checkCombinedPeak` vs `max_mem`) | 0 (enables all) | 0 | n/a | very low | trivial | I-2 Step 3, I-4 Step 3 |
| 1 | **AstNode 32→24 B** | ≈1.44 | ≈1.44 | plain struct (I-3 A) | low–med | med | I-1, I-3 A |
| 2 | **LirInst 32→20 B** | ≈1.3–1.5 | ≈1.3–1.5 | union(enum) (I-3 B) | med–high | med–high | I-1, I-3 B, I-4 f#1 |
| 3 | **Segment-growth policy + exact-fit final segment** | up to ≈49–58 | 0 | n/a (allocator) | med | med | I-2 |
| 4 | **Arena reclaim / pool reset** (import reuse; module reset-with-reload) | ≈4.3 + enabler | 0 | n/a (allocator) | med–high | low / high | I-2 Step 3, I-4 |
| 5 | **AST side arrays + token value union slice** | ≈0.75–0.9 (+~0.06 token) | same | legal (I-3 C) | low–med | med | I-1, I-3 C, I-4 |
| 6 | **I/O spill** (per-module LIR first; AST deferred) | after #3/#4 | 0 | n/a (I/O) | med (LIR) / high (AST) | high | I-4 |
| 7 | **Marker reduction** (Option B coarsening) | 0 (wall +99 % stderr) | 0 | n/a (pal.zig) | low | low | I-5 |

### Item 0 — Enforce the 16 MiB budget (tripwire)
Fix `checkCombinedPeak` to gate `pool.peak` against `alloc.max_mem` (16 MiB default) instead of `POOL_SIZE`, and emit the clean "memory limit exceeded" diagnostic / exit 1 path that is already written (`allocator.zig:220-227`) instead of a raw OS kill. Saves nothing, but makes every other claim in this roadmap *verifiable* — today no run could catch a 16 MiB overrun (I-2 Step 3, I-4 Step 3, I-4 Concern 4). **Sequenced first.**

### Item 1 — AstNode 32 → 24 B (live constant-factor)
Move the over-wide `payload:u64` to `payload:u32` (13+ sites already read it as a u32 low word) and the extra-children range out-of-line (`extra_ranges` pool, mirroring `ast.zig:285-289`), fold `child_2` (used by ~10 of 111 kinds) into the extra-children mechanism behind a getter (I-1 Step 2, I-3 Candidate A). Saves **1.44 MB** (I-1 review fix #6). Consumers: 16 writer sites (parser.zig `astStoreAddExtraChildren`; return changes from packed u64 to range index, incl. the sole direct packed-range reader `parser.zig:1447-1448`) + **75 getter readers** across 12 non-test files, all passing `node.payload` positionally (I-3 Step 2, I-3 review fix #1). No zig0 feature needed. **Lowest-risk live-side win; do first of the two struct cuts.**

### Item 2 — LirInst 32 → 20 B (live constant-factor)
Rebound the `union(enum)` payload to ≤16 B by side-tabling the rare wide variants (`call_direct`/`tail_call` 28 B → 16 B with module_id/return_type/is_extern in a per-function call-info side table; `int_const`/`float_const`/`enum_const` u64 values → const-pool indices; `builtin_socket_select` — I-3 Candidate B). Saves **≈1.3–1.5 MB** at the 20 B target (I-4 review fix #1). 20 B is the **zig0-natural** bound (4 B emitted tag + 16 B payload); 16 B total is the **stretch** (payload ≤12 B, reshapes ~15 four-u32 variants + every `switch(inst)` consumer in `c89_emit.zig:2780/:4324/:6308` and lower.zig — I-3 Concern 2). The 20 B cut reshapes only 5–6 wide variants; ~70 variants and their consumers are untouched. **Budget 20 B; treat 16 B as stretch.**

### Item 3 — Segment-growth policy + exact-fit final segment (the #1 pool lever)
Change `growableSandGrow` (`allocator.zig:108-130`) so the final segment is capacity-exact instead of doubled, mirroring the exact-size copies `lirFunctionRelocateToModule` already performs (`lir.zig:373-404`; I-2 Step 3 #1a), optionally with a growth cap. The module chain 65,532 K → ~16 MiB saves ≈**49 MiB**; scratch 8,188→~2,012 K ≈ −6.2 MiB, perm 4,092→~1,977 K ≈ −2.1 MiB, type_db 1,020→~245 K ≈ −0.8 MiB (I-2 Step 2 waste table). This alone removes the 4.0× overshoot and the 78.2 %-of-gap module share. Allocation-address changes only — byte-neutral for emission, no pointer-stability impact (arena-internal). **Highest-value, moderate-risk item; sequence after the two struct cuts so the module's live need is already smaller.**

### Item 4 — Arena reclaim / pool reset
**(a) import-arena reuse (low risk):** route per-`@import` scratch (`parser.zig:672-676`) through the already-reset scratch tier instead of a fresh pool chain — recovers ≈**4.3 MiB** committed-but-dead (I-2 Step 3 #2, structural truth #2). **(b) module-arena reset-with-reload (high risk):** reset the module arena at phase boundaries so the pool tracks live, not cumulative — this is the enabler that makes I-4 spill meaningful (I-2 Concern 3, I-4 Concern 1). Blocked on pointer retention (`lir.zig:365-372`) until the reload path exists; requires the I-4 residency work. **Do (a) at its recommended-order slot (after Item 5, before Item 7); gate (b) behind Item 6 — 4(b) and Item 6 are a coupled pair (reset + spill return pool bytes only together).**

### Item 5 — AST side arrays + token value union (the final ~1 MB)
Fold int literal values into the payload (small-int fast path) and side-table token values (Token 20→16 B via a plain u32 value field — the 16 B packed struct remains REJECTED by zig0, `token.zig:129-131`, but the u32 layout avoids it entirely; I-3 Candidate C). Saves ≈0.75–0.9 MB (AST side arrays; I-1 Step 4) + ≈60 KB live token peak (I-3 Candidate C). This slice takes live from ≈16.5–17 MiB to ≈15.5–16.2 MiB — it crosses below 16 MiB at the optimistic band edge, but may not fully cross at the pessimistic edge (≈16.2 MiB); the Item 6 spill fallback covers the residue (I-4 Step 4). **Do only if Items 1–3 leave the live total above target.**

### Item 6 — I/O spill (per-module LIR first; per-module AST deferred)
Per-module/per-function LIR serialization + reload is the **clean, lowest-risk spill**: `LirFunction` is a self-contained scalar unit (`lir.zig:371-372`), already grouped per module (`main.zig:775-776`), emission already streams per module with a 4,096 B buffer (`c89_emit.zig:29-64`, `main.zig:770-833`); the only non-streaming pre-pass is `ts_ref_set` (`main.zig:706-740`), trivially per-module-izable (I-4 Step 2 #2/#3). Per-module AST dump is **structurally possible** (contiguous ranges, write-once store) but **architecturally expensive**: the global flat index space is pinned by `resolved_types` (`resolved_type_table.zig:62-82`), `comptime_values` (`main.zig:398,408`), every `Symbol.decl_node`, cross-module derefs (semantic_analyzer/lower/comptime_eval/const_alias_prepass), the ComptimeEvaluation flat whole-store scan (`main.zig:393-394`), and 284 `store.nodes.items` deref sites across 16 non-test files (I-4 Step 2 #1, I-4 review fix #4). **Spill reduces peak only if it returns pool bytes** — dump-without-reset is pure disk I/O (the OS already pages the 256 MiB BSS for free; I-4 Step 2 point 5). **Keep in reserve** for larger future stdlibs or a strict per-module residency cap, gated on Item 4(b).

### Item 7 — Marker reduction (Option B: coarsen to the measurement set)
Delete/disable the ~15 per-node debug codes (≥98.7 % of the flood) and keep the ~30 measurement markers (track-memory, IRN/IRE/IRP, DC:k, X:, FE:, FWD:n, P0/P1/P3, D2:, INT:new, HTT:t, MT, arena-grew, Ra/D12; I-5 Step 1). (The keep-list is the measurement set; P1:t/P3:d/HTT:t are themselves per-inst volume contributors ≈165 K lines that coarsening removes — they are retained only if the future execution plan keeps those specific hooks, otherwise they coarsen too; I-5 Concern 4.) Recovers **≈26–27 s** of on-state wall (M4 28.40 s → ≈1.5–2.0 s) and ≈99 % of the 82 MB stderr, **zero memory effect** (markers allocate nothing — I-5 Step 4), and preserves every hook the roadmap's verification runs consume. Must keep `--track-memory` on its channel (it shares `pal.markerWrite`) and **fix the `AS:` gate bypass** (`ast.zig:448-450` — 41,605 lines / 312,526 B on marker-off runs; I-5 Step 2, Concern 3). **Cheapest, independent, orthogonal to the memory path — do anytime; not required for ≤16 MiB.**

### Recommended order (value/risk)
0 → 1 → 2 → 3 → 5 → 4(a) → 7 (independent) → [4(b)+6 only if live must go below ≈16 MiB]. Items 1–2 give ≈2.7–3.0 MB of live cut at the 20 B LirInst anchor (I-4 f#1); Items 3+4(a)+5 cross the pool below 16 MiB; Item 0 keeps every step measurable.

---

## 4. What cannot happen — guarantee analysis

Per option, its effect on OOM risk (Win98, 32 MB physical; compiler demand on the host ≈ `pool.peak` committed, I-4 Step 3):

| option | effect on OOM risk | statement |
|---|---|---|
| 0 tripwire | prevents silent overrun | turns an over-budget compile into a clean exit-1 diagnostic *before* the OS kills the process — the intended path (`allocator.zig:220-227`) is today unreachable because `_ = alloc` discards `max_mem` (I-4 Step 3) |
| 1/2/5 live compaction | lowers the pool floor | pool ≥ live total, so shrinking live (≈2.7–3.0 MB combined at the 20 B LirInst anchor; I-4 f#1) directly lowers the committed floor; alone it still leaves live ≈16.5–17 MiB (I-4 f#1) |
| 3 growth policy | biggest single reduction | removes the 4.0× geometric overshoot — pool 83 → ≈ live + margin without reset; without it a 16 MiB-live compiler would still commit a ~64 MiB module chain (I-2 Step 2) |
| 4 arena reclaim | removes committed-but-dead bytes | import reuse −4.3 MiB immediately; module reset makes the pool track live (and is the *only* thing that makes spill pay) (I-2 Step 3, I-4 Concern 1) |
| 6 spill | reduces peak **only after reset** | dump-without-reset changes nothing the OS must back — the pool never frees (I-4 Step 2 #5, Concern 1); with 4(b) it caps the module arena at ≈ largest module AST+LIR ≈1.6 MB + ≈1 MB + resident tables ≈0.4–0.7 MB (I-4 Step 2) |
| 7 marker reduction | none (memory) | markers allocate nothing — no OOM effect; removes 82 MB of disk/paging churn on the 32 MB host and 27 s wall (I-5 Step 4) |

**The honest guarantee:** once the compiler's committed high-water is bounded ≤16 MiB and `checkCombinedPeak` gates `max_mem`, a ≤16 MiB-pool compiler on 32 MB physical + a ≥16 MiB paging file **cannot itself be the cause of a Windows "out of memory"**. This is a bound on the compiler's *demand*, not an absolute guarantee — the OS environment (paging-file size, other processes) is outside the compiler's control (I-4 Step 3). Two further structural requirements for the guarantee to hold: (a) **`POOL_SIZE` must shrink** to track the achievable peak — the 256 MiB BSS (`allocator.zig:184-185`) is itself a latent Win98 hazard even at a 16 MiB compile (I-4 Concern 3); (b) the **memory-limit/`OOM:` messages must stay ungated** diagnostics (they already are; allocator.zig:65-73/:221-234 — I-5 Step 2).

---

## 5. Acceptance criteria for a future execution plan

A future execution plan derived from this roadmap must state these as its exit gates:

1. **Self-compile pool ≤ 16 MiB:** `track-memory: pool=…` ≤ **16,384 K** (16 MiB) on the canonical self-compile run (anchor and units per I-2; today 83,210 K = 5.08×).
2. **4 MD5 gates re-baselinable** (byte-identity; re-baseline allowed only if a future execution changes emission, per design-doc scope ruling): gol `eed963e0…`, lisp `c3c58477…`, json `089e4f04…`, mud `a1d0dd55…`. In addition: 40 `.c` self-compile output, 0 errors; matrix 21/21; corpus clean.
3. **No Windows OOM:** the bounded-demand guarantee holds — compiler committed pool ≤16 MiB on 32 MB physical + ≥16 MiB paging file; `checkCombinedPeak` gates `alloc.max_mem` (tripwire active); `POOL_SIZE` shrunk to track the achievable peak.
4. **Measurement workflow intact:** `--track-memory` and the measurement marker set survive any marker coarsening; the `AS:` gate bypass (`ast.zig:448-450`) is fixed (I-5).
5. **zig0 dialect honored:** every encoding uses only the I-3 Step 1 toolkit (plain structs, `union(enum)`, u32/u64 + shift/mask, arrays, out-of-line pools); no packed structs, bitfields, `anytype`, `@Type` (I-3).
6. **No silent regression:** ladder examples byte-equal to reference; self-compiled zig1_5 runs the example ladder correctly (established route per memory-comparison design).

---

## Out of Scope

- Performing the refactoring / compaction / spill itself (future execution plan, fed by this roadmap).
- Migration to a richer dialect (future objective; the zig0 binding constraint applies throughout).
- Re-baselining the 4 MD5 gates now, or any `sf/src` change.
- Self-compile correctness/determinism work (established elsewhere).
