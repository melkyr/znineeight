# zig1 Memory Refactor Execution — Allocation → Warnings → Migrations — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Execute the zig1 memory refactor roadmap (self-compile pool ≤ 16 MiB, never-OOM-Windows) AND make the emitted C compile warning-clean at `-O2`/`-O3` (portable to mingw/msvc6/openwatcom). Order: allocation wins → warnings → struct migrations.

**Architecture:** Phase 1 allocation strategy (items 0/3/4a — the ~58 MiB of the pool gap, zero code migration); Phase 2 the `-O2`/`-O3` warning classes (zero-length array, maybe-uninit, shift-parens, benign tail → 0 warnings); Phase 3 struct migrations (items 1/2/5 — AstNode/LirInst/side-arrays, the ~3.6 MB live tail); Phase 4 markers + spill-reserve + GATE. Every emission-affecting task guards runtime via a golden sample captured from the reference zig1.

**Tech Stack:** Zig (sf/src), C89 (emitted code), gcc -m32 (build + `-O2`/`-O3` portability gate), bash.

## Global Constraints

- **Golden-sample runtime protocol (operator-mandated):** at the start of every emission-affecting F task, capture the golden sample with the reference zig1 — its `--dump-c89` emission + compiled/run stdout+rc for the 4 gates (`examples/z98/{game_of_life,lisp_interpreter_curr,json_parser,mud_server}/main.zig`) and the runtime fixture set (`emission_assoc_chain_xmod`, `tco_return_try`, `tco_defer`, `tco_factorial`, `fn_ptr_struct_field`, `quicksort`, `func_ptr_return`, `hello`, `emission_lower_crash_xmod`) — into `/tmp/golden_<TASK>/` (gitignored). Runtime MUST match this golden sample; byte-identity may be re-baselined with evidence, never guessed.
- **Warning-clean target:** `-Wall -Wextra -O3` on the emitted compiler C AND `zig1_5`'s emitted C → **0 warnings, 0 errors**. Rebuild check: `gcc -m32 -std=c89 -O3 -Wall -Wextra -Wno-long-long -Wno-pointer-sign -Wno-implicit-function-declaration -I <repo>/sf/src/include`.
- **4 MD5 byte-identity gates** (gol `eed963e0640a073ed4eebb292f136e05`, lisp `c3c5847798e4553b2e34950e085bb6c6` repo-root CWD, json `089e4f046464ce3882aa2b2c4e585013`, mud `a1d0dd55aada9c3fd904ae33f54de32e`): keep byte-identical OR re-baseline with golden-sample runtime evidence (operator-ruled; emitter fixes W-1/W-2/W-4 are emission-affecting by design).
- **Hard target frame:** self-compile pool ≤ 16,384 K (`pool=` from `--track-memory --markers`); never OOM a 32 MB physical P3/P4 Win98 host. zig0 dialect binding (no packed/bitfield/anytype/@Type); custom u32/u64+shift encoding allowed.
- Compiler under test `/tmp/fx_subfolder/zig1`; rebuild `timeout 900 bash sf/scripts/build_release.sh` (repo root, gate `=== [release] Done ===`, reinstall std lib after wipe); self-compile `timeout 900 bash scripts/self_compile/build_zig1_5.sh`. `timeout 120` on all compiler/binary invocations.
- Z98 dialect for any new/changed `.zig` (no anytype/@Type, `@intCast`, switch needs `else`, no method syntax, no pointer captures).
- Editing discipline: `edit`/`fastedit` only; re-read before each edit; bottom-to-top; never touch `sf/build/out_release/` (WEDGED).
- Ledger: append one line per task to `.superpowers/sdd/progress.md`. Memory: `mnemoria --path .opencode/memory add --agent memrefactor-session --type <discovery|decision|bugfix|problem|pattern>`.
- Reports: `.superpowers/sdd/task-<N>-report.md` (gitignored; shared `task-MEMREFACTOR-report.md` recommended). WARNING: `task-1-report.md` is TRACKED — never reuse. `task-brief` script only matches numeric "Task N" — prefer self-contained dispatches.
- Pre-existing dirty files never staged: `docs/superpowers/plans/2026-08-26-assoc-misparse-pendingscope-plan.md`, `mnemoria/*`, untracked `build/`.
- Roadmap + evidence sources: `docs/superpowers/specs/2026-08-26-zig1-memory-refactor-roadmap.md` (items 0-7, commit ff5b1d7c/a4171677) and `.superpowers/sdd/task-ROADMAP-report.md` (I-1..I-5).

---

### Task M0: Budget tripwire (roadmap item 0)

**Files:**
- Modify: `sf/src/allocator.zig` (`checkCombinedPeak` :216-228), `sf/src/main.zig` (`--max-mem` plumbing :142/:914-917)
- Commit: `fix: enforce max_mem budget in checkCombinedPeak (16MiB tripwire)`

**Interfaces:**
- Consumes: I-2 finding (checkCombinedPeak gates POOL_SIZE, not max_mem).
- Produces: the 16 MiB budget is enforceable + measurable; `--max-mem` works.

- [ ] **Step 1: Golden baseline (emission-affecting? NO — allocator internal, but capture anyway)**

Capture golden runtime for the fixture set per the protocol (defensive; cheap).

- [ ] **Step 2: Fix the gate**

In `allocator.zig:216-228` `checkCombinedPeak`: replace the `_ = alloc;` that discards `max_mem`; gate `pool_kb` against `alloc.max_mem` when set (else POOL_SIZE). Wire `--max-mem` (main.zig:142/:914-917) so the value reaches `CompilerAlloc.max_mem`.

- [ ] **Step 3: Verify the tripwire fires**

Canary: `zig1 --dump-c89 <fixture> --max-mem=16` must abort with the out-of-memory diagnostic (`ICE: out of memory`, allocator.zig:28) since pool.peak 83 MiB > 16 MiB. `--max-mem=256` must pass. This proves enforceability (M3 will bring the real pool under budget).

- [ ] **Step 4: Gates**

Rebuild zig1; self-compile 0 errors; 4 MD5 byte-identical (allocator-internal); golden runtime matches. Commit verbatim. Report + ledger + mnemoria (bugfix).

---

### Task M3: Segment-growth policy + exact-fit final segment (roadmap item 3)

**Files:**
- Modify: `sf/src/allocator.zig` (`growableSandGrow` :108-130, `sandAlloc` :52, growth policy)
- Commit: `fix: cap segment growth + exact-fit final segment (kill 4x doubling overshoot)`

**Interfaces:**
- Consumes: I-2 finding (module chain 65,532 K = 13 grows 4 K→32 MiB for 16,383 K live = 4.0× overshoot).
- Produces: pool.peak drops toward ~live+margin (module chain 64 MiB → ~16-32 MiB); expected pool from 83,210 K to ~40-50 MiB.

- [ ] **Step 1: Golden baseline (not emission-affecting — allocator only; skip per protocol, verify 4 MD5)**

- [ ] **Step 2: Fix the growth policy**

Read `growableSandGrow`/`sandAlloc`. Change the geometric doubling so the final segment is exact-fit to the requested size (or a capped curve) instead of always doubling to the next power-of-two — the 13th grow to 32 MiB for 16.4 MiB live is the waste. Preserve `sandReset` reuse semantics. Z98-clean.

- [ ] **Step 3: Verify pool drop**

Rebuild zig1 + zig1_5. `--track-memory --markers` self-compile: `pool=` must drop substantially from 83,210 K (measure exact). 4 MD5 byte-identical (allocator-internal); self-compile 0 errors; golden runtime matches.

- [ ] **Step 4: Commit + report + ledger + memory**

Commit verbatim. Report pool before/after + chain-sum evidence. Ledger + mnemoria (bugfix/pattern).

---

### Task M4: Per-`@import` arena reuse (roadmap item 4a)

**Files:**
- Modify: `sf/src/parser.zig` (per-`@import` arena creation :672-676), possibly `sf/src/import_resolver.zig`
- Commit: `fix: reuse scratch arena across @imports (reclaim 4.2MiB dead chains)`

**Interfaces:**
- Consumes: I-2 finding (parser.zig:672-676 creates ~320 fresh chains, 4.2 MiB never reclaimed).
- Produces: pool.peak drops ≈4.2 MiB (cumulative).

- [ ] **Step 1: Golden baseline (not emission-affecting — verify 4 MD5 only)**

- [ ] **Step 2: Reuse the per-@import arena**

Read parser.zig:672-676 + import_resolver.zig:132/135. Replace the per-`@import` fresh scratch chain with a single reused scratch arena (reset between modules, preserving pointer-stability for anything that must outlive the parse). Z98-clean.

- [ ] **Step 3: Verify pool drop + correctness**

Rebuild; `--track-memory` self-compile `pool=` drops ≈4.2 MiB. 4 MD5 byte-identical; self-compile 0 errors; golden runtime matches; matrix 21/21.

- [ ] **Step 4: Commit + report + ledger + memory**

Commit verbatim. Report pool delta. Ledger + mnemoria (bugfix/pattern).

---

### Task W-I: Investigate the 3 maybe-uninitialized sites (read-only)

**Files:**
- Report: `.superpowers/sdd/task-MEMREFACTOR-report.md` (append)

**Interfaces:**
- Consumes: `-O2`/`-O3` warnings (`lower.zig:1553/1573` payload_tid, `parser.zig:1100` member_buf).
- Produces: verdict per site — real uninit-read vs gcc false-positive — with a canary test; feeds W-3.

- [ ] **Step 1: Analyze `lower.zig:1553` + `:1573` (`payload_tid` / `payload_tid_1`)**

`var payload_tid: u32 = undefined;` then `for (fe in fields) { if (fe.type_id != TYPE_VOID) { payload_tid = fe.type_id; break; } }` then `pre_cap_type = payload_tid;` / `nextTemp(self, payload_tid)`. Determine if a path exists where the loop finds no non-void field (empty fn-type field list, all-void payloads). If unreachable, prove why; if reachable, classify real.

- [ ] **Step 2: Analyze `parser.zig:1100` (`member_buf`)**

`var member_buf: [*]u32 = undefined;` written only by `parserPushU32`, read at :1115 guarded by `if (member_count > 0)`. Confirm the guard makes it safe (false-positive) or find a hole.

- [ ] **Step 3: Canary + verdict**

Write a minimal `.zig` probe if needed to exercise the suspected uninit path; run under reference zig1 + `-fsanitize=address` zig1_5 to observe. Report: per-site verdict, gcc-analysis basis, evidence. Ledger + mnemoria (discovery/problem).

---

### Task W-1: Zero-length array emission fix (emitter)

**Files:**
- Modify: `sf/src/c89_emit.zig` (empty-slice emission producing `unsigned int dummy[0]`)
- Commit: `fix: emit C90-valid empty slices (no zero-length arrays, msvc6/openwatcom-safe)`

**Interfaces:**
- Consumes: `-O2`/`-O3` warning (source_manager.c:285/290 `unsigned int dummy[0]`); golden sample.
- Produces: no `[0]` array declarations in emitted C; C90-clean.

- [ ] **Step 1: Golden baseline (EMISSION-AFFECTING — capture per protocol)**

Capture `/tmp/golden_W1/` = reference zig1 emission + run outputs for the 4 gates + fixture set.

- [ ] **Step 2: Pin the emission path**

Find in c89_emit.zig where an empty u32 slice (`&dummy[0]`, `0-0`) is emitted (grep the emitted source_manager.c:285 shape back to its emitter site).

- [ ] **Step 3: Fix the emission**

Emit a C90-valid empty slice: a shared static `[1]` dummy (or pass NULL for len-0). No `[0]` arrays anywhere in the emitted C. Z98-clean.

- [ ] **Step 4: Verify**

Rebuild zig1 + zig1_5. Emitted compiler C + zig1_5 emitted C: `grep -E '[0-9a-zA-Z_]+\[0\];'` = 0 real decls. `-Wall -Wextra -O3` build 0 errors, zero `-Warray-bounds` of this class. **Runtime must match golden sample byte-for-byte** (4 MD5s may be re-baselined — record diff + runtime equality as the re-baseline evidence). Self-compile 0 errors.

- [ ] **Step 5: Commit + report + ledger + memory**

Commit verbatim. Report golden-diff + runtime-equality evidence. Ledger + mnemoria (bugfix).

---

### Task W-2: Shift-parens emission fix (emitter)

**Files:**
- Modify: `sf/src/c89_emit.zig` (binary-shift emission of a compound shift amount)
- Commit: `fix: parenthesize shift amount in emitted C (no -Wparentheses)`

**Interfaces:**
- Consumes: `-O2`/`-O3` warning (comptime_eval.c:754/878 `1ULL << (u64)wb - 1U`).
- Produces: emitted shift amounts parenthesized; semantics unchanged.

- [ ] **Step 1: Golden baseline (EMISSION-AFFECTING — capture per protocol)**

Capture `/tmp/golden_W2/`.

- [ ] **Step 2: Fix the emission**

In c89_emit.zig, when emitting `<<`/`>>` with a compound (non-atomic) shift amount, wrap the amount in parens: `1ULL << ((u64)wb - 1U)`. Check the same for the shifted value operand.

- [ ] **Step 3: Verify**

Rebuild. `-Wall -Wextra -O3` on emitted compiler C + zig1_5 emitted C: 0 `-Wparentheses` for shift sites. **Runtime matches golden sample** (semantics unchanged — byte-identity expected to hold; re-baseline only if emission changed). Self-compile 0 errors.

- [ ] **Step 4: Commit + report + ledger + memory**

Commit verbatim. Report. Ledger + mnemoria (bugfix).

---

### Task W-3: Fix source `undefined` reads (after W-I)

**Files:**
- Modify: the `sf/src` sites W-I found real (`lower.zig:1553/:1573`, `parser.zig:1100`)
- Commit: `fix: eliminate uninitialized reads flagged by gcc -O2/-O3`

**Interfaces:**
- Consumes: W-I verdicts.
- Produces: no `-Wmaybe-uninitialized` in emitted C.

- [ ] **Step 1: Golden baseline (EMISSION-AFFECTING — capture per protocol)**

Capture `/tmp/golden_W3/`.

- [ ] **Step 2: Apply the fixes**

For each real site: initialize the variable (or restructure the loop to guarantee a definition) in the Zig source, matching the surrounding code's style (e.g., `var payload_tid: u32 = type_mod.TYPE_UNDEFINED;` or an early `else`). Z98-clean. Do NOT touch false-positive sites.

- [ ] **Step 3: Verify**

Rebuild. `-Wall -Wextra -O3` on emitted compiler C: 0 `-Wmaybe-uninitialized`. Runtime matches golden; 4 MD5 keep-or-re-baseline with evidence; self-compile 0 errors.

- [ ] **Step 4: Commit + report + ledger + memory**

Commit verbatim. Report per-site fix + verdict. Ledger + mnemoria (bugfix).

---

### Task W-4: Benign-tail emitter cleanup → warning-clean build

**Files:**
- Modify: `sf/src/c89_emit.zig` (dead-store temps, unused labels, duplicate const, C90 constants, string-init, unused statics)
- Commit: `fix: warning-clean C89 emission at -Wall -Wextra -O3`

**Interfaces:**
- Consumes: the benign-warning classes (unused `_`/`__1` temps, `__loop_0_end` labels, unused params/statics, duplicate `const`, ISO C90 decimal constants, string-literal pointer init).
- Produces: **0 warnings** at `-Wall -Wextra -O3` on both the compiler's emitted C and `zig1_5`'s emitted C.

- [ ] **Step 1: Golden baseline (EMISSION-AFFECTING — capture per protocol)**

Capture `/tmp/golden_W4/`.

- [ ] **Step 2: Fix the dead-store discard temps**

`unsigned int _; _ = expr;` (set-but-not-used): when a Zig expression's result is discarded (the `_`/`__N` temps), the emitter should not emit the temp + store (or emit `(void)expr;`). Applies to the ~15-20 `set but not used` sites (c89_emit.c, lower.c, main.c, lexer.c, parser.c, etc.).

- [ ] **Step 3: Fix unused labels**

`__loop_N_end:` when unreachable (the common `while`-end label): emit only when the loop has an exit that uses it.

- [ ] **Step 4: Fix the remaining classes**

- duplicate `const` (ast.c:32, pal.c:32): emit `const` once.
- ISO C90 decimal constants (`4294967295`, `2166136261`, `18446744073709551615`): append `U`/`ULL` suffixes per constant size.
- string-literal pointer init (`const unsigned char (*p)[N] = "…"`): emit a compatible cast or `char`-typed initializer.
- unused `static` functions (e.g. `getCheckedCastFnName`, `tstEdgesFill`, `initArray`, `unrAppend`, `appendBucket`, `pal_strlen`/`pal_memcpy`): emit `static` only when referenced, or drop when dead in all emission paths.
- unused parameters (e.g. `alignment` in sandTryReallocInPlace, `alloc` in computeSharedSet): emit `(void)param;` or omit.

- [ ] **Step 5: Verify warning-clean + runtime**

Rebuild zig1 + zig1_5. `gcc -m32 -std=c89 -O3 -Wall -Wextra …` on emitted compiler C AND on `zig1_5`'s emitted C: **0 warnings, 0 errors** (allow only the 3 `-Wno-*` that are structural: long-long, pointer-sign, implicit-function-declaration). Runtime matches golden sample; 4 MD5 keep-or-re-baseline with evidence; self-compile 0 errors.

- [ ] **Step 6: Commit + report + ledger + memory**

Commit verbatim. Report warning-count before/after (128-129 → 0) + per-class evidence. Ledger + mnemoria (pattern).

---

### Task M1: AstNode 32→24 B (roadmap item 1)

**Files:**
- Modify: `sf/src/ast.zig` (AstNode layout :116-128; payload u64→u32; child_2 → side table) + all readers/writers (75 `astStoreGetExtraChildren` reader sites across 12 files; 16 `astStoreAddExtraChildren` writer sites in parser.zig; 43 child_2 sites)
- Commit: `refactor: AstNode 32->24B (payload u32 + child_2 side table)`

**Interfaces:**
- Consumes: I-1/I-3 (layout + writer/reader split; parser.zig:1447-1448 sole direct packed-range reader).
- Produces: module-arena live drops ≈1.44 MB; emitted AstNode = 24 B.

- [ ] **Step 1: Golden baseline (EMISSION-AFFECTING — the compiler's own C changes; user-program emission should not)**

Capture `/tmp/golden_M1/` (4 gates + fixture set run outputs).

- [ ] **Step 2: Design the 24 B layout**

Per I-1: `kind u8, flags u8, pad2, span_len u32, span_start u32, child_0 u32, child_1 u32, child_2 u32` (drop payload u64→ reuse a spare u32 or fold into child_2; keep `extra_children` via a parallel array/side table — see ast.zig:433-454 pool pattern). Preserve the `start<<32|count` range semantics via a side-table range. Confirm every `payload` read site (u32 low-word consumers) is compatible.

- [ ] **Step 3: Apply the migration**

ast.zig new layout + accessors; update the 16 writers + 75 readers + 43 child_2 sites. parser.zig:1447-1448 packed-range reader updated to the side table. Z98-clean; byte-order/offsets per the emitted header (update `ZZZ_ASTNODE_32B` marker to reflect the new size).

- [ ] **Step 4: Verify**

Rebuild zig1 + zig1_5. Emitted AstNode sizeof = 24 B. `--track-memory` self-compile `mod=` drops ≈1.44 MB (16,383 K → ~14,900 K). Self-compile 0 errors. **User-program emission: 4 MD5 gates byte-identical** (AstNode is internal; the 4 gates' C must not change) + golden runtime matches. Matrix 21/21.

- [ ] **Step 5: Commit + report + ledger + memory**

Commit verbatim. Report sizeof + mod-arena delta. Ledger + mnemoria (decision/refactor).

---

### Task M2: LirInst 32→20 B (roadmap item 2)

**Files:**
- Modify: `sf/src/lir.zig` (union(enum) :22-102 reshape; wide variants tail_call/call_direct 28 B → side table) + all `switch(inst)` consumers (c89_emit.zig:2780/4324/6308, lower.zig:5699-5860, construction sites lower.zig:2934/5136/2523/1652/1668) + `lirFunctionRelocateToModule` (lir.zig:373-470)
- Commit: `refactor: LirInst 32->20B (side-table wide operands)`

**Interfaces:**
- Consumes: I-1/I-3 (20 B natural bound — union payload ≤12 B under the 4 B tag; side-table the 6-8-operand variants).
- Produces: module-arena live drops ≈1.3-1.5 MB; emitted LirInst = 20 B.

- [ ] **Step 1: Golden baseline (EMISSION-AFFECTING — capture per protocol)**

Capture `/tmp/golden_M2/`.

- [ ] **Step 2: Design the 20 B layout**

Reduce every variant's payload ≤12 B; move the wide operands (callee, module_id, args, return_type, is_indirect, is_extern for call/tail_call) into a side table (per-fn, relocated with `lirFunctionRelocateToModule` — see I-3 Concern 2 re pointer stability). Keep the `switch(inst)` dispatch working via the 4 B tag.

- [ ] **Step 3: Apply the migration**

lir.zig new layout + side-table append/read helpers; update all constructors + consumers. Z98-clean.

- [ ] **Step 4: Verify**

Rebuild. Emitted LirInst sizeof = 20 B. `--track-memory` self-compile `mod=` drops ≈1.3-1.5 MB. Self-compile 0 errors. 4 MD5 gates byte-identical + golden runtime matches. TCO fixtures (tco_return_try/tco_defer/tco_factorial) still byte-equal to golden.

- [ ] **Step 5: Commit + report + ledger + memory**

Commit verbatim. Report sizeof + mod delta. Ledger + mnemoria (decision/refactor).

---

### Task M5: AST side arrays + token value union (roadmap item 5)

**Files:**
- Modify: `sf/src/ast.zig` (side arrays for rarely-used node fields), `sf/src/token.zig` (TokenValue union → plain `u32` value :115-123)
- Commit: `refactor: AST side arrays + Token 20->16B value union`

**Interfaces:**
- Consumes: I-1/I-3 (Token 20 B actual; union-forced 8-align; plain u32 not packed); M1 (side-array machinery reused).
- Produces: live drops ≈0.75-0.9 MB; Token = 16 B.

- [ ] **Step 1: Golden baseline (EMISSION-AFFECTING — capture per protocol)**

Capture `/tmp/golden_M5/`.

- [ ] **Step 2: Token value union → plain u32**

token.zig: replace the `union { u64; f64; u32 } value` with a plain `u32` value (the `u64`/`f64` token payloads are not needed at runtime token scope — verify every `value` read site first). 20 → 16 B. NOT packed (zig0 can't).

- [ ] **Step 3: AST side arrays**

Move the rarely-used node fields (child_2 / extra payloads) out of AstNode into parallel arrays via the ast.zig:433-454 pool pattern, reusing M1's side-table machinery. Z98-clean.

- [ ] **Step 4: Verify**

Rebuild. Emitted Token = 16 B; AstNode unchanged from M1. `--track-memory` self-compile `mod=` drops ≈0.75-0.9 MB. Self-compile 0 errors. 4 MD5 gates byte-identical + golden runtime matches. **If live now crosses ≤16 MiB (optimistic edge), note it; the pessimistic edge needs M6.**

- [ ] **Step 5: Commit + report + ledger + memory**

Commit verbatim. Report sizeof + live delta + whether ≤16 MiB is crossed. Ledger + mnemoria (decision/refactor).

---

### Task M7: Marker coarsening (roadmap item 7)

**Files:**
- Modify: `sf/src/pal.zig` (markerWrite :130-134), marker call sites across `sf/src` (~1,415 string sites → ~30 measurement markers)
- Commit: `perf: coarsen markers to ~30 measurement codes (recover ~27s markers wall)`

**Interfaces:**
- Consumes: I-5 (1,728 sites; 1,289 strings; 82 MB / 27 s wall; keep ~30 measurement set incl. track-memory; fix the `AS:` gate bypass ast.zig:448-450).
- Produces: `--markers` self-compile wall ≈1-2 s (from ~27 s); stderr volume ≈1.28%; zero memory change.

- [ ] **Step 1: Golden baseline (NOT stdout-affecting — verify 4 MD5 only; markers are stderr)**

- [ ] **Step 2: Keep the measurement set**

Retain the ~30 measurement markers (incl. `track-memory`, IRN/IRE, arena-growth, INT:new, DC:k, X:, FE:, FWD:n, P0:lc, D2:, MT, Ra). Remove the per-node debug flood (INT/A4/STX/VFLOW/GBL/STB/D7/COE + the `_`/`__1` destructure traces) — either gate them off entirely or convert to compile-time-disabled.

- [ ] **Step 3: Fix the `AS:` gate bypass**

ast.zig:448-450 fires 41,605× via `pal.stderr_write` even without `--markers` — gate it.

- [ ] **Step 4: Verify**

Rebuild. `--markers` self-compile wall drops (measure; target ~1-2 s); stderr lines drop to ≈ measurement-set count. 4 MD5 gates byte-identical (stdout unchanged); `--track-memory` still emits the `pool=` line; self-compile 0 errors; golden runtime matches.

- [ ] **Step 5: Commit + report + ledger + memory**

Commit verbatim. Report wall/stderr before/after. Ledger + mnemoria (pattern).

---

### Task M6: I/O spill (roadmap item 6 — RESERVE, gated)

**Files:**
- Only if pool still > 16,384 K after M1+M2+M5. Otherwise skip (documented).
- Modify: per I-4 (per-module LIR spill clean; AST spill blocked on index-space surgery)
- Commit: `perf: spill per-module LIR to disk (reserve)`

**Interfaces:**
- Consumes: I-4 (spill only pays after arena reset; per-module LIR self-contained).
- Produces: pool crosses ≤16,384 K if the compacted live still exceeds it.

- [ ] **Step 1: Decide (gate)**

Measure `pool=` after M5. If ≤16,384 K: mark task SKIPPED with the measurement as evidence (report + ledger). If >: proceed.

- [ ] **Step 2: Implement per-module LIR spill**

Per I-4: spill per-module LIR to disk before emission, reload per module; requires the I-2 reset path. Report STOP if AST-side spill is required (index-space surgery) — present to operator.

- [ ] **Step 3: Verify + commit + report + ledger + memory**

Pool ≤16,384 K; golden runtime matches; 4 MD5 keep-or-re-baseline. Commit verbatim (or "docs: spill reserve not required").

---

### Task GATE: Full sweep + reconciliation

**Files:**
- Modify: `repro/mi_matrix/EXPECTED_FAIL.md`, `docs/sf/QUICK_REF.md`, `docs/superpowers/specs/2026-08-26-zig1-memory-refactor-roadmap.md` (status)
- Commit: `docs: memory refactor execution GATE + reconciliation`

**Interfaces:**
- Consumes: all prior tasks; golden samples; roadmap + report.
- Produces: measured GATE evidence; roadmap status updated; acceptance confirmed.

- [ ] **Step 1: Full gate battery**

4 MD5 (keep-or-re-baseline with golden evidence); matrix 21/21; corpus 329 + examples z98 21 runtime sweep vs **golden sample** (RUNTIME must match everywhere; byte-identity diffs documented); self-compile 0 errors; `--track-memory` self-compile `pool=` ≤ 16,384 K (or documented spill-reserve).

- [ ] **Step 2: Warning-clean confirmation**

`-Wall -Wextra -O3` on emitted compiler C + zig1_5 emitted C: 0 warnings, 0 errors. Report counts.

- [ ] **Step 3: Reconcile docs**

EXPECTED_FAIL.md + QUICK_REF.md: new baseline paragraph (memory refactor GATE, newest-first); roadmap doc: mark items 0-7 DONE/skipped + measured deltas. Historical sections as snapshots (supersede, don't rewrite).

- [ ] **Step 4: Report + ledger + memory**

Report all gate evidence + reconciliation. Ledger + mnemoria (success/pattern).
