# zig1 Memory Refactor Execution — Allocation → Warnings → Migrations — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Execute the zig1 memory refactor roadmap (self-compile pool ≤ 16 MiB, never-OOM-Windows) AND make the emitted C compile warning-clean at `-O2`/`-O3` (portable to mingw/msvc6/openwatcom). Order: allocation wins → warnings → struct migrations.

**Architecture:** Phase 1 allocation strategy (items 0/3/4a — the ~58 MiB of the pool gap, zero code migration); Phase 2 the `-O2`/`-O3` warning classes (zero-length array, maybe-uninit, shift-parens, benign tail → 0 warnings); Phase 3 struct migrations (items 1/2/5 — AstNode/LirInst/side-arrays, the ~3.6 MB live tail); Phase 4 markers + spill-reserve + GATE. Every emission-affecting task guards runtime via a golden sample captured from the reference zig1.

**AMENDMENT 5 (operator-ruled 2026-08-26):** the W-1..W-4 series landed on the **bootstrap** (the reference `/tmp/fx_subfolder/*.c` is emitted by `zig0`/`codegen.cpp`), but the TRUE objective is the **self-hosted** compiler — `zig1_5`'s own emitted C (`c89_emit.zig` → `/tmp/zig1_5/gen/*.c`). A new **W2 series** (W2-I investigation + W2-1..4 fixes) is added, scoped to **`sf/src/c89_emit.zig` ONLY** (do NOT touch the bootstrap), to reach **0 warnings on `gen/*.c`** at `-Wall -Wextra -O3`. W-4 as committed (`a3fd9a2b`) covers the reference (bootstrapped) build only; its c89_emit.zig part is superseded by the W2 series. The `undefined`-init warnings are fixed at the **emitter** (emit `= 0` for `undefined` locals — safe, reads of undefined are UB) so users never have to initialize defensively. The 4 MD5 gates WILL be re-baselined by the W2 fixes (c89_emit.zig changes zig1's emission of user programs) with golden runtime-equality as the evidence (operator pre-authorized). **AMENDMENT 5 status (2026-08-26, W2 series COMPLETE):** self-hosted emission warning-clean, 17,788 → 0 (W2-1 `c45f7333`, W2-2 `582cab3b`, W2-3 `3c668094`, W2-4 `39982678`+`4a5cf580`). 4 MD5 gates re-baselined to gol `b335d894`, lisp `93946438`, json `76056b97`, mud `4591fef0` (golden runtime-equality evidence).

**AMENDMENT 6 (operator-ruled 2026-08-26, migration discipline + post-M6 evaluation):**
1. **Widening provenance (verified — do NOT shrink indices).** The current u32/u64 widths are deliberate overflow fixes, NOT bloat: `50ebbf82` (AstNode `payload u32→u64` + `FnProto.params_start u16→u32` — extra-children start index overflowed u16; self-compile has ~69,026 extra-children > 65,535), `378c71fa` (type-registry index starts u16→u32), `7ab3b519` (`span_len u16→u32`). M1/M2/M5 reclaim **waste** (the 8-byte u64 payload holding a u32 index; `child_2` for ~10/112 kinds) via **side tables** — every index field stays **u32**, never shrunk back to u16.
2. **A first, B gated after M6 (operator m0694).** Execute M1/M2/M5 as the quick-win (different-indices) versions only, to validate no issues. The "clever" 16-B AstNode compaction (span out-of-line + child_2 side table + payload u32) is NOT in M1/M5 — it becomes a new read-only **I-COMPACT task after M6**, with a go/no-go against the measured pool after A+M6.
3. **Padding caution (operator m0699).** The AstNode 2-byte padding may be structural (zig0/C89 alignment quirks). **Padding-squeezing is the LAST step** — never force-reorder fields or squeeze padding to hit a size target; that is how a mess starts. M1/M2/M5 must not depend on padding elimination for their size target; report the actual emitted `sizeof` after each migration.

**AMENDMENT 9 (operator-ruled 2026-08-26, 4(b) decomposition — the reset is REQUIRED, not reserve):**
The ≤16 MiB POOL target is unreachable without a module-arena reset: `pool=` is the monotonic CUMULATIVE bump (never returns bytes), so struct compaction lowers the LIVE floor but not the cumulative pool — indeed M1+M2 raised pool `45,407K → 50,501K` (side tables are extra cumulative allocations). The single clean reset point is the **Lowering→Emission boundary**: the module arena holds (a) AST store (built `phase_ImportResolution`, read by every phase through lowering), (b) resolution tables (`resolved_types`/`comptime_values`, keyed by node_idx), (c) LIR (relocated to module by `lirFunctionRelocateToModule`). After `phase_LIRLowering`, (a) and (b) are dead — `c89_emit` reads LIR only (its `.store` is the LIR instruction, not the AST). **Decomposition (added before M6):** **I-4B** (read-only — measure the per-phase module-arena growth + the reset ceiling), **4(b)-1** (split LIR into a dedicated `lir_arena` — mechanical, byte-neutral), **4(b)-2** (reset the module arena after lowering — AST + resolution tables dead; makes pool track live). **M6 spill is re-scoped to be gated on 4(b)-2** (spill only pays after a reset returns bytes).

**AMENDMENT 10 (operator-ruled 2026-08-26, streaming-AST evaluation — the complete path):**
I-4B showed 4(b)+M6 cannot reach ≤16,384 K (post-M6 live ≈ 16,727 KiB ≈ 16.3 MiB, still ~343 KiB over). The operator's direction (m0805/m0810) corrects the "AST spill blocked" framing: **per-module** dumping is blocked (interleaved flat node array + node_idx-keyed `resolved_types`/`comptime_values`/`Symbol.decl_node` + ComptimeEvaluation full-store scan), but **whole-AST streaming (write-through, always-on-disk)** is viable because the AST is **write-once** (only the parser appends; 281 read sites, 0 writes) — the ideal property for paging (no dirty write-back, no COW). A new read-only **I-STREAM task** (added before 4(b)-1) designs the disk-backed node + resolution-table storage, estimates the pool ceiling, and issues the **complete-path decision**: (a) **STREAM** — new execution task list (node blocks → fault-in accessor → resolution-table streaming → comptime streaming sweep) that caps `pool.peak` (never fully materialized), vs (b) **INCREMENTAL** — keep 4(b)-1 → 4(b)-2 → M6 → I-COMPACT → GATE (lands ~16.3-16.7 MiB live / ~48 MiB pool, misses 16,384 K). I-STREAM's decision informs (and may supersede) 4(b)-1/4(b)-2/M6.

**AMENDMENT 11 (operator-ruled 2026-08-26, corrected floor + streaming task decomposition):**
The operator's "stage done → query only" probe (m0834) corrected the floor. Verified: `path_to_id`/`content_to_id` hash maps are **WRITE-ONCE in import resolution** (`u32ToU32MapPut` only at module_registry.zig:315/345/361/367/370/374/377), then query-only → spilleable. The interner (`string_interner.zig`) is NOT stage-done — `stringInternerIntern` has **196 call sites across all phases** (parse interns identifiers, lowering interns mangled names, emission interns type names) — but its `entries` are append-once+immutable (only `.next` rehashed by `stringInternerGrowBuckets`) and its `text` bytes are append-only (the ~4 MB bulk); it is READ constantly during emission (`stringInternerGet` on every name write). **Corrected floor:** ~38 MB is "stage-done → query only" (AST 9.9 + resolution tables 11 + LIR 10.4 + token array 6.6 + perm hash maps); the truly stay-resident core = interner + type_db + live working set ≈ 7–9 MB (NOT the earlier "perm ~6 MB irreducible" claim). **4(b)-1/4(b)-2 are SUPERSEDED** (streaming caps the bump better than a reset; see the SUPERSEDED notes on those tasks). A new **S-series** replaces M6, ordered **lesser → higher risk**, each item an I (design/census, read-only) + F (implement) pair with a per-step gate (4 MD5 byte-identical-or-re-baselined + golden 9/9 + self-compile clean + `pool=` measure) and a decision outcome toward ≤16,384 K.

**Tech Stack:** Zig (sf/src), C89 (emitted code), gcc -m32 (build + `-O2`/`-O3` portability gate), bash.

## Global Constraints

- **Golden-sample runtime protocol (operator-mandated):** at the start of every emission-affecting F task, capture the golden sample with the reference zig1 — its `--dump-c89` emission + compiled/run stdout+rc for the 4 gates (`examples/z98/{game_of_life,lisp_interpreter_curr,json_parser,mud_server}/main.zig`) and the runtime fixture set (`emission_assoc_chain_xmod`, `tco_return_try`, `tco_defer`, `tco_factorial`, `fn_ptr_struct_field`, `quicksort`, `func_ptr_return`, `hello`, `emission_lower_crash_xmod`) — into `/tmp/golden_<TASK>/` (gitignored). Runtime MUST match this golden sample; byte-identity may be re-baselined with evidence, never guessed.
- **Warning-clean target:** `-Wall -Wextra -O3` → **0 warnings, 0 errors** on BOTH the reference build's C (`/tmp/fx_subfolder/*.c`, W-4, done `a3fd9a2b`) AND the self-compiled `gen/*.c` (W2 series). Rebuild check: `gcc -m32 -std=c89 -O3 -Wall -Wextra -Wno-long-long -Wno-pointer-sign -Wno-implicit-function-declaration -I <repo>/sf/src/include`.
- **4 MD5 byte-identity gates** (CURRENT post-W2 re-baseline values: gol `b335d894`, lisp `93946438`, json `76056b97`, mud `4591fef0` — full hashes in task-MEMREFACTOR-report.md): keep byte-identical OR re-baseline with golden-sample runtime evidence (operator-ruled; emitter/struct changes are emission-affecting by design).
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

### Task W-4: Benign-tail emitter cleanup → warning-clean build (REFERENCE build)

> **AMENDMENT 5 scope note:** as executed, this task covers the **reference (bootstrap-emitted) build** only — the plan's gate "0 warnings on `zig1_5`'s emitted C" was met only for `/tmp/fx_subfolder/*.c` (committed `a3fd9a2b`, via `codegen.cpp`/`cbackend.cpp`). The `c89_emit.zig` (self-compile, `gen/*.c`) warning-clean work is the **W2 series** below. The reference build must REMAIN 0-warning at `-Wall -Wextra -O3`.

**Files:**
- Modify: `src/bootstrap/codegen.cpp` (+ `codegen.hpp`/`cbackend.cpp` as needed), `sf/src/parser.zig` (1-line `member_buf` defensive init per operator ruling)
- Commit: `fix: warning-clean C89 emission at -Wall -Wextra -O3`

**Interfaces:**
- Consumes: the benign-warning classes (unused `_`/`__1` temps, `__loop_0_end` labels, unused params/statics, duplicate `const`, ISO C90 decimal constants, string-literal pointer init) as they appear in the reference `/tmp/fx_subfolder/*.c`.
- Produces: **0 warnings** at `-Wall -Wextra -O3` on the reference build's emitted C. (Self-compile `gen/*.c` 0-warning is the W2 series' deliverable.)

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

### Task W2-I: Self-compile warning census + fix mapping (read-only)

> **AMENDMENT 5:** this is the TRUE objective — warning-clean for the SELF-HOSTED compiler's emitted C (`zig1_5` → `/tmp/zig1_5/gen/*.c`, emitted by `c89_emit.zig`).

**Files:**
- Report: `.superpowers/sdd/task-MEMREFACTOR-report.md` (append)

**Interfaces:**
- Consumes: `-Wall -Wextra -O3` measurement of `/tmp/zig1_5/gen/*.c` at HEAD `a3fd9a2b` (~17,788 warnings: unused-temp-decls ~13,621; sign-compare ~265; int-conversion ~98; uninitialized ~71; return-type ~14; type-limits ~7 + tail).
- Produces: per-class census with exact counts, the `c89_emit.zig` emission site for each class, and the fix approach (suppress / cast / init / restructure); feeds W2-1..4.

- [ ] **Step 1: Rebuild + measure**

Rebuild zig1 + zig1_5 from HEAD `a3fd9a2b` (clean tree). `gcc -m32 -std=c89 -O3 -Wall -Wextra -Wno-long-long -Wno-pointer-sign -Wno-implicit-function-declaration -fsyntax-only /tmp/zig1_5/gen/*.c 2> /tmp/w2.log; wc -l < /tmp/w2.log`; `grep -oE 'warning: [^[]*' /tmp/w2.log | sort | uniq -c | sort -rn` for the full class histogram.

- [ ] **Step 2: Map each class to its `c89_emit.zig` emission site**

For each warning class, trace the emitted pattern back to the `c89_emit.zig` code that produces it (declaration, expression, cast, label, comparison emission). Record `file:line` per class. Determine whether the fix is emitter-level (in `c89_emit.zig`) for every class — if any class can ONLY be fixed in the Zig source (`sf/src/*.zig`), flag it and classify (STOP-present if a source touch would be required — the operator ruled the `undefined` case is emitter-level).

- [ ] **Step 3: Fix-mapping table + report**

Table: class | count | emitted pattern | c89_emit.zig site | fix approach | task owner (W2-1/2/3/4). Ledger + mnemoria (discovery). Read-only: no source changes, no commit.

---

### Task W2-1: Dead-result-temp suppression (emitter)

**Files:**
- Modify: `sf/src/c89_emit.zig` (discarded-expression result temps)
- Commit: `fix: emit (void) for discarded expression results (kill unused-temp-decls)`

**Interfaces:**
- Consumes: W2-I mapping (the ~13,621 unused-temp-decls — the dominant class).
- Produces: gen/ unused-temp-decls eliminated (the bulk of the 17,788 → near-0).

- [ ] **Step 1: Golden baseline (EMISSION-AFFECTING — capture per protocol)**

Capture `/tmp/golden_W2_1/` (4 gate emissions + md5s; 9 runtime fixtures).

- [ ] **Step 2: Fix the emission**

When a Zig expression's result is discarded (statement context), do NOT emit an unused result-temp declaration + dead store — emit `(void)expr;` (or suppress the temp entirely when the expression has no side effects). This is the c89_emit.zig analogue of the codegen.cpp DCE (read how codegen.cpp solved it; port the principle WITHOUT touching the bootstrap). Keep it general (fixes all programs, not just the compiler). Z98-clean.

- [ ] **Step 3: Verify**

Rebuild zig1 + zig1_5. gen/ warning count drops by the unused-temp-decls class (measure before/after). `-Wall -Wextra -O3` on gen/: the unused-temp-decls class = 0. Golden runtime 9/9 byte-identical; 4 MD5 re-baselined with golden evidence (record old→new); self-compile 40 `.c`/0 errors; reference build still 0-warning.

- [ ] **Step 4: Commit + report + ledger + memory**

Commit verbatim. Report before/after counts + re-baseline evidence. Ledger + mnemoria (bugfix).

---

### Task W2-2: sign-compare + int-conversion casts (emitter)

**Files:**
- Modify: `sf/src/c89_emit.zig` (comparison/pointer-cast emission)
- Commit: `fix: emit correct signedness + pointer casts (no -Wsign-compare / -Wint-conversion)`

**Interfaces:**
- Consumes: W2-I mapping (~265 sign-compare + ~98 int-conversion).
- Produces: those classes = 0 in gen/ at `-Wall -Wextra -O3`.

- [ ] **Step 1: Golden baseline (EMISSION-AFFECTING — capture per protocol)**

Capture `/tmp/golden_W2_2/`.

- [ ] **Step 2: Fix the emission**

For sign-compare: emit the correct signedness cast on one operand of mixed-sign comparisons. For int-conversion: emit an explicit cast where a pointer/int or int/pointer conversion is intended (or suppress the erroneous one — verify the Zig source intends it). Emitter-level, general. Z98-clean.

- [ ] **Step 3: Verify**

Rebuild. gen/ sign-compare + int-conversion classes = 0. Golden runtime 9/9; 4 MD5 re-baseline with evidence; self-compile 0 errors; reference build still 0-warning.

- [ ] **Step 4: Commit + report + ledger + memory**

Commit verbatim. Ledger + mnemoria (bugfix).

---

### Task W2-3: undefined-init + return-type + type-limits (emitter)

**Files:**
- Modify: `sf/src/c89_emit.zig` (local-decl + return emission)
- Commit: `fix: init undefined locals to 0 + correct return types (no -Wmaybe-uninitialized/-Wreturn-type/-Wtype-limits)`

**Interfaces:**
- Consumes: W2-I mapping (~71 uninitialized; ~14 return-type; ~7 type-limits).
- Produces: those classes = 0 in gen/ at `-Wall -Wextra -O3`.

- [ ] **Step 1: Golden baseline (EMISSION-AFFECTING — capture per protocol)**

Capture `/tmp/golden_W2_3/`.

- [ ] **Step 2: Fix the emission**

- `undefined` locals: emit `= 0` (or the zero value of the type) for a local whose Zig source initializer is `undefined` — operator-ruled EMITTER-level so users never have to initialize defensively; reads of undefined are UB so `0` is safe. General (all programs).
- return-type: emit correct return statements / explicit `return 0` for non-void-returning paths gcc sees as falling off.
- type-limits: avoid comparisons/ops that gcc proves always-true/overflow (emitter-level adjustments; verify semantics).
Z98-clean.

- [ ] **Step 3: Verify**

Rebuild. gen/ uninitialized + return-type + type-limits classes = 0. Golden runtime 9/9; 4 MD5 re-baseline with evidence; self-compile 0 errors; reference build still 0-warning.

- [ ] **Step 4: Commit + report + ledger + memory**

Commit verbatim. Ledger + mnemoria (bugfix).

---

### Task W2-4: Residual tail → 0 warnings on gen/ (emitter) + GATE

**Files:**
- Modify: `sf/src/c89_emit.zig` (residual classes)
- Commit: `fix: warning-clean self-emission at -Wall -Wextra -O3 (gen 0 warnings)`

**Interfaces:**
- Consumes: W2-1..3 results + W2-I residual mapping.
- Produces: **0 warnings, 0 errors** on `/tmp/zig1_5/gen/*.c` at `-Wall -Wextra -O3` (only the 3 structural `-Wno-*` allowed).

- [ ] **Step 1: Golden baseline (EMISSION-AFFECTING — capture per protocol)**

Capture `/tmp/golden_W2_4/`.

- [ ] **Step 2: Eliminate the residual tail**

Address every remaining gen/ warning class to reach 0 (misc, `main`, leftover duplicates, etc.). Iterate: rebuild zig1 + zig1_5 → measure gen/ → fix → until 0 warnings.

- [ ] **Step 3: Full gate**

gen/ 0 warnings + 0 errors at `-Wall -Wextra -O3`; golden runtime 9/9 byte-identical; corpus sweep (zig1_5 vs zig1: 0 asymmetric/new failures); self-compile 40 `.c`/0 errors; 4 MD5 re-baselined with golden evidence; **reference build still 0-warning**.

- [ ] **Step 4: Commit + report + ledger + memory**

Commit verbatim. Report gen/ before/after (17,788 → 0) + re-baseline evidence. Ledger + mnemoria (pattern).

---

### Task M1: AstNode 32→24 B (roadmap item 1)

**Files:**
- Modify: `sf/src/ast.zig` (AstNode layout :116-128; drop payload u64 → side tables for extra-children ranges + literal values) + all readers/writers (75 `astStoreGetExtraChildren` reader sites across 12 files; 16 `astStoreAddExtraChildren` writer sites in parser.zig; 43 payload/child_2 sites)
- Commit: `refactor: AstNode 32->24B (payload moved to side tables)`

**Interfaces:**
- Consumes: I-1/I-3 (layout + writer/reader split; parser.zig:1447-1448 sole direct packed-range reader).
- Produces: module-arena live drops ≈1.44 MB; emitted AstNode = 24 B.

- [ ] **Step 1: Golden baseline (EMISSION-AFFECTING — the compiler's own C changes; user-program emission should not)**

Capture `/tmp/golden_M1/` (4 gates + fixture set run outputs).

- [ ] **Step 2: Design the 24 B layout**

Per I-1/AMENDMENT 6: `kind u8, flags u8, pad2, span_len u32, span_start u32, child_0 u32, child_1 u32, child_2 u32` = 24 B — **drop `payload u64` entirely** (its content moves to a side table: extra-children ranges `(start u32, count)` and the literal/int/string values). **Padding discipline (AMENDMENT 6, operator m0699):** keep the `pad2` as-is — do NOT reorder fields or squeeze padding to hit the target (the padding may be structural under zig0/C89 alignment); padding elimination is the LAST step, out of scope here. **Indices stay u32** (span_len/span_start/child_0/1/2 were deliberately widened; never shrink back to u16). Keep `extra_children` via a parallel array/side table — see ast.zig:433-454 pool pattern. Preserve the `start<<32|count` range semantics via the side table (start stays u32 — 69,026 > 65,535). Confirm every `payload` read site (u32 low-word consumers) is compatible.

- [ ] **Step 3: Apply the migration**

ast.zig new layout + accessors; update the 16 writers + 75 readers + 43 child_2 sites. parser.zig:1447-1448 packed-range reader updated to the side table. Z98-clean; byte-order/offsets per the emitted header (update `ZZZ_ASTNODE_32B` marker to reflect the new size).

- [ ] **Step 4: Verify**

Rebuild zig1 + zig1_5. Emitted AstNode sizeof = 24 B. `--track-memory` self-compile `mod=` drops ≈1.44 MB (16,383 K → ~14,900 K). Self-compile 0 errors. **User-program emission: 4 MD5 gates byte-identical** (AstNode is internal; the 4 gates' C must not change) + golden runtime matches. Matrix 21/21.

- [ ] **Step 5: Commit + report + ledger + memory**

Commit verbatim. Report sizeof + mod-arena delta. Ledger + mnemoria (decision/refactor).

---

### Task M2: LirInst 32→24 B (roadmap item 2)

> **AMENDMENT 7 (operator-ruled 2026-08-26, alignment check):** the original "20 B" target is **unmeetable** — i386 `gcc -m32` 4-byte alignment makes `enum_const` (u64 + 3×u32 = 20 B) the floor after side-tabling the call variants; the literal "call/tail_call" scope alone yields **28 B** (because `builtin_socket_select` = 24 B becomes the union max). **Corrected target = 24 B**: side-table `tail_call` (28) + `call_direct` (28) + `builtin_socket_select` (24) → union max = `enum_const` 20 → struct = tag(4) + 20 = 24 B. `enum_const.value u64` STAYS in-node (reaching 20 B would require side-tabling it too — marginal, rejected). Indices stay u32.

**Files:**
- Modify: `sf/src/lir.zig` (union(enum) :22-102 reshape; side-table `tail_call` 28 B + `call_direct` 28 B + `builtin_socket_select` 24 B) + all `switch(inst)` consumers (c89_emit.zig:2780/4324/6308, lower.zig:5699-5860, construction sites lower.zig:2934/5136/2523/1652/1668) + `lirFunctionRelocateToModule` (lir.zig:373-470)
- Commit: `refactor: LirInst 32->24B (side-table call/tail_call/socket_select operands)`

**Interfaces:**
- Consumes: I-1/I-3 (24 B floor — union max = `enum_const` 20 B after the 3 wide variants are side-tabled; side-table the 6-8-operand call variants).
- Produces: module-arena live drops ≈1.3-1.5 MB; emitted LirInst = 24 B.

- [ ] **Step 1: Golden baseline (EMISSION-AFFECTING — capture per protocol)**

Capture `/tmp/golden_M2/`.

- [ ] **Step 2: Design the 24 B layout**

Move the wide operands (callee, module_id, args, return_type, is_indirect, is_extern for `tail_call`/`call_direct`; nfds/readfds/writefds/exceptfds/timeout_ms/result for `builtin_socket_select`) into a per-fn side table, relocated with `lirFunctionRelocateToModule` (see I-3 Concern 2 re pointer stability). Keep the `switch(inst)` dispatch working via the 4 B tag. **Padding/alignment discipline (AMENDMENT 6):** the u64 `int_const`/`float_const`/`enum_const` values stay u64 in-node (genuine 8-byte values); do NOT realign variants or squeeze union padding — `enum_const` 20 B is the accepted floor. Operand indices stay u32.

- [ ] **Step 3: Apply the migration**

lir.zig new layout + side-table append/read helpers; update all constructors + consumers. Z98-clean.

- [ ] **Step 4: Verify**

Rebuild. Emitted LirInst sizeof = 24 B (or actual — report; do NOT force alignment tricks). `--track-memory` self-compile `mod=` drops ≈1.3-1.5 MB. Self-compile 0 errors. 4 MD5 gates byte-identical + golden runtime matches. TCO fixtures (tco_return_try/tco_defer/tco_factorial) still byte-equal to golden.

- [ ] **Step 5: Commit + report + ledger + memory**

Commit verbatim. Report sizeof + mod delta. Ledger + mnemoria (decision/refactor).

---

### Task M5: AST side arrays + token value union (roadmap item 5)

> **AMENDMENT 8 (operator-ruled 2026-08-26): CLOSED AS UNFEASIBLE.** The Token 16 B target is not reachable without risk, verified by a read-only audit (implementer BLOCKED + controller re-check): `TokenValue` (`token.zig:122-127`) genuinely carries `int_val: u64` and `float_val: f64` — the Token is the **only carrier** of literal values into the AstStore pools, read at `parser.zig:539/546/550/562` + `dump_tokens.zig:26/29`. `sf/src` itself contains `>u32` literals (`4294967296`, `1099511628211`, …) and f64 literals; truncation would corrupt them. 16 B requires `packed` (rejected by zig0 — `token.zig:129-131` FIXME) or a module-side literal-value pool (I-3 Option A) / literal-text re-parse (Option B) — both deferred (I-COMPACT-era decision). The AST side-array part is already completed by M1 (payload → dense u32 table + `extra_ranges` u64 pool + literal pools). **No source change, no commit.** Token stays 20 B (live win was only ~60 KB — scratch transient).

**Files:**
- (no change — closed unfeasible, AMENDMENT 8)
- Commit: (none)

**Interfaces:**
- Consumes: I-1/I-3 + the M5 token-value audit (5 genuine u64/f64 read sites).
- Produces: documented no-op; Token retained at 20 B; the token-value-pool option recorded for a future I-COMPACT decision.

- [ ] **Step 1 (done — audit):** verified the 5 u64/f64 read sites + the zig0 `packed` rejection + M1-completed AST side arrays. Result: Token 16 B unfeasible without risk; M5 closed.

- [ ] **Step 2 (done):** report the finding to `.superpowers/sdd/task-MEMREFACTOR-report.md` (`## M5 fix` — BLOCKED audit + options + controller confirmation). No source change, no commit. Ledger + mnemoria (decision).

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

### Task I-4B: Module-arena reset ceiling measurement (read-only)

> **AMENDMENT 9 (operator m0779):** the ≤16 MiB pool target requires a module-arena reset (pool is the cumulative bump; only a reset makes it track live). This task measures the reset ceiling BEFORE any code change, so 4(b)-1/4(b)-2 are known worth it.

**Files:**
- Report: `.superpowers/sdd/task-MEMREFACTOR-report.md` (append `## I-4B` section)

**Interfaces:**
- Consumes: runCompiler phase structure (main.zig:200-272: ImportResolution → SymbolRegistration → TypeResolution → FrontResolution → ComptimeEvaluation → SemanticAnalysis → StaticAnalyzers → LIRLowering → C89Emission); the module arena (`ctx.alloc.module`) holding AST store + resolution tables + relocated LIR.
- Produces: per-phase module-arena growth (live), the exact dead-data boundary, and the quantified reset ceiling (expected pool after 4(b)-1+4(b)-2).

- [ ] **Step 1: Measure per-phase module-arena live size**

Read `runCompiler` (main.zig:200-272) + the module-arena consumers. At each phase boundary, record the module-arena live high-water (via `alloc_mod` internals / `--track-memory mod=` checkpoints, or a targeted /tmp-only instrumented build). Confirm which phases grow `ctx.alloc.module` and by how much.

- [ ] **Step 2: Pin the dead-data boundary**

Verify `c89_emit` reads ONLY LIR (its `.store` is the LIR instruction, not the AST store) — i.e., after `phase_LIRLowering`, the AST store + `resolved_types` + `comptime_values` are dead. Grep/confirm no AST-store reads in `phase_C89Emission` paths.

- [ ] **Step 3: Quantify the reset ceiling**

Compute: after 4(b)-1 (LIR → dedicated `lir_arena`) + 4(b)-2 (module-arena reset after lowering), `pool.peak` ≈ max(live module during lowering, LIR live) + scratch + perm + type_db. State the expected pool vs the 16,384 K target, and whether spill (M6) would still be needed. Also record the current `pool=` (~50,501 K) as the no-reset baseline.

- [ ] **Step 4: Report + ledger + memory**

Report: per-phase table, dead-boundary evidence, reset-ceiling number, reachability verdict. Ledger + mnemoria (discovery). Read-only: no source changes, no commit.

---

### Task I-STREAM: Streaming / disk-backed AST design + complete-path decision (read-only)

> **AMENDMENT 10 (operator m0805/m0810):** the "AST spill blocked" framing was over-stated. Per-MODULE dumping IS blocked (interleaved flat node array + node_idx-keyed `resolved_types`/`comptime_values`/`decl_node` + ComptimeEvaluation full-store scan), but whole-AST streaming (write-through, always-on-disk) is viable because the AST is **write-once** (parser-only writer). This task designs it and issues the COMPLETE-PATH decision (streaming execution tasks vs incremental 4(b)-1/2→M6).

**Files:**
- Report: `.superpowers/sdd/task-MEMREFACTOR-report.md` (append `## I-STREAM` section)

**Interfaces:**
- Consumes: I-4B verdict (4(b)+M6 → post-M6 live 16,727 KiB ≈ 16.3 MiB / pool ~48 MiB, misses 16,384 K); write-once AST (only parser appends; ~281 `store.nodes.items` read sites across 16 non-test files, 0 writes); M1 side tables (dense `payload` u32 + sparse `extra_ranges` u64); resolution tables `resolved_types`/`comptime_values` (~11 MB, node_idx-keyed, read by analysis + lowering); ComptimeEvaluation full-store scan (main.zig:393-394); module-arena structure (main.zig:200-272).
- Produces: streaming-AST design + per-item migration census + pool-ceiling estimate + the COMPLETE-PATH go/no-go (ordered task list for the chosen path with expected pool/RSS at each step).

- [ ] **Step 1: Design the disk-backed node storage (preserving the u32 index space)**

Block-based node storage: `store.nodes` → fixed-size blocks (e.g., 4096 nodes/block = 96 KB at 24 B), a RESIDENT block table mapping `block → resident-pointer | disk-slot`, and `store.node(idx) = blocks[idx>>12][idx & 0xFFF]` with fault-in on non-resident blocks. Write-through: the parser appends to the current block, spilling full blocks to disk. NO write-back needed (write-once). Confirm the `u32` node_idx space is preserved so `resolved_types`/`comptime_values`/`decl_node` keys stay valid, and that M1's `payload`/`extra_ranges` side tables stay consistent (resident or block-backed).

- [ ] **Step 2: Migration census**

Enumerate with `file:line` + counts: (a) parser append path (`astStoreAddNode` + writers) → block append + spill; (b) the ~281 `store.nodes.items` read sites → `store.node(idx)` accessor (list per-file counts); (c) the resolution tables `resolved_types`/`comptime_values` (~11 MB, as big as the AST) → same disk-backed treatment or per-module restructure; (d) ComptimeEvaluation full-store scan → streaming sequential block sweep (small resident window — it is already a single linear pass); (e) `error_code_registry` (module-backed) + `global_decls`/`lir_fns` survivors. Classify each as mechanical / needs-design / blocked.

- [ ] **Step 3: Pool-ceiling estimate**

For the STREAMING build (write-through): `pool.peak` ≈ bounded parser buffer + resident block window + scratch + perm + type_db + resolution-table window (if streamed) — state whether pool ≤ 16,384 K is reachable, and the RSS bound. Compare against the INCREMENTAL path (4(b)+M6: 16,727 KiB live / ~48 MiB pool). Note the monotonic-pool subtlety: streaming caps the bump (never fully materialized), so it is the only approach that can guarantee ≤16 MiB pool.

- [ ] **Step 4: Complete-path decision (go/no-go) + report**

Issue the recommendation + the complete ordered task list:
- **(a) STREAM** — new execution tasks (S-1 node-block storage + write-through; S-2 accessor migration of the ~281 sites; S-3 resolution-table streaming; S-4 comptime streaming sweep), each with its own gate (4 MD5 byte-identical, golden 9/9, self-compile, pool measure).
- **(b) INCREMENTAL** — keep 4(b)-1 → 4(b)-2 → M6 → I-COMPACT → GATE, accept ~48 MiB pool / ~16.3 MiB live.
State expected pool/RSS at each step of the recommended path so the operator can decide. Report + ledger + mnemoria (decision). Read-only: no source changes, no commit.

---

### Task 4(b)-1: Split LIR into a dedicated arena (mechanical, byte-neutral)

> **SUPERSEDED by AMENDMENT 11 (operator m0843).** The streaming S-series (S-LIR) subsumes this — LIR is spilled/streamed directly instead of given its own arena so the module arena can be reset. Do NOT execute this task. Kept as a historical alternative.
>
> **AMENDMENT 9:** LIR is in the module arena only to survive lowering→emission. Give it its own arena so the module arena (AST + resolution tables) becomes resettable after lowering.

**Files:**
- Modify: `sf/src/main.zig` (add `lir_arena: Sand` to CompilerAlloc; init), `sf/src/lir.zig` (`lirFunctionRelocateToModule` → relocate into the LIR arena instead of module), callers
- Commit: `refactor: relocate LIR into a dedicated arena (decouple from AST module arena)`

**Interfaces:**
- Consumes: I-4B dead-boundary finding; `lirFunctionRelocateToModule` (lir.zig:373-470, deep-copy scratch→module).
- Produces: LIR in its own arena; module arena holds AST + resolution tables only; emission unchanged.

- [ ] **Step 1: Golden baseline (EMISSION-AFFECTING — capture per protocol)**

Capture `/tmp/golden_4b1/` (4 gates + 9 fixtures).

- [ ] **Step 2: Add the LIR arena**

Add `lir_arena: Sand` to `CompilerAlloc` (allocator.zig) + init in main.zig; change `lirFunctionRelocateToModule` and its call sites to relocate into `lir_arena` (preserving the deep-copy + pointer-stability semantics). Z98-clean; indices stay u32.

- [ ] **Step 3: Verify byte-neutrality**

Rebuild zig1 + zig1_5. 4 MD5 gates byte-identical; golden 9/9; self-compile 40 `.c`/0 errors; ref 0-warning; matrix 21/21. **Emissions must be unchanged** (this is a pure arena-routing change).

- [ ] **Step 4: Commit + report + ledger + memory**

Commit verbatim. Report arena-routing diff + gate evidence. Ledger + mnemoria (refactor).

---

### Task 4(b)-2: Reset the module arena after lowering (pool tracks live)

> **SUPERSEDED by AMENDMENT 11 (operator m0843).** Streaming (S-series) caps the pool bump better than a post-lowering reset, and the `error_code_registry` module-backed survivor makes the reset a hard stop anyway. Do NOT execute this task. Kept as a historical alternative.
>
> **AMENDMENT 9:** after 4(b)-1, everything in the module arena is dead post-`phase_LIRLowering`. Reset it at the Lowering→Emission boundary so the monotonic pool reuses those bytes (pool.peak → live, not cumulative). This is the genuinely hard, high-risk item — the enabler for both the ≤16 MiB pool target and M6 spill.

**Files:**
- Modify: `sf/src/main.zig` (reset `ctx.alloc.module` between `phase_LIRLowering` and `phase_C89Emission`), `sf/src/allocator.zig` (if `sandReset` needs a "release chains" variant for true reuse)
- Commit: `perf: reset module arena after lowering (pool tracks live, not cumulative)`

**Interfaces:**
- Consumes: 4(b)-1 (LIR out of module arena); I-4B (dead-boundary proof + expected ceiling).
- Produces: pool.peak drops from ~50,501 K toward the I-4B ceiling (≤16,384 K if the ceiling says so); AST + resolution tables freed after lowering.

- [ ] **Step 1: Golden baseline (EMISSION-AFFECTING — the compiler's own allocations change; user-program emission must not)**

Capture `/tmp/golden_4b2/` (4 gates + 9 fixtures). Note: `pool=`/`mod=` will change by design (that's the point); byte-identity applies to the emitted C + runtime, NOT the track-memory numbers.

- [ ] **Step 2: Reset the module arena**

Between `phase_LIRLowering` and `phase_C89Emission` in `runCompiler`, `alloc_mod.sandReset(&ctx.alloc.module)` (or a release-to-pool variant). Verify via I-4B + 4(b)-1 that no live pointer into the module arena survives (AST/resolution tables dead; LIR moved out). STOP if `c89_emit` or the emission path needs ANY module-arena data.

- [ ] **Step 3: Verify pool drop + correctness**

Rebuild. `--track-memory` self-compile: `pool=` must drop substantially (measure; compare to I-4B ceiling). 4 MD5 gates byte-identical (user-program emission unchanged); golden 9/9; self-compile 40 `.c`/0 errors; ref 0-warning; matrix 21/21.

- [ ] **Step 4: Commit + report + ledger + memory**

Commit verbatim. Report pool before/after + I-4B ceiling reconciliation + pointer-safety proof. Ledger + mnemoria (bugfix/refactor).

---

### Task S-LIR: Spill LIR to disk (LOWEST risk — self-contained per-fn)

> **AMENDMENT 11 (supersedes M6):** LIR (10.4 MB) is the lowest-risk spill — self-contained per-fn scalar units (lir.zig:371-372), already relocated, per-module grouped (main.zig:775-776). Designed by I-STREAM S-5 + I-4B. F task only.

**Files:**
- Modify: `sf/src/lir.zig`, `sf/src/main.zig` (per-module LIR spill/reload around `phase_C89Emission`), `sf/src/c89_emit.zig` (read via fault-in accessor if needed)
- Commit: `perf: spill per-module LIR to disk`

**Interfaces:**
- Consumes: I-STREAM S-5 design; I-4B (LIR live ~10.4 MB during lowering; emission reads LIR only).
- Produces: LIR no longer resident as a full 10.4 MB bump; pool drops ~8 MB toward the S-series floor.

> **AMENDMENT 12 (operator-ruled 2026-08-26, after S-LIR-F commit `eb203fe8`):** S-LIR is confirmed as **stream-during-lowering** (serialize each `LirFunction` to disk as it is lowered; keep only a disk-slot table resident; fault-in per function during emission) — NOT spill-after-lowering, which cannot lower `pool.peak` (monotonic bump). The S-LIR-F implementation self-declared `fopen/fread/fputc/fclose/fseek` externs in `sf/src/lir_stream.zig` and used byte-at-a-time `fputc` — REJECTED. All disk I/O externs MUST live in `sf/src/pal.zig` (the platform layer, Win9x target); `lir_stream.zig` must `@import("pal.zig")` and use pal's API. Use bulk `fwrite` (declare `extern "c" fn fwrite(buf: [*]const u8, size: u32, count: u32, file: *void) u32;` in pal.zig mirroring `fread`) — the earlier `[*]const void` form failed because Z98 emits `void*` (drops `const` on `void`); `[*]const u8` emits `const unsigned char*`, analogous to the warning-clean `fread([*]u8,…)`. Warnings may appear: if `fwrite([*]const u8,…)` still trips `-Wbuiltin-declaration-mismatch`, a documented `-Wno-builtin-declaration-mismatch` carve-out on the warning gate is acceptable (solve later) — do NOT work around it architecturally.

- [ ] **Step 1: Golden baseline (EMISSION-AFFECTING — capture per protocol)** — capture `/tmp/golden_SLIR/` (4 gates + 9 fixtures).
- [ ] **Step 2: Implement** — stream each LirFunction to disk as lowered (AMENDMENT 12); all I/O externs in `pal.zig` (add `fwrite`); `lir_stream.zig` imports pal, no self-declared externs, bulk `fwrite` not `fputc`; reload per module in `phase_C89Emission`; preserve the u32 index/ordinal space; Z98-clean.
- [ ] **Step 3: Verify** — 4 MD5 byte-identical (or re-baseline with golden runtime evidence); golden 9/9; self-compile 40 .c/0 err; ref 0-warning (or documented `-Wno-builtin-declaration-mismatch` carve-out per AMENDMENT 12); `pool=` drops toward the measured floor (record).
- [ ] **Step 4: Commit + report + ledger + memory** — commit verbatim.

---

### Task S-HASH: Spill perm hash maps after import (LOW — stage-done)

> **AMENDMENT 11:** `path_to_id`/`content_to_id` are WRITE-ONCE in import resolution (module_registry.zig:315/345/361/367/370/374/377), then query-only. Small but proven stage-done → a clean first disk-backed win. I + F.

**Files:**
- Modify: `sf/src/module_registry.zig` (disk-back `path_to_id`/`content_to_id` after import resolution), `sf/src/allocator.zig` if a release path is needed
- Commit: `perf: spill perm hash maps to disk after import resolution`

**Interfaces:**
- Consumes: the write-once finding (m0834/m0839); hash.zig U32ToU32Map.
- Produces: perm shrinks by the hash-map footprint; establishes the write-through/fault-in pattern for later S items.

- [ ] **Step 1: (I) census** — read-only: list every perm-arena hash map, its write phase and read phases, and size; confirm none is written after import resolution. Report to `.superpowers/sdd/task-MEMREFACTOR-report.md`.
- [ ] **Step 2: Golden baseline** — capture `/tmp/golden_SHASH/`.
- [ ] **Step 3: (F) implement** — disk-back the confirmed write-once maps (write-through on put, fault-in on get); Z98-clean.
- [ ] **Step 4: Verify** — 4 MD5 byte-identical; golden 9/9; self-compile clean; `pool=`/`perm=` drops (record).
- [ ] **Step 5: Commit + report + ledger + memory** — commit verbatim.

---

### Task S-TOKEN: Stream the token array (LOW-MED — eliminates double-lex)

> **AMENDMENT 13 (operator-ruled 2026-08-26):** the 4 MD5 gates are RE-BASELINEABLE with golden-sample runtime evidence — byte-identity is NOT the bar, runtime behavior is (per Global Constraints line 31; as done W2-1/2/3). S-TOKEN deletes `moduleScanDiscover` outright (pull-parser streams tokens; drop per-module count/materialize lex + token array + AST pre-size). RECORDED HAZARD (census §f.4 incomplete): deleting a scan pass shifts interner insertion order → `name_id` values change → `error_code_registry` (open-addressed, keyed by name_id, emitted in slot order by `emitErrorCodePrologue` c89_emit.zig:1775) lays out differently → lisp `#define ERROR_*` prologue reorders (14 lines; semantically identical, codes unchanged). gol/json/mud immune (no error-set defs). Any future "delete a scan pass" task must audit open-addressed maps keyed by `name_id` emitted in slot order. Measured memory win at HEAD: ~2 MB scratch (largest module token array ≈ 86 K × 24 B ≈ 2.06 MB), not the plan's ~6.6 MB (330 K-token figure stale).

**Files:**
- Modify: `sf/src/parser.zig` (pull-token consumption; drop `parserInit(tokens:[]const Token)` full array), `sf/src/import_resolver.zig` (`moduleScanDiscover` count-only pre-sizing vs pull-parse), `sf/src/lexer.zig` if a push→pull interface is needed
- Commit: `perf: stream tokens (pull-parser; drop token array + double-lex)`

**Interfaces:**
- Consumes: parser.zig:32-33/57 (token array); import_resolver.zig:33-73/146-148 (scan + pre-size).
- Produces: scratch peak drops ~2 MB; single lex pass.

- [ ] **Step 1: (I) census** — read-only: map every `tokens_ptr`/`tokens_len`/`peek`/`next` consumer in parser.zig; the AST-store pre-sizing dependency (`nodes_target = total_tokens*6/10`); classify mechanical vs needs-design. Report.
- [ ] **Step 2: Golden baseline** — capture `/tmp/golden_STOKEN/`.
- [ ] **Step 3: (F) implement** — pull-token consumption (depth-3 window + `last_tok` + cached eof); delete `moduleScanDiscover` + per-module count/materialize lex + token array + AST pre-size; Z98-clean; preserve same AST nodes/order/spans.
- [ ] **Step 4: Verify** — 4 MD5 keep-or-re-baseline (re-baseline with golden runtime evidence; EXPECTED: gol/json/mud match, lisp re-baselines to `3591bad9…`); golden 9/9 runtime; self-compile clean; `scratch=` peak drops ~2 MB (record); matrix 21/21.
- [ ] **Step 5: Commit + report + ledger + memory** — commit verbatim.

---

### Task S-AST: Block-based node storage (MED — designed by I-STREAM)

> **AMENDMENT 11:** write-once AST (parser-only writer, ~276 read sites, 0 writes) → block-based disk-backed nodes with a fault-in accessor, preserving the u32 index space. Designed by I-STREAM S-1/S-2. F task.

**Files:**
- Modify: `sf/src/ast.zig` (block table + `store.node(idx)` accessor + write-through append), parser + all ~276 read sites (per I-STREAM census: 270 cast-form + 6 non-cast-form)
- Commit: `perf: disk-backed block AST storage (write-through, fault-in accessor)`

**Interfaces:**
- Consumes: I-STREAM S-1/S-2 (4096-node/96 KB blocks, `blocks[idx>>12][idx & 0xFFF]`, resident ring W=8 + head-pin); M1 side tables (payload/extra_ranges block-parallel).
- Produces: AST no longer a 9.9 MB resident bump; pool drops toward the bounded-buffer window.

- [ ] **Step 1: Golden baseline** — capture `/tmp/golden_SAST/`.
- [ ] **Step 2: Implement** — block storage + accessor + parser write-through; migrate the ~276 read sites; Z98-clean; keep u32 indices.
- [ ] **Step 3: Verify** — 4 MD5 byte-identical; golden 9/9; self-compile clean; `pool=`/`mod=` drop (record); matrix 21/21.
- [ ] **Step 4: Commit + report + ledger + memory** — commit verbatim.

---

### Task S-RES: Stream the resolution tables (HIGHER — ~205 sites)

> **AMENDMENT 11:** `resolved_types`/`comptime_values` (~11 MB, node_idx-keyed, built in semantic analysis, queried in lowering/emission) → same disk-backed treatment or per-module restructure. Designed by I-STREAM S-3. F task; the linear-probing hash (hash.zig:61) is the complication.

**Files:**
- Modify: `sf/src/resolved_type_table.zig` (+ comptime_values), ~182 call sites across 6 files (per I-STREAM census), `sf/src/hash.zig` if the open-addressing needs a disk-backed variant
- Commit: `perf: stream resolution tables (resolved_types/comptime_values disk-backed)`

**Interfaces:**
- Consumes: I-STREAM S-3 (dense-res rewrite, ~205 sites, linear probing); ComptimeEvaluation full-store scan → streaming sweep (main.zig:393-394).
- Produces: resolution tables no longer an 11 MB resident bump.

- [ ] **Step 1: Golden baseline** — capture `/tmp/golden_SRES/`.
- [ ] **Step 2: Implement** — disk-back the tables or restructure per-module; migrate the ~182 sites; streaming comptime sweep; Z98-clean.
- [ ] **Step 3: Verify** — 4 MD5 byte-identical; golden 9/9; self-compile clean; `pool=` drops (record).
- [ ] **Step 4: Commit + report + ledger + memory** — commit verbatim.

---

### Task S-INTERNER: Write-through interner text (HIGHEST — read-constantly)

> **AMENDMENT 11:** the interner is NOT stage-done (196 `Intern` sites across all phases) but its `entries` are append-once+immutable and its `text` bytes are append-only — the ~4 MB bulk. It is READ constantly during emission. The highest-risk item: write-through the text+entries to disk, fault-in on `stringInternerGet`, keeping the mutable `buckets` resident. I + F — do this LAST, only if the pool is still over target after S-LIR..S-RES.

**Files:**
- Modify: `sf/src/string_interner.zig` (disk-backed entries/text + fault-in `stringInternerGet`)
- Commit: `perf: write-through interner to disk (fault-in on lookup)`

**Interfaces:**
- Consumes: m0839 finding (entries immutable, text append-only, buckets mutable, read-constantly).
- Produces: perm shrinks by the ~4 MB text bulk; the emission read path faults per name.

- [ ] **Step 1: (I) census** — read-only: measure per-phase interner read volume (how much text is touched in emission vs other phases); decide fault-in granularity + whether emission can batch lookups. Report + STOP-present if the read cost is prohibitive.
- [ ] **Step 2: Golden baseline** — capture `/tmp/golden_SINT/`.
- [ ] **Step 3: (F) implement** — write-through append + fault-in `stringInternerGet`; keep `buckets` resident; Z98-clean.
- [ ] **Step 4: Verify** — 4 MD5 byte-identical; golden 9/9; self-compile clean; `perm=` drops (record); emission wall acceptable.
- [ ] **Step 5: Commit + report + ledger + memory** — commit verbatim.

---
> **AMENDMENT 14 (operator-ruled 2026-08-26):** correctness fix wave — one F task per open finding across the S-series (S-LIR/S-HASH/S-TOKEN/S-AST) + the carried W2-2/W2-3 findings. Rationale: **a compiler cannot rely on guessing** — the spill/fault-in I/O paths (`pal.zig` streamOpen/streamWrite/streamRead/streamSeek) discard every C return value (`_ = fwrite/fread/fseek`), so a short write/read, failed open, or failed seek silently produces WRONG emitted C. Each finding (even Minor) becomes a discrete F task. Execution order: these run BEFORE I-COMPACT and after S-INTERNER. Every task's gate = 4 MD5 keep-or-re-baseline (current: gol `b335d894`, lisp `3591bad9`, json `76056b97`, mud `4591fef0`) + golden 9/9 + self-compile clean + ref 0-warning (pre-authorized pal.c `fwrite` carve-out is not a defect).

### Task S-FIX-1: I/O error discipline (systemic — pal.zig + all spill call sites)

**Files:**
- Modify: `sf/src/pal.zig` (`streamOpen`/`streamWrite`/`streamRead`/`streamSeek`), all spill/fault-in call sites (`sf/src/lir_stream.zig`, `sf/src/module_registry.zig` hash spill, `sf/src/ast.zig` block spill/fault)
- Commit: `fix: verify spill I/O results (ICE on short write/read/seek, null handle)`

**Interfaces:**
- Consumes: the systemic finding (pal.zig:113/118/123 `_ = fwrite/fread/fseek`; :96 streamOpen `?*void` never null-checked at call sites).
- Produces: every spill I/O failure becomes a clear ICE (panicHandler "out of memory"-style diagnostic), never silent wrong output.

- [ ] **Step 1:** `streamWrite`/`streamRead` check the C return equals the requested byte count → on short/mismatch `panic` (ICE); `streamSeek` checks return == 0 → ICE on failure.
- [ ] **Step 2:** null-check `streamOpen` at EVERY call site (ast.zig:513 spill_handle, lir_stream.zig lirStreamBeginWrite/BeginRead, module_registry.zig hash spill open) → ICE on null.
- [ ] **Step 3:** Verify — 4 MD5 byte-identical; golden 9/9; self-compile; ref 0-warning.
- [ ] **Step 4:** Commit verbatim + report + ledger + memory.

### Task S-FIX-2: S-HASH fault-in failure is an ICE, not a silent null

**Files:**
- Modify: `sf/src/module_registry.zig` (`moduleRegistryFaultInPathToId` + `moduleRegistryPathToIdGet`)
- Commit: `fix: S-HASH fault-in failure is an ICE, not a silent null`

**Interfaces:**
- Consumes: S-HASH Important + Minor 1 (fault-in open-failure → `spilled=1` + empty map → every Get silently returns null; a future direct Get/Put silently wrong).
- Produces: post-spill Get either faults successfully or aborts with a clear diagnostic; a direct (un-routed) Get path is structurally prevented or guarded.

- [ ] **Step 1:** fault-in: on open/read failure or empty-after-fault → panic (ICE), never return a null-bearing empty map.
- [ ] **Step 2:** guard the coupling — a `u32ToU32MapGet`/`Put` on a spilled `path_to_id` must route through the helper (or assert), so future call sites cannot silently misbehave.
- [ ] **Step 3:** Verify — 4 MD5 byte-identical; golden 9/9; self-compile; ref 0-warning.
- [ ] **Step 4:** Commit verbatim + report + ledger + memory.

### Task S-FIX-3: S-HASH fault-in validates cap/count before allocate

**Files:**
- Modify: `sf/src/module_registry.zig` (hash spill read)
- Commit: `fix: S-HASH fault-in validates cap/count before allocate`

**Interfaces:**
- Consumes: S-HASH Minor 3 (fault-in trusts file-sourced `cap`/`count`; a corrupt file could oversize `sandAlloc`).
- Produces: fault-in cross-checks file header cap/count against the recorded spill metadata; mismatch → ICE.

- [ ] **Step 1:** read the recorded meta (capacity/count stored at spill) and verify the file header matches before any `sandAlloc`.
- [ ] **Step 2:** on mismatch or absurd size (> a sane bound) → ICE, not allocation.
- [ ] **Step 3:** Verify — 4 MD5 byte-identical; golden 9/9; self-compile; ref 0-warning.
- [ ] **Step 4:** Commit verbatim + report + ledger + memory.

### Task S-FIX-4: S-LIR checks spill fopen success

**Files:**
- Modify: `sf/src/lir_stream.zig` (`lirStreamBeginWrite`/`lirStreamBeginRead`)
- Commit: `fix: S-LIR checks spill fopen success`

**Interfaces:**
- Consumes: S-LIR Minor 1 (null handle → silent no-op writes while the slot table records offsets → wrong C).
- Produces: fopen null → ICE immediately.

- [ ] **Step 1:** after `streamOpen`, null-check the handle in both BeginWrite and BeginRead → ICE on null.
- [ ] **Step 2:** Verify — 4 MD5 byte-identical; golden 9/9; self-compile; ref 0-warning.
- [ ] **Step 3:** Commit verbatim + report + ledger + memory.

### Task S-FIX-5: S-LIR asserts byte_len on read

**Files:**
- Modify: `sf/src/lir_stream.zig` (`lirStreamReadFunction`)
- Commit: `fix: S-LIR asserts byte_len on read`

**Interfaces:**
- Consumes: S-LIR Minor 2 (`byte_len` recorded but never asserted; the S-LIR-I design said "asserted on read" and it was dropped).
- Produces: a wrong seek/offset is caught (ICE) instead of silently reading garbage.

- [ ] **Step 1:** after reading a function, verify the consumed bytes equal `slot.byte_len` (or verify the record header offsets) → mismatch ICE.
- [ ] **Step 2:** Verify — 4 MD5 byte-identical; golden 9/9; self-compile; ref 0-warning.
- [ ] **Step 3:** Commit verbatim + report + ledger + memory.

### Task S-FIX-6: S-AST closes the spill file

**Files:**
- Modify: `sf/src/ast.zig` (spill lifecycle) + `sf/src/main.zig` (call the close at end of emission)
- Commit: `fix: S-AST closes the spill file`

**Interfaces:**
- Consumes: S-AST Minor 1 (spill_handle never closed — correct only because fseek-before-read happens to flush; fragile invariant + crash-mid-write hazard).
- Produces: explicit close/flush at end of `phase_C89Emission`; no reliance on exit-time flush.

- [ ] **Step 1:** add an explicit `streamClose` for the AST spill handle at the end of emission (both output-dir and non-output-dir paths).
- [ ] **Step 2:** Verify — 4 MD5 byte-identical; golden 9/9; self-compile; ref 0-warning.
- [ ] **Step 3:** Commit verbatim + report + ledger + memory.

### Task S-FIX-7: S-AST guards spill seek offset width

**Files:**
- Modify: `sf/src/ast.zig` (fault-in/spill `i32` seek offset)
- Commit: `fix: S-AST guards spill seek offset width`

**Interfaces:**
- Consumes: S-AST Minor 6 (`i32` seek offset overflows past ~18,730 blocks / ~77 M nodes).
- Produces: a bound check (or 64-bit-aware seek) so a pathological AST cannot silently seek to a wrong offset.

- [ ] **Step 1:** guard `bi * AST_BLOCK_REC_SIZE` against `i32` overflow (assert block count below the limit) → ICE if exceeded.
- [ ] **Step 2:** Verify — 4 MD5 byte-identical; golden 9/9; self-compile; ref 0-warning.
- [ ] **Step 3:** Commit verbatim + report + ledger + memory.

### Task S-FIX-8: Emit C89-legal zero-init (drop C99 compound literal)

**Files:**
- Modify: `sf/src/c89_emit.zig` (`.ret_void` → `return (T){0}` sites, ~6)
- Commit: `fix: emit C89-legal zero-init (drop C99 compound literal)`

**Interfaces:**
- Consumes: W2-3 Important #1 (`return (T){0}` C99 compound literal breaks msvc6/openwatcom).
- Produces: C89-legal zero-init for the non-scalar ret_void fallthrough sites (e.g., a named temp `T t = {0}; return t;` or an equivalent that is valid strict C89).

- [ ] **Step 1:** replace each `return (T){0}` with a C89-legal form (verify with `gcc -m32 -std=c89 -pedantic` on the emitted gen C).
- [ ] **Step 2:** Verify — 4 MD5 keep-or-re-baseline; golden 9/9; self-compile; ref 0-warning.
- [ ] **Step 3:** Commit verbatim + report + ledger + memory.

### Task S-FIX-9: Comparison cast width-guard (no narrow truncation)

**Files:**
- Modify: `sf/src/c89_emit.zig` (comparison cast, W2-2)
- Commit: `fix: comparison cast width-guard (no narrow truncation)`

**Interfaces:**
- Consumes: W2-2 Important-latent (comparison cast keys signedness only, not width — a u8/u16 unsigned operand would truncate an out-of-range int).
- Produces: the cast is emitted only when the unsigned operand width ≥ the signed operand width; otherwise no narrowing cast (or a widening one).

- [ ] **Step 1:** add the width guard so a mixed-sign comparison never casts the signed operand DOWN into a narrower unsigned type.
- [ ] **Step 2:** Verify — 4 MD5 byte-identical; golden 9/9; self-compile; ref 0-warning.
- [ ] **Step 3:** Commit verbatim + report + ledger + memory.

### Task S-FIX-10: Remove dead spill machinery

**Files:**
- Modify: `sf/src/ast.zig` (dead `astStoreEnsureNodesCapacity`, redundant lir_read reset) + `sf/src/lir.zig` (dead `lirFunctionRelocateToModule`, `LirFunctionArrayList`), `sf/src/module_registry.zig` (unused spill-meta fields), `sf/src/main.zig` (redundant `lir_read` reset)
- Commit: `chore: remove dead spill machinery (S-AST/S-LIR)`

**Interfaces:**
- Consumes: S-LIR Minor 5 + S-AST Minor 3 + S-HASH Minor 2 + the redundant-reset note.
- Produces: no dead code; every removal verified to have zero references (including test files) before deleting.

- [ ] **Step 1:** grep each target (fns, types, fields) for references across `sf/src` (incl. tests); only delete if zero.
- [ ] **Step 2:** delete; rebuild.
- [ ] **Step 3:** Verify — 4 MD5 byte-identical; golden 9/9; self-compile; ref 0-warning.
- [ ] **Step 4:** Commit verbatim + report + ledger + memory.

### Task S-FIX-11: gitignore spill temp files

**Files:**
- Modify: `.gitignore` (add `.zig1_ast.tmp`, `.zig1_hash.tmp`, `.zig1_lir.tmp`)
- Commit: `chore: gitignore spill temp files`

**Interfaces:**
- Consumes: S-LIR/S-HASH/S-AST leftover temp files in repo CWD on no-output-dir runs.
- Produces: spill temp files no longer pollute `git status`.

- [ ] **Step 1:** append the three `.zig1_*.tmp` patterns to `.gitignore`; confirm `git status` is clean of them.
- [ ] **Step 2:** Commit verbatim.

### Task S-FIX-12: astStoreComputeMemory reports block-window size

**Files:**
- Modify: `sf/src/ast.zig` (`astStoreComputeMemory`)
- Commit: `fix: astStoreComputeMemory reports block-window size`

**Interfaces:**
- Consumes: S-AST Minor 4 (computes nodes as `len × 24 B` — over-reports for disk-backed storage; tests-only today).
- Produces: the reported AST memory is the resident window (slots) + block table, not `len × 24 B`.

- [ ] **Step 1:** recompute: resident slots' allocated node/payload bytes + block-table + resident side tables.
- [ ] **Step 2:** Verify — build + `ast_tests` (if buildable) or confirm the number is sane; 4 MD5 byte-identical; self-compile.
- [ ] **Step 3:** Commit verbatim + report + ledger + memory.

### Task S-FIX-13: migrate tests to the astStoreNodeAt accessor

**Files:**
- Modify: `sf/src/tests/*` (stale `store.nodes.items` refs: test_lower_bin, test_recovery_expr, test_semantic_bin, ast_tests, debug_err_recovery)
- Commit: `chore: migrate tests to astStoreNodeAt accessor`

**Interfaces:**
- Consumes: S-AST Minor 5 (tests still reference the removed `nodes.items`).
- Produces: the test sources compile against the block-backed store (or are documented as out-of-build if they were already broken pre-M1/S-AST).

- [ ] **Step 1:** replace `store.nodes.items[X]` with `astStoreNodeAt(&store, X)` in the listed test files.
- [ ] **Step 2:** attempt to build the affected tests; for any pre-broken test (pre-existing errors identical at base), document rather than fix.
- [ ] **Step 3:** Commit verbatim + report + ledger + memory.

### Task S-FIX-14: S-TOKEN formal task review (process gap)

**Files:**
- Report: `.superpowers/sdd/task-MEMREFACTOR-report.md` (append `## S-TOKEN review`)
- Commit: none (read-only review)

**Interfaces:**
- Consumes: S-TOKEN never received a formal task review (process gap — moved on after the operator's +10 MB transient ruling).
- Produces: an independent review of commit `000b0a73` (pull-parser) with spec-compliance + quality verdicts; any new findings recorded for the fix wave.

- [ ] **Step 1:** generate the review package (`review-package 0d5bd3bb 000b0a73`).
- [ ] **Step 2:** dispatch the task reviewer (brief = S-TOKEN plan task + AMENDMENT 13; report = `## S-TOKEN-F (final)`); record verdict + findings.

---

### Task I-COMPACT: clever 16-B AstNode compaction evaluation (read-only, orthogonal; gated after the S-series)

> **AMENDMENT 6 + 11 (operator m0694/m0843):** I-COMPACT (span out-of-line + child_2 side table + payload u32 → ~16 B nodes) is ORTHOGONAL to the S-series: under streaming it shrinks the block size + resident window rather than the pool bump directly. Evaluate it AFTER the S-series, only if the pool is still over 16,384 K and the remaining gap is the AST node size. Go/no-go recommendation only — no `sf/src` changes, no commit.

**Files:**
- Report: `.superpowers/sdd/task-MEMREFACTOR-report.md` (append `## I-COMPACT` section)

**Interfaces:**
- Consumes: measured `pool=`/`total=` after M1/M2/M5 (+M6 if not skipped); I-1/I-3 layout data; the span-read census (404 `.span_start` + 334 `.span_len` non-ast.zig read sites across parser/lower/semantic_analyzer/analyzer/diagnostics).
- Produces: go/no-go recommendation for a future B execution, with the quantified remaining gap and the ~16 B layout design + migration cost (≈700 span-read sites + diagnostics-path impact).

- [ ] **Step 1: Measure the post-A+M6 state**

`--track-memory --markers` self-compile: `pool=` and `total=` after M1/M2/M5 (+M6 result). Record the gap to the 16,384 K target.

- [ ] **Step 2: Quantify the B opportunity**

From the I-1 census: AstNode 32→16 B = half the AST memory (5.76 MB → ~2.9 MB at current node counts, scaled to post-migration counts). Break down: span out-of-line (8 B — the biggest chunk, read 404+334 sites, ~all for diagnostics/error location), child_2 side table (4 B — 10/112 kinds, 43 sites), payload u32 (already M1). Verify by reading whether span reads are error-path-only or hot-path (sample lower.zig/analyzer.zig span reads).

- [ ] **Step 3: Design the ~16 B layout + migration cost**

`kind u8, flags u8, pad2, child_0 u32, child_1 u32, payload u32` = 16 B, with `span_start`/`span_len` and `child_2` in parallel side arrays (ast.zig:433-454 pool pattern). Enumerate the migration: the ~700 span-read sites → accessor `astStoreSpanOf(node)`, the 43 child_2 sites, and the diagnostics/recovery paths that consume spans. Note padding discipline (AMENDMENT 6): keep `pad2`; never force-reorder.

- [ ] **Step 4: Go/no-go + report**

Go/no-go: recommend B ONLY if the post-A+M6 gap to ≤16 MiB is not closed by A+M6 and B's ~2.9 MB AST reduction is the decisive lever; otherwise recommend against (record the closing measurement). If no-go, note what WOULD justify revisiting. Report: measured state, B opportunity table, layout + migration cost, go/no-go. Ledger + mnemoria (decision). Read-only: no source changes, no commit.

---

### Task GATE: Full sweep + reconciliation

**Files:**
- Modify: `repro/mi_matrix/EXPECTED_FAIL.md`, `docs/sf/QUICK_REF.md`, `docs/superpowers/specs/2026-08-26-zig1-memory-refactor-roadmap.md` (status)
- Commit: `docs: memory refactor execution GATE + reconciliation`

**Interfaces:**
- Consumes: all prior tasks (incl. I-COMPACT's go/no-go); golden samples; roadmap + report.
- Produces: measured GATE evidence; roadmap status updated; acceptance confirmed.

- [ ] **Step 1: Full gate battery**

4 MD5 (keep-or-re-baseline with golden evidence); matrix 21/21; full corpus sweep vs **golden sample** (RUNTIME must match everywhere; byte-identity diffs documented) — 405 dirs = 330 mi_matrix (incl. W2-1 fixture `emission_global_alias_xmod`) + 21 z98 + 54 top-level repro; self-compile 0 errors; `--track-memory` self-compile `pool=` ≤ 16,384 K (or the S-series outcome + I-COMPACT verdict as the documented residual).

- [ ] **Step 2: Warning-clean confirmation**

`-Wall -Wextra -O3` on emitted compiler C (reference) AND zig1_5 emitted C (`gen/*.c`): **0 warnings, 0 errors** on BOTH. Report counts (reference via W-4; gen via W2-1..4).

- [ ] **Step 3: Reconcile docs**

EXPECTED_FAIL.md + QUICK_REF.md: new baseline paragraph (memory refactor GATE, newest-first); roadmap doc: mark items 0-7 DONE/skipped + measured deltas. Historical sections as snapshots (supersede, don't rewrite).

- [ ] **Step 4: Report + ledger + memory**

Report all gate evidence + reconciliation. Ledger + mnemoria (success/pattern).
