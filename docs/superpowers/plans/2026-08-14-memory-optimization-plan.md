# Compiler Memory Optimization (Waste Elimination) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Eliminate the ~2× copy-into-bump allocation waste across all 37 growable collections, fix the two self-compile blockers (scratch OOM + parser ASan overflow), and reclaim static BSS so zig1 self-compiles end-to-end under 16 MB.

**Architecture:** 13 fix-tasks interleaved by impact. Foundation first (token array, parser bug, shared primitives, hash maps), then the systematic sweep, then arena resize + gate sweep. Every fix is behavior-preserving (emitted C89 must stay byte-identical).

**Tech Stack:** Z98 compiler (`sf/src/*.zig`), compiler under test `/tmp/fx_subfolder/zig1`, arenas (`allocator.zig`), hash maps (`util/hash.zig`), `--track-memory --markers`, `--max-mem`.

## Global Constraints

- **Read `docs/sf/QUICK_REF.md` first** — the ⭐ SUBAGENT CHEAT-SHEET (lines 1-70) is MANDATORY. Copy exact commands. **Compiler under test is `/tmp/fx_subfolder/zig1`** (NOT `sf/build/out_release/zig1`; the release build script was redirected to `/tmp/fx_subfolder`).
- **`sf/build/out_release/` is WEDGED — any command touching it HANGS; NEVER touch/list/build into it. Use `timeout` on all risky commands.**
- **Output must stay byte-identical.** Every fix must preserve the emitted C89 exactly. The 4 MD5 gates are the regression guard; any MD5 change = regression (STOP).
- **Build:** `bash sf/scripts/build_release.sh` → gate line `=== [release] Done: /tmp/fx_subfolder/zig1 ===`. **The script wipes `/tmp/fx_subfolder/` (including `lib/`) — reinstall the std lib after every rebuild** before running examples/repros:
  `cp sf/src/std.zig sf/src/std_io.zig sf/src/std_arena.zig sf/src/std_net.zig /tmp/fx_subfolder/lib/`
- **Editing:** `edit`/`fastedit` only (AGENTS.md §X.7: re-read region before each edit, bottom-to-top). NO sed/python/bulk transforms.
- **Z98 constraints** (AGENTS.md §1.3): no anytype/@Type; concrete maps (`U32ToU32Map` etc.); `@intCast` for i32↔usize; no pointer captures; switch requires `else`; `std.debug.print` → `std.io.print(fmt, .{args})`.
- **The plan is the ONLY authority.** STOP on any issue. Every fix-task re-runs `--track-memory --markers` and reports the per-arena peak delta.
- **MD5 gate recipe:** single-file `--dump-c89` to stdout piped to `md5sum` (per F3). Baselines (unchanged since F3 AMENDMENT B, post-fallback-demotion HEAD `5c1e17e4`):
  - gol `9cf758d96f25d41980379564a5501bc8`
  - lisp `524d2872daefb2677c8ddc1ac8f34cf5`
  - json `066c99974f6052317636854dc4c2a2d5`
  - mud `a1d0dd55aada9c3fd904ae33f54de32e`
- **Baselines to preserve:** corpus 252 dirs `OK=246 / FAIL=2 / ICE=0 / CRASH=0 / GG=4` (FAIL=2 = `field_store_drop` + `self_embed_optional_cycle`); 21-example matrix 21/21; `test_analyzer_bin` PASS.
- **Self-compile gate (new, valid after Task 1+2):** `mkdir -p DIR && /tmp/fx_subfolder/zig1 --dump-c89 --output-dir DIR sf/src/main.zig` completes rc=0 (no OOM, no ASan crash).

---

### Task 1: F-TOKEN+F-SOURCE — two-pass token count + source read into perm (OOM closure)

> **AMENDMENT (operator ruling Option A, 2026-08-14):** Task 1 now ALSO includes F-SOURCE (read each module's source directly into perm, removing the scratch copy). Rationale: the actual token counts exceed the plan's ≤65,536 assumption — `c89_emit.zig` has **73,912 tokens**, `lower.zig` **79,606** — so an exact-size token array ALONE still leaves scratch at 2.02–2.16 MB > 2 MB. Removing the in-scratch source text closes the gap. The standalone Task 9 (F-SOURCE) is **absorbed** into this task.

**Files:**
- Modify: `sf/src/import_resolver.zig:16-81` (token array + `moduleRegistryParseModule`; `moduleRegistryResolveImports` readFile at `:96` reads into perm)
- Modify: `sf/src/lexer.zig` (add `count_only` mode: suppress diagnostics + interning + `string_buf` writes)
- Modify: `sf/src/source_manager.zig:75-101` (`sourceManagerAddFile` takes ownership of the perm-backed source; no scratch→perm copy)
- Modify (docs): `sf/docs/tech_docs/00_lexer_parser.md` + `sf/docs/tech_docs/00_shared_infra.md` (`[updated: 2026-08-14]`)
- Report: `.superpowers/sdd/task-F-TOKEN-report.md`

**Interfaces:**
- Consumes: current `tokenArrayEnsureCapacity`/`tokenArrayAppend` (`import_resolver.zig:16-32`), `lexerInit`/`lexerNextToken` (`lexer.zig`), `sourceManagerAddFile` (`source_manager.zig`), `pal.readFile` (`pal.zig`).
- Produces: (1) token array allocated at exact size (no doubling); (2) each module's source read directly into perm (no scratch copy). Combined, import scratch for the largest module (`c89_emit.zig`, 73,912 tokens) = exact token array (73,912 × 24 = 1,773,888 B) + `string_buf` (small) ≈ **1.78 MB < 2 MB cap — the scratch OOM is closed**. `Token` = 24 B (`token.zig:115-123`).

- [ ] **Step 1: Reproduce the RED scratch OOM (baseline)**

```bash
mkdir -p /tmp/ftok && timeout 120 /tmp/fx_subfolder/zig1 --dump-c89 --output-dir /tmp/ftok sf/src/c89_emit.zig 2>&1 | tail -3
```
Expected: `OOM: used=1919196 new=3492060 total=2097152` (rc=3). Record the exact numbers.

- [ ] **Step 2: Change the token array to exact-size via two-pass lexing**

The token array currently grows ×2 copy-into-bump inside `moduleRegistryParseModule` (`import_resolver.zig:39-47`). Replace the growth with a **two-pass** scheme: (1) a counting pass over the source that returns the token count without retaining tokens or emitting diagnostics; (2) `sandAlloc` the exact `count × 24` bytes; (3) the real lexing pass fills that array. The counting pass must NOT duplicate diagnostics (either a `count_only` lexer mode that suppresses interning + diagnostics, or a dry-scan). Concrete edit targets:

```zig
// import_resolver.zig — replace the tok_items growth loop in moduleRegistryParseModule
// with: count first, then allocate exact, then lex into it.
var token_count: usize = 0;
// PASS 1: count tokens (no allocation, no diagnostics)
var lex1 = lexer_mod.lexerInit(content, file_id, reg.interner, reg.diag, scratch);
while (true) {
    var t = lexer_mod.lexerNextToken(&lex1);
    token_count += 1;
    if (t.kind == TokenKind.eof) break;
}
// allocate exact-size token array
var raw = alloc_mod.sandAlloc(scratch, token_count * @intCast(usize, @sizeOf(Token)), @intCast(usize, 4)) catch |err| return null;
var tok_items = @ptrCast([*]Token, raw);
// PASS 2: real lex into the exact array
var lex2 = lexer_mod.lexerInit(content, file_id, reg.interner, reg.diag, scratch);
var tok_len: usize = 0;
while (true) {
    var t = lexer_mod.lexerNextToken(&lex2);
    tok_items[tok_len] = t;
    tok_len += 1;
    if (t.kind == TokenKind.eof) break;
}
```

The counting pass (PASS 1) must be a pure count. **IMPORTANT (from the first implementation attempt):** suppressing only SOME side effects is not enough — interning identifiers in PASS 1 (but not strings) changes the interner insertion order and shifts `string_id` values, breaking byte-identity (the `lisp` MD5). The `count_only` mode must suppress **ALL** of: diagnostics, interning (strings, identifiers, builtins), and `string_buf` writes. PASS 2 then performs every side effect in exactly the pre-change source order, keeping the output byte-identical. Verify no duplicate diagnostics by re-running the corpus (no new FAIL / no diagnostic-count change).

Then, **read the source directly into perm** instead of scratch: in `moduleRegistryResolveImports` (`import_resolver.zig:96`), change `pal.readFile(path_s, scratch)` to read into the perm arena; `sourceManagerAddFile` (`source_manager.zig:75-101`) should take ownership of the perm-backed buffer (not re-copy). `content` remains a valid slice (perm is retained), and the lexer/parser are arena-agnostic (they take `[]const u8`). This removes the 345–349 KB scratch transient — the residual that pushed exact-size tokens over the 2 MB cap.

- [ ] **Step 3: Rebuild + verify the OOM is gone**

```bash
bash sf/scripts/build_release.sh 2>&1 | tail -2
cp sf/src/std.zig sf/src/std_io.zig sf/src/std_arena.zig sf/src/std_net.zig /tmp/fx_subfolder/lib/
mkdir -p /tmp/ftok2 && timeout 120 /tmp/fx_subfolder/zig1 --dump-c89 --output-dir /tmp/ftok2 sf/src/c89_emit.zig 2>&1 | tail -3
```
Expected: no `OOM` (the exact-size token array + perm source now fits under 2 MB). The compile may proceed to hit the parser ASan bug (on modules with >64-field unions/enums) — that is Task 2, out of this task's gate; the scratch OOM on c89_emit/lower must be GONE (grep the output for `OOM:`).

- [ ] **Step 4: Gate — byte-identity + peak reduction**

Run the 4 MD5 gates (byte-identical) + corpus 252 (no change) + `--track-memory --markers` on `examples/z98/rogue_mud/main.zig` (import scratch peak should DROP; record the delta). All must match baselines.

- [ ] **Step 5: Commit**

```bash
git add sf/src/import_resolver.zig sf/src/lexer.zig sf/src/source_manager.zig sf/docs/tech_docs/00_lexer_parser.md sf/docs/tech_docs/00_shared_infra.md
git commit -m "fix: two-pass token count + source into perm closes scratch OOM (F-TOKEN+F-SOURCE)"
```

**Gate:** c89_emit/lower standalone no longer OOM scratch; 4 MD5s byte-identical; corpus 252 unchanged; rogue_mud import scratch peak reduced.

---

### Task 2-I: Investigate the growable parser arena design

> **AMENDMENT (operator ruling, 2026-08-14, third):** Task 2 is high-difficulty, so it is split into **2-I (investigate + design)** then **2-F (implement)**. The intended design (operator-approved) is the target the investigation must ground:
> - The parser arena becomes a **segmented bump arena** — starts at a small segment (4 KB); on overflow it allocates a **double-size segment** (4→8→16→32 KB…) **bump-allocated from the module arena** (8 MB, has headroom); old segments stay live (no copy → no dangling pointers). No fixed cap — grows until the module arena is genuinely exhausted (a real reported OOM).
> - **Growth warnings:** a reusable helper `arenaGrew(name, old, new)` writes `arena <name>: grew <old> -> <new>` to stderr, gated behind `--track-memory --markers` (byte-identity safe). Fires on every segment doubling. Reusable primitive for Tasks 3–8.
> - **`span_len` u16 → u32** at `sf/src/ast.zig:290` (+ sibling span fields) so a 345 KB module's spans never overflow (removes the `c89_emit` `PANIC: integer overflow`).
> - The three static arenas (14 MB BSS) still sum well UNDER 16 MB; F-RESIZE (Task 12) shrinks them — nothing grows any arena toward 16 MB.

**Files:**
- Investigate (read-only): `sf/src/allocator.zig` (Sand arena machinery `:1-65`), `sf/src/import_resolver.zig` (`moduleRegistryParseModule` `:34-81`, `p_arena_buf` `:39-50`), `sf/src/parser.zig` (every `sandAlloc`/`sandReset`/`.start`/`.pos`/`.end` + `parserPushU32`), `sf/src/ast.zig` (Span struct, `span_len` `:290`, `@sizeOf(AstNode)`)
- Modify (docs): none (investigation)
- Report: `.superpowers/sdd/task-2-I-growable-arena-report.md`

**Interfaces:**
- Consumes: `Sand` (`allocator.zig:1-7`), `sandAlloc`/`sandReset`/`sandReallocInPlace` (`allocator.zig:26-65`), parser arena `&p_arena` (`import_resolver.zig:48-50`), `parserPushU32` (committed in `672e65d7`), module arena (`ctx.alloc.module`).
- Produces: a concrete, file:line-grounded design for the segmented growable parser arena that keeps the parser's existing `*Sand` interface working, the `arenaGrew` helper spec, and the `span_len` u16→u32 widening plan.

- [ ] **Step 1: Map the parser-arena contract**

Read `parser.zig` + `import_resolver.zig` and catalog EVERY use of the parser's arena: each `sandAlloc`, `sandReset`, `sandResetPeak`, `sandReallocInPlace`, and every direct `.start`/`.pos`/`.end` read/write, plus anything that holds a pointer/slice into the arena across an allocation. This is the contract the growable arena must satisfy (esp. any pointer that would dangle on a segment switch).

- [ ] **Step 2: Design the segmented growable arena**

Specify: the growable arena struct shape (segment chain + current-segment `Sand` view); how `moduleRegistryParseModule` constructs it (first segment 4 KB, backed by the module arena); the overflow path (alloc double-size segment, `arenaGrew`, switch the active `Sand`, old segments live); `sandReset` semantics (return to first segment, pos=0); interaction with `parserPushU32` and `sandReallocInPlace`. Flag any invariant a segment switch would break (pointer held across alloc) and how to preserve it.

- [ ] **Step 3: Assess the `span_len` u16→u32 widening**

Locate `span_len` and all sibling span fields (`ast.zig` Span struct, `ast.zig:290`). Compute what widening does to `@sizeOf(AstNode)`/`@sizeOf(Span)` (must stay 24 B / intended layout — check for padding). Verify u32 is sufficient for a 345 KB module (it is) and confirm no OTHER `u16` span field can overflow.

- [ ] **Step 4: Spec `arenaGrew`**

Placement in `allocator.zig`, signature, the `pal.markerWrite` gating (`--markers`), and a confirmation it is stderr-only (byte-identity-safe). Where exactly the call goes in the doubling path.

- [ ] **Step 5: Write the F-task implementation plan + flag design forks**

List the exact files/lines the F-task will change, ordered. If any design fork emerges (e.g. segment-switch breaks an invariant and needs a different approach), write it up for the operator ruling at the STOP.

**Gate:** investigation report with the complete arena contract, the growable-arena design, the span_len plan, the `arenaGrew` spec, and an F-task plan; **zero source changes**.

---

### Task 2-F: Implement the growable parser arena + arenaGrew + span_len u16→u32 + block child-buffer fix

> Consumes the Task 2-I design. **Operator rulings (binding):** FORK A = option **1** (accept `@sizeOf(AstNode)` **28 B**; update `ast_tests.zig:50` assert 24→28 + `zzz_astnode_sz` docstring `ast.zig:113`); FORK B = **A2** (grow-aware `sandAlloc` via `Sand.growable` hook — parser.zig unchanged); **reuse** ONE `GrowableSand` across modules (reset per module). **ADDED to scope:** fix the latent **block child-buffer bug** at `parser.zig:1803` (`self.child_buf_items[0..local_len]` reads enclosing-scope entries when nested; should be `[saved_len .. saved_len+k]`). The fixed `[64]u32` growable field buffers are already committed (`672e65d7`, `parserPushU32`).

**Files:**
- Modify: `sf/src/allocator.zig` (segmented growable arena via `Sand.growable` hook + `arenaGrew`)
- Modify: `sf/src/import_resolver.zig` (wire `moduleRegistryParseModule` to ONE reused growable parser arena; reset per module)
- Modify: `sf/src/parser.zig` (fix block child-buffer bug `:1803`; verify `parserPushU32` unchanged)
- Modify: `sf/src/ast.zig:106,270,290,113` (`span_len` u16 → u32; update `zzz_astnode_sz` to 28 B)
- Modify: `sf/src/tests/ast_tests.zig:50` (assert `@sizeOf(AstNode) == 28`)
- Modify (docs): `sf/docs/tech_docs/00_lexer_parser.md` + `sf/docs/tech_docs/00_shared_infra.md` (`[updated: 2026-08-14]`)
- Report: `.superpowers/sdd/task-F-PARSER-report.md`

**Interfaces:**
- Consumes: Task 2-I design; `parserPushU32` (`672e65d7`); module arena for backing segments.
- Produces: parser arena has NO fixed cap (segmented growable, module-arena-backed, doubles + `arenaGrew`); `span_len` widened to u32 (`@sizeOf(AstNode)` = 28 B); block child-buffer bug fixed; no ASan / no parser-arena OOM / no span_len PANIC. Byte-identical.

- [ ] **Step 1: Reproduce the baselines (ASan overflow + parser-arena OOM + span_len PANIC)**

```bash
mkdir -p /tmp/fp && timeout 120 /tmp/fx_subfolder/zig1 --dump-c89 --output-dir /tmp/fp sf/src/ast.zig 2>&1 | tail -5
timeout 120 /tmp/fx_subfolder/zig1 --dump-c89 --output-dir /tmp/fp2 sf/src/c89_emit.zig 2>&1 | grep -E "OOM:|PANIC:"
timeout 120 /tmp/fx_subfolder/zig1 --dump-c89 --output-dir /tmp/fp3 sf/src/lower.zig 2>&1 | grep -E "OOM:|PANIC:"
```
Record all baseline messages.

- [ ] **Step 2: Implement the segmented growable parser arena per the 2-I design (A2: `Sand.growable` hook; ONE reused arena, reset per module)** — allocator.zig + import_resolver.zig.
- [ ] **Step 3: Add `arenaGrew` and wire it into the doubling path** (stderr-only, `--markers`-gated).
- [ ] **Step 4: Widen `span_len` u16 → u32** (`ast.zig:106,270,290`), update `zzz_astnode_sz` (`ast.zig:113`) to the 28 B layout, and update `ast_tests.zig:50` to 28.
- [ ] **Step 5: Fix the block child-buffer bug** at `parser.zig:1803`: replace `self.child_buf_items[0..local_len]` with the correct `[saved_len .. saved_len+local_len]` slice so nested >64-statement blocks get their OWN children, not enclosing-scope entries.
- [ ] **Step 6: Rebuild + verify**

Rebuild (`bash sf/scripts/build_release.sh` → gate `=== [release] Done: /tmp/fx_subfolder/zig1 ===`), reinstall std lib. Verify: no ASan on `ast.zig`/`parser.zig`/`main.zig`; no parser-arena `total=4096`/`total=16384` OOM on `c89_emit`/`lower`; no `span_len` PANIC; `--track-memory --markers` on `lower.zig`/`c89_emit.zig` shows `arena … grew …` lines; 4 MD5 gates byte-identical; corpus 252 unchanged; self-compile (`main.zig`) rc=0 (now expected to complete — the module-arena headroom arbiter for the +1.8 MB AstNode widening).

- [ ] **Step 7: Commit**

```bash
git add sf/src/allocator.zig sf/src/import_resolver.zig sf/src/parser.zig sf/src/ast.zig sf/src/tests/ast_tests.zig sf/docs/tech_docs/00_lexer_parser.md sf/docs/tech_docs/00_shared_infra.md
git commit -m "fix: growable parser arena + arenaGrew warnings + span_len u16->u32 + block child-buffer bug"
```

**Gate:** no ASan crash; no parser-arena `total=4096`/`total=16384` OOM on `c89_emit`/`lower`; no `span_len` PANIC; `arena … grew …` warnings visible under `--track-memory --markers`; `@sizeOf(AstNode)` = 28 B; block child-buffer bug fixed; 4 MD5s byte-identical; corpus 252 unchanged. **SELF-COMPILE rc=0 IS DEFERRED (amendment, 2026-08-14):** self-compile is NOT yet achievable due to two underlying issues now examined in their own task families — (a) AST duplication from unnormalized import paths (F-PATHNORM-{Feas,Inv,Fix}), (b) parser value-position `if (opt) |cap| expr else expr` gap (F-PARSERGAP-{Feas,Inv,Fix}). Subsequent F-tasks (F-AST, F-LIR, F-HASHMAP, F-SWEEP, F-DEADCODE, F-RESIZE) are **NOT blocked** by the deferred self-compile gate — their optimizations remain wanted.

---

### Task 3: Unified growable arena pool (replace the 5 fixed buffers)

> **AMENDMENT (operator long-term ruling, 2026-08-14):** this task REPLACES the old F-PRIMITIVES task. The five fixed buffers (`perm_arena_buf[4M]`, `mod_arena_buf[8M]`, `scr_arena_buf[2M]`, `type_db_buf[128K]`, `p_arena_buf[4K/16K]`) are unified into **ONE static growable pool**. This is the durable fix for the "fixed-cap OOM unmasked by the previous fix" pattern.

**Design (operator-approved):**
- One static BSS buffer `memory_pool_buf: [POOL_SIZE]u8` (POOL_SIZE ≈ 10 MiB; sized by measurement in Task 12).
- The pool is a **monotonic bump `Sand`** (never reset) that hands out segments.
- Each of the 5 arenas becomes a `GrowableSand` (segment chain, first segment 4 KB, double on overflow, old segments live) whose `backing` is the pool. The existing `Sand.growable` hook (A2, built in Task 2-F) makes `sandAlloc` grow transparently, so `ctx.alloc.perm/module/scratch` stay `Sand` with `.growable` set — **the whole codebase's `*Sand` usage is untouched**.
- `arenaGrew` fires per doubling (already built); `checkCombinedPeak` becomes a **pool-level peak check** (the pool's high-water vs POOL_SIZE), which is what "16 MB budget" means as a soft, warned, tracked limit.
- **No fixed per-arena cap remains.** The `p_arena_buf` stack buffer (Task 2-F) is superseded — the parser arena's `GrowableSand` is now pool-backed too.

**Files:**
- Modify: `sf/src/allocator.zig` (add `memory_pool_buf` + `pool` Sand; convert `initCompilerAlloc` to build 3 growable tier arenas backed by the pool; add `sandTryReallocInPlace` end-check; pool-level peak check)
- Modify: `sf/src/main.zig` (`type_db_buf[131072]` → growable, pool-backed; `initCompilerAlloc` call site; `--track-memory` reports pool usage + type_db)
- Modify: `sf/src/import_resolver.zig` (parser `GrowableSand` backing → the pool, not the module arena)
- Modify (docs): `sf/docs/tech_docs/00_shared_infra.md` (arena → pool rewrite) + `00_lexer_parser.md` (span_len 28 B + growable parser arena notes, `[updated: 2026-08-14]`)
- Report: `.superpowers/sdd/task-F-POOL-report.md`

**Interfaces:**
- Consumes: `GrowableSand`/`sandAlloc` growable hook + `arenaGrew` (Task 2-F); `Sand`/`sandInit`/`sandReset`/`sandReallocInPlace`.
- Produces: one pool with 5 growable segmented arenas; `sandTryReallocInPlace` (tail-guarded); pool-level peak check; `--track-memory` reports pool peak. NO fixed arena cap remains.

- [ ] **Step 1: Add `sandTryReallocInPlace` (tail-guarded) + the pool**

In `allocator.zig`: (a) add `sandTryReallocInPlace` (returns the pointer when `old_ptr+old_size == sand.start+sand.pos` AND growth fits in `sand.end`, else null — fixes the existing `sandReallocInPlace` missing end-check); (b) add `memory_pool_buf: [POOL_SIZE]u8` + a `pool: Sand` monotonic bump over it; (c) `initCompilerAlloc` builds the 3 tier arenas as growable (`GrowableSand` backed by `pool`) and returns their `Sand` views with `.growable` set.

- [ ] **Step 2: Convert `type_db` + parser arena to pool-backed growable**

In `main.zig`, replace `type_db_buf[131072]` with a `GrowableSand` backed by the pool (its `*Sand` view is what `typeRegistryInit` receives). In `import_resolver.zig`, change the parser `GrowableSand` backing from `module_arena` to the pool.

- [ ] **Step 3: Pool-level peak check + `--track-memory`**

Rewrite `checkCombinedPeak` to check the pool's high-water against POOL_SIZE (and keep the soft `pal.exit(1)` on overflow). Extend `--track-memory` (`main.zig:239-258`) to also print `pool=XK` (and `type_db=XK`).

- [ ] **Step 4: Rebuild + verify byte-identity + no fixed-cap OOM**

Rebuild (`build_release.sh` → gate `=== [release] Done ===`), reinstall std lib. Verify: 4 MD5 gates byte-identical; corpus 252 unchanged; **self-compile (`main.zig`) rc=0** (the pool removes the 8 MB module cap, absorbing the +1.8 MB AstNode widening); `--track-memory --markers` on self-compile shows `pool=…` and `arena … grew …` warnings.

- [ ] **Step 5: Commit**

```bash
git add sf/src/allocator.zig sf/src/main.zig sf/src/import_resolver.zig sf/docs/tech_docs/00_shared_infra.md sf/docs/tech_docs/00_lexer_parser.md
git commit -m "feat: unified growable arena pool (no fixed per-arena caps)"
```

**Gate:** 4 MD5s byte-identical; corpus 252 unchanged; self-compile rc=0; `--track-memory --markers` shows `pool=XK` + `arena … grew …`; `sandTryReallocInPlace` has call sites; no fixed arena cap remains (grep: `arena_buf` gone).
---
### Task 3b-I: Investigate the module-arena 64 MB (dump AST representation)

> **AMENDMENT (operator ruling, 2026-08-14):** self-compile's module arena genuinely needs ~64 MB live for 24,790 lines (I-M3's ~7.3 MB projection was wrong). The 16 MB target **cannot** be reconsidered, so this investigation determines whether the AST is pathologically large (duplication/over-retention) or genuinely large — and what can be done. Uses I/O dumps of the AST representation to quantify.

**Files:**
- Investigate (read-only): `sf/src/ast.zig` (AstStore arrays), `sf/src/import_resolver.zig` (per-module parse into shared store), `sf/src/main.zig` (module arena wiring), `sf/src/type_resolver.zig`/`resolved_type_table.zig`/`coercion.zig`/`lir.zig` (other module-arena consumers), `sf/src/c89_emit.zig`/`semantic_analyzer.zig` (large modules)
- Modify (docs): none (investigation)
- Report: `.superpowers/sdd/task-3b-I-modulearena-report.md`

**Interfaces:**
- Consumes: the pool-backed module arena (Task 3); measured 64 MB live / 128 MB chain.
- Produces: a per-array decomposition of the module arena (AST nodes / extra_children / identifiers / string_values / int_values / float_values / fn_protos / resolved types / coercion / lir_fns / maps), a per-module accumulation breakdown, and a verdict: pathology (duplication/leak) vs genuine.

- [ ] **Step 1: Decompose the module arena per array**

Read `ast.zig` (AstStore: `nodes`, `extra_children`, `identifiers`, `string_values`, `int_values`, `float_values`, `fn_protos` sizes/counts) and the other module-arena consumers. Compute each array's element size × count for self-compile (37 modules, 24,790 lines). Use `--dump-ast` (if it emits node counts) or instrument via `pal.stderr_write` markers to print `AstStore` array lengths at end of import / end of compile.

- [ ] **Step 2: Measure per-module accumulation**

Determine how much each module adds (nodes appended, extra_children, identifiers interned). Compile a handful of representative modules and record the delta. Check for **duplication**: is any module's AST added more than once, or is shared data (e.g. identifiers/string values) copied per-module instead of referenced?

- [ ] **Step 3: Quantify the waste split**

Split the 64 MB into: live AST nodes (28 B × count), extra_children, side arrays, resolved types/maps, and the 2× copy-into-bump dead copies. Which is dominant?

- [ ] **Step 4: Produce reduction options**

For each dominant component, state concrete reduction paths (e.g. node-count reduction, side-array dedup, interning of shared spans, streaming/on-demand module AST so the module arena resets per phase, node packing below 28 B). Rank by (saving ÷ complexity) and flag whether any makes 16 MB achievable for self-compile.

- [ ] **Step 5: Write the report** `.superpowers/sdd/task-3b-I-modulearena-report.md` + STOP for operator ruling (what to build next: a targeted fix vs an AST-representation redesign).

**Gate:** per-array decomposition, per-module accumulation, waste split, ranked reduction options, and a pathology-vs-genuine verdict; zero source changes.

---
### F-PATHNORM-Feas: Feasibility — path normalization fixes AST duplication

> **AMENDMENT (operator ruling, 2026-08-14):** reduce AST duplications FIRST (before F-AST). Investigation 3b-I found self-compile's module arena is ~69.6 MB of which AST store = 57.7 MB live with **nodes 88% duplicated**: `joinPath` (`module_registry.zig:109-119`) keeps `..`/`.` in resolved paths, so the same physical file is interned under multiple path strings → the path-based dedup fails → 1272 module entries parse 37 physical files (34.4× avg, 109× max) → each re-parse appends a full AST copy to the shared store. Genuine single-parse AstStore ≈ 5.0 MB (11.4× inflation).

**Files:**
- Investigate (read-only): `sf/src/module_registry.zig:109-119` (`joinPath`/`appendZigExt`), resolver path-intern + dedup (`module_registry.zig`, `import_resolver.zig`), `sf/src/string_interner.zig`
- Modify (docs): none
- Report: `.superpowers/sdd/F-PATHNORM-Feas-report.md`

- [ ] **Step 1: Confirm the root cause** — trace how a physical file gets multiple path strings (e.g. `a/../b.zig` vs `b.zig` vs `./b.zig`) and that module dedup keys on the un-normalized string. Reproduce the duplication count (1272 entries / 37 files).
- [ ] **Step 2: Confirm the fix direction** — verify that normalizing `..`/`.` before interning makes dedup succeed → each physical file parsed once → AST store → ~5-6 MB.
- [ ] **Step 3: Pin the locus** — exactly where normalization must happen (joinPath, the resolver's path interning, or a shared util) and any edge cases (absolute vs relative, trailing slashes, `..` beyond root).
- [ ] **Step 4: Write the report** (confirmed/refuted, go/no-go, scope) + feed F-PATHNORM-Inv.

**Gate:** root cause confirmed, fix direction validated, precise locus + edge cases identified; zero source changes.

---

### F-PATHNORM-Repro: Repro — AST duplication from un-normalized import paths

> **AMENDMENT (operator directive, 2026-08-15):** after Feas, create a self-contained repro of the AST-duplication defect so the fix is observable WITHOUT the full-blown self-compile (avoids scope creep + the 1 GiB temp-pool dependency). F-PATHNORM-Inv/Fix validate on this repro + corpus + 4 MD5 gates instead of full self-compile.

**Files:**
- Create: `repro/mi_matrix/pathnorm_dup_xmod/{main.zig, mod.zig, sub/mod2.zig, NOTES.md}` — small multi-module fixture with a mutual `..` import cycle mirroring the self-compile pattern (lexer.zig ↔ tests/lexer_tests.zig) at reduced scale
- Report: `.superpowers/sdd/F-PATHNORM-Repro-report.md`

- [ ] **Step 1: Create the fixture** — `main.zig` imports `mod.zig`; `mod.zig` imports `sub/mod2.zig`; `sub/mod2.zig` imports `../mod.zig`. The `..` cycle compounds `sub/../` prefixes per layer, so `mod.zig` and `sub/mod2.zig` are re-registered/re-parsed many times (each layer = a new un-normalized path string → a new module entry). Keep std out of the import chain so the repro is self-contained; `main.zig` may use `std.io.print` (installed canonical lib) if output is wanted.
- [ ] **Step 2: RED — observe the duplication** — run the repro through the compiler under test (`/tmp/fx_subfolder/zig1`, dump + gcc + run per QUICK_REF). Observe module entries >> 2 physical files using the committed `--markers` instrumentation (import parse markers, `IRP:m` at `import_resolver.zig:111`) and/or the emitted per-module C unit count, and record `--track-memory` module-arena figure.
- [ ] **Step 3: Record the baseline** — exact observed numbers (parse-marker count, module entries, emitted units, module arena) into `NOTES.md` + report, matching the corpus two-state-gate convention.
- [ ] **Step 4: Commit** (`git add` the repro dir only; message `repro: AST duplication from un-normalized import paths (pathnorm)`).

**Gate:** repro exists under `repro/mi_matrix/pathnorm_dup_xmod/`; RED shows duplication (module entries / parse markers >> 2 physical files); numbers recorded in NOTES.md; commit contains only the repro dir.

---

### F-PATHNORM-Inv: Investigation — shared path-normalization utility

**Files:**
- Investigate (read-only): all path-string handling in `sf/src/*.zig` (grep `joinPath`, `appendZigExt`, `readFile`, path interning, `@import`/`@cInclude` resolution, module dedup keys), plus `sf/src/module_registry.zig` and any `util/` candidates
- Modify (docs): none
- Report: `.superpowers/sdd/F-PATHNORM-Inv-report.md`

**Interfaces:**
- Consumes: F-PATHNORM-Feas findings.
- Produces: a designed **shared path-normalization utility** (name, signature, normalization rules) + all call sites that should use it + a content-hash double-guard design.

> **AMENDMENT (operator directive, 2026-08-15):** besides path-string dedup, investigate a **content-hash double-guard** — hash each parsed module's content and store it, so the compiler can detect a module was already parsed even when path normalization misses it (e.g. symlink/realpath aliases, absolute vs relative root paths, or future path spellings). Produce a design for this guard (where the hash is computed, where stored, when compared, cost, and how it interacts with the path-id dedup).
- [ ] **Step 1: Survey all path-string consumers** — every place that builds, compares, interns, or dedups a path (`joinPath` :109-119, `appendZigExt` :131, resolver import resolution, source-manager file ids, `pal.readFile`). Note where `..`/`.` would break dedup or equality.
- [ ] **Step 2: Design the shared utility** — e.g. `util/path.zig` `normalizePath(buf, []const u8) []const u8` (resolve `.`/`..`, collapse `//`, keep leading `/` or drive-letter, trim trailing `/`). State the exact normalization rules.
- [ ] **Step 3: Enumerate call sites** — which consumers switch to the utility, and whether any other compiler part (not just import) needs it (search for path-equality/dedup beyond module_registry).
- [ ] **Step 4: Write the report** (utility design + rules + full call-site list).

**Gate:** shared utility designed with exact rules; all path consumers + dedup sites enumerated; zero source changes.

---

### F-PATHNORM-Fix: Implement — normalize import paths (dedup → no AST duplication)

**Files:**
- Modify: `sf/src/util/path.zig` (create, per F-PATHNORM-Inv design) + `sf/src/module_registry.zig` (joinPath/resolver use the utility) + any other call sites per F-PATHNORM-Inv
- Modify (docs): `sf/docs/tech_docs/01_import_resolution.md` (`[updated: 2026-08-14]`)
- Report: `.superpowers/sdd/F-PATHNORM-Fix-report.md`

> **AMENDMENT (operator ruling, 2026-08-15):** Fix implements BOTH the path-normalization utility AND the content-hash double-guard (directive). **Hash site = RESOLVE-TIME (Option 2, operator choice):** hash each module's source content at import-resolution time — BEFORE the module entry is created — via a `content_to_id: U32ToU32Map` hashmap on ModuleRegistry keyed by the `fnv1a` (u32, `util/hash.zig`) content hash; if the hash is already seen, REUSE the existing module id (skip creating/parsing a duplicate) — no edge-redirect/merge/neuter machinery needed. The hashmap makes recall trivial. Rationale (operator): loop-time hashing would burden every alias with an extra readFile just to check a hash that could be reused; resolve-time avoids it.

**Interfaces:**
- Consumes: F-PATHNORM-Inv utility + content-hash guard design.
- Produces: normalized paths used everywhere paths are interned/deduped → each physical file parsed once; content-hash dedup (resolve-time) reuses already-parsed modules across path aliases.

- [ ] **Step 1: Implement the shared utility** (per the design) + wire it into `joinPath`/resolver and all enumerated call sites.
- [ ] **Step 1b: Implement the resolve-time content-hash double-guard** — `content_to_id: U32ToU32Map` on ModuleRegistry, `fnv1a` hash of module source at import-resolution (before entry creation), reuse existing module id when hash already seen. No merge/neuter machinery.
- [ ] **Step 2: Rebuild + verify** — `bash sf/scripts/build_release.sh` → gate `=== [release] Done ===`; reinstall std lib.
- [ ] **Step 3: Gate** — 4 MD5 gates byte-identical; corpus 252 unchanged; **self-compile module arena drops ~69.6 MB → ~6 MB** (`--track-memory --markers` on `sf/src/main.zig` shows the module arena no longer ballooning; module entries ≈ 37, not 1272); **repro `pathnorm_dup_xmod` dedups** (parse markers / emitted units ≈ 6 = 3 fixture + 3 std, not 147; still prints 12).
- [ ] **Step 4: Commit** (`git add` the touched files; message `fix: normalize import paths + content-hash module dedup (eliminate AST duplication)`)

**Gate:** 4 MD5s byte-identical; corpus 252 unchanged; self-compile module arena → ~6 MB (dedup works); repro `pathnorm_dup_xmod` parses/units collapse to ~6.

---

### Task 4: F-AST — pre-size AST store (module arena)

**Files:**
- Modify: `sf/src/ast.zig:127-210` (append helpers for `nodes`, `extra_children`, `identifiers`, `string_values`, `int_values`, `float_values`, `fn_protos`)
- Modify: `sf/src/import_resolver.zig` (or wherever AST store is initialized) to pre-size `nodes`/`extra_children` from a line-count heuristic.
- Modify (docs): `sf/docs/tech_docs/00_lexer_parser.md` (`[updated: 2026-08-14]`)
- Report: `.superpowers/sdd/task-F-AST-report.md`

**Interfaces:**
- Consumes: `AstStore` (`ast.zig:101-210`), `astStoreEnsureCapacity`-style helpers.
- Produces: AST `nodes`/`extra_children` allocated with a near-final pre-size, eliminating most of the ~2× module-arena waste.

> **AMENDMENT (operator ruling, 2026-08-15):** Task 4 delivered + accepted with two deviations (runtime-gate verified: 21/21 examples runtime-identical; self-compile module arena top 16M→8M): (1) **heuristic = token count** (nodes ×0.6/token, extra_children ×0.25/token) instead of line-count — calibrated because nodes/token is stable (0.51–0.55) while nodes/line varies 2× (3.8–6.6); line-based ×12 measured a REGRESSION (rogue 506K→966K). (2) **`moduleScanDiscover`** (import_resolver.zig:27): side-effect-free closure pre-scan (each file lexed once, O(tokens+imports), no module creation, no interner/path_to_id writes) to learn the closure token total, since the shared store's first grow point only knows module[0]'s count. Measured: rogue_mud `mod=` 506K→370K (−27%), corpus 253 unchanged, 4 MD5s byte-identical.

- [ ] **Step 1: Record the module-arena baseline**

Run `--track-memory --markers` on `examples/z98/rogue_mud/main.zig`; record `mod=` peak (I-M1 measured 803K for rogue_mud).

- [ ] **Step 2: Pre-size the AST store**

In `astStoreEnsureCapacity` (or the append entry points), when growing from cap 0, pre-size to a heuristic (e.g. `nodes` cap = line_count × 4; `extra_children` cap = line_count × 8). The line count is available from `content` (already read). Use the exact-size/in-place helpers from Task 3 where the array is arena-tail.

- [ ] **Step 3: Rebuild + verify byte-identity + module peak reduction**

Rebuild + reinstall std lib. 4 MD5s byte-identical; corpus 252 unchanged; `--track-memory` on rogue_mud shows reduced `mod=` peak.

- [ ] **Step 4: Commit**

```bash
git add sf/src/ast.zig sf/src/import_resolver.zig sf/docs/tech_docs/00_lexer_parser.md
git commit -m "fix: pre-size AST store nodes/extra_children (module arena waste)"
```

**Gate:** 4 MD5s byte-identical; corpus 252 unchanged; rogue_mud `mod=` peak reduced.

---

### Task 5: F-LIR — per-function LIR scratch reset

**Files:**
- Modify: `sf/src/lower.zig:5197-5200` (where `lir_fns`/per-fn LIR is allocated), `sf/src/main.zig:567` (LIR phase scratch reset)
- Modify (docs): `sf/docs/tech_docs/07_lir_lowering.md` (`[updated: 2026-08-14]`)
- Report: `.superpowers/sdd/task-F-LIR-report.md`

**Interfaces:**
- Consumes: `LirFunction` lists (`lir.zig:120-308`), `lowerFn` (`lower.zig`), scratch arena (`self.alloc` = scratch, `main.zig:621`).
- Produces: scratch reset between functions (not just per phase), bounding the LIR `insts`/`blocks`/`hoisted_temps` leak (~0.5–1 MB).

> **AMENDMENT (operator ruling, 2026-08-15):** Task 5 delivered + accepted with a mechanism deviation: the brief's simple per-function `sandReset` is UNSAFE because `lir_fns` stores a shallow by-value struct copy (lists stay in scratch) and `phase_C89Emission` reads the scratch-resident LIR later. Implemented `lirFunctionRelocateToModule` (lir.zig): deep module-arena copy of all 5 lists (insts, blocks, params, hoisted_temps, switch_cases) capacity-exactly + per-function `sandReset`. Verified: 4 MD5s byte-identical, corpus 253 unchanged, rogue_mud `scr=` 511K→127K (pool 3759K→3247K), lisp 422K→63K (pool 1930K→1674K), ASan clean.

- [ ] **Step 1: Locate the per-function LIR allocation site**

Read `lower.zig:5197-5200` and `lir.zig:120-308`. Confirm the per-function LIR lists (`insts`, `blocks`, `params`, `hoisted_temps`, `switch_cases`) are allocated into the scratch arena and only reset per phase (`main.zig:567`).

- [ ] **Step 2: Reset scratch per function**

After a function's LIR is copied into the module-arena `lir_fns` (as pointers/indices — confirm the copy), `sandReset(scratch)` (or `sandResetPeak`) before lowering the next function. The function's LIR must already be module-resident or fully emitted before the reset. Preserve emitted-C byte-identity.

- [ ] **Step 3: Rebuild + verify byte-identity + scratch peak reduction**

4 MD5s byte-identical; corpus 252 unchanged; `--track-memory` on rogue_mud/lisp shows reduced later-phase `scr=` peak.

- [ ] **Step 4: Commit**

```bash
git add sf/src/lower.zig sf/src/main.zig sf/docs/tech_docs/07_lir_lowering.md
git commit -m "fix: per-function LIR scratch reset bounds later-phase scratch peak"
```

**Gate:** 4 MD5s byte-identical; corpus 252 unchanged; later-phase scratch peak reduced.

---

### Task 6-I: F-HASHMAP investigate — enumerate map init sites + hint availability

> **AMENDMENT (operator ruling, 2026-08-15):** Task 6 split into 6-I (investigate) + 6-F (implement) for scope control.

**Files:**
- Investigate (read-only): `sf/src/util/hash.zig` (map API: init/InitCap/grow/in-place), every map init site in `sf/src/`
- Modify (docs): none
- Report: `.superpowers/sdd/task-F-HASHMAP-I-report.md`

**Interfaces:**
- Consumes: Task 3 helpers (`u32ToU32MapInitCap`, in-place grow) — confirm exact names/signatures in `util/hash.zig`.
- Produces: a complete enumeration of every map init site in `sf/src/`, each with (a) map type, (b) file:line, (c) whether an expected-size hint is available at init, (d) the hint source/derivation, (e) pre-size candidate Y/N + risk note.

- [ ] **Step 1: Read `util/hash.zig`** — confirm the map types (U32ToU32Map, U64ToU32Map, U32ToU64Map, any others), the init/cap/grow API added in Task 3 (`...MapInitCap`, in-place grow path), and the growth/waste mechanics.
- [ ] **Step 2: Enumerate all map init sites** — grep `sf/src/` for every map init (`u32ToU32MapInit`, `u64ToU32MapInit`, `u32ToU64MapInit`, and any others). Record each: map type, file:line, containing struct (if any), arena it allocates from.
- [ ] **Step 3: Determine hint availability per site** — for each init site, whether an expected-size hint exists at init time (map size bounds from data already known: token count, module count, symbol count, string count, type count, resolved-type count, etc.). Derive the hint source precisely.
- [ ] **Step 4: Flag order-safety risks** — for each pre-size candidate, whether the map's slot layout / iteration order is observable in emitted C89 (if pre-sizing could change emitted output, flag it as a byte-identity risk to skip or verify).
- [ ] **Step 5: Write the report** — full enumeration table + recommendation of which sites 6-F should convert to `...MapInitCap`, which must NOT be touched (order-safety or no hint), and expected peak savings.

**Gate:** complete map-init-site enumeration with hint availability + order-safety flags; zero source changes.

---

### Task 6-F: F-HASHMAP implement — pre-size maps where a hint exists

**Files:**
- Modify: `sf/src/util/hash.zig` (ADD `...MapInitCap(alloc, hint)` — capacity-hint init allocating all 3 arrays at once) + the ~6 direct pre-size candidate call sites per the 6-I enumeration (keyword_set, emitted_type_set, fwd_decl_set, lfwd, lemit, pointer_only_map, cinclude seen; exact set from 6-I report)
- Modify (docs): `sf/docs/tech_docs/00_shared_infra.md` (`[updated: 2026-08-14]`)
- Report: `.superpowers/sdd/task-F-HASHMAP-report.md`

> **AMENDMENT (operator ruling, 2026-08-15):** the plan premise was WRONG — Task 3 never added `...MapInitCap`/in-place grow to `util/hash.zig`; and true in-place grow is infeasible with the separate-3-array layout (tail-realloc extends one array; rehash needs all three). Ruling: 6-F (1) ADDS `...MapInitCap` (capacity-hint alloc for all 3 arrays at once), (2) pre-sizes the ~6 DIRECT candidates only, (3) does NOT pre-size `error_code_registry` (emitted `#define ERROR_*` slot order → byte-identity), (4) does NOT refactor map layout; unhinted maps keep the existing copy-into-bump grow (leak accepted).

**Interfaces:**
- Consumes: 6-I enumeration (`.superpowers/sdd/task-F-HASHMAP-I-report.md`).
- Produces: `...MapInitCap(alloc, hint)` in `util/hash.zig`; ~6 direct map sites pre-sized at init.

- [ ] **Step 1: Add `...MapInitCap`** to `util/hash.zig` — for each map type, a capacity-hint init that allocates all 3 arrays (keys/vals/slots) at the hinted size in one go (matching the existing grow layout).
- [ ] **Step 2: Pre-size the ~6 direct candidates** from the 6-I report (keyword_set, emitted_type_set, fwd_decl_set, lfwd, lemit, pointer_only_map, cinclude seen) — convert to `...MapInitCap` with the exact hint source. Do NOT pre-size `error_code_registry` (emitted order). Do NOT guess sizes; skip any candidate whose hint is not cheaply available.
- [ ] **Step 3: Rebuild + verify byte-identity** — 4 MD5s byte-identical; corpus 253 unchanged; `--track-memory` on rogue_mud (record before/after; the pre-sized maps are scratch-arena, single-digit KB — a measurable reduction is NOT expected on rogue_mud, per the review); test_analyzer_bin PASS.
- [ ] **Step 4: Commit** — `git add` the files actually changed + docs; message `fix: add MapInitCap + pre-size direct hash maps (reduce rehash waste)`.

> **AMENDMENT (operator ruling, 2026-08-15):** gate wording corrected — the pre-sized maps are **scratch**-arena, not module/perm; the plan's "module/perm peaks reduced" was off-target. Measured identical (±1K noise); total 756K ≪ 16MB, no runtime impact. Accepted. (Reviewer also noted: `types_len`-hinted maps over-allocate at most ~1 grow's worth when few types emit — negligible, accepted.)

**Gate:** 4 MD5s byte-identical; corpus 253 unchanged; byte-identity preserved (no emitted-order-observable map pre-sized).

---

### Task 7: F-TYPEDB — type_db soft OOM + peak exposure (growable SUBSUMED by Task 3)

> **AMENDMENT (operator long-term ruling, 2026-08-14):** the `type_db` **growable** is SUBSUMED by Task 3's unified pool (type_db becomes a pool-backed `GrowableSand` there). This task keeps ONLY the soft-OOM + `--track-memory` peak exposure.

**Files:**
- Modify: `sf/src/type_registry.zig:127-136, 143-153` (`arrayGrow`, `typeRegistryEnsureCapacity`: `catch unreachable` → soft OOM)
- Modify: `sf/src/main.zig:239-258` (`--track-memory` block: add `type_db` peak — already extended for `pool=XK` in Task 3)
- Modify (docs): `sf/docs/tech_docs/03_type_resolution.md` (`[updated: 2026-08-14]`)
- Report: `.superpowers/sdd/task-F-TYPEDB-report.md`

**Interfaces:**
- Consumes: the pool-backed `type_db` `GrowableSand` (Task 3), `TypeRegistry` (`type_registry.zig`).
- Produces: type-registry OOM is a soft `pal.exit(1)` (not `catch unreachable` panic); `--track-memory` prints `type_db=XK`.

- [ ] **Step 1: Change `catch unreachable` to a soft OOM in `type_registry.zig`**

In `arrayGrow` (`:129`) and `typeRegistryEnsureCapacity` (`:148`), replace `catch unreachable` with a path that prints `OOM: type_db ...` (reuse the `sandAlloc` OOM style) and `pal.exit(1)`. (No `error` return needed — the existing callers don't handle errors.)

- [ ] **Step 2: Rebuild + verify**

Rebuild. Run `--track-memory --markers` on rogue_mud — confirm `type_db=XK` prints (already wired for `pool=XK` in Task 3). 4 MD5s byte-identical (the flag is not used in the MD5 recipe); corpus 252 unchanged.

- [ ] **Step 3: Commit**

```bash
git add sf/src/type_registry.zig sf/docs/tech_docs/03_type_resolution.md
git commit -m "fix: type_db soft OOM (growable already pool-backed via Task 3)"
```

**Gate:** no `catch unreachable` remains in `type_registry.zig` OOM paths; `--track-memory` prints `type_db=XK`; 4 MD5s byte-identical.

---

### Task 8-I: F-SWEEP re-audit — which I-M2 collections remain after Tasks 1/4/5/6/7

> **AMENDMENT (operator ruling, 2026-08-16):** Task 8 split into 8-I (re-audit) + 8-F (implement). The I-M2 lever table lists ALL 37 collections, but Tasks 1/4/5/6/7 already migrated some (#1 token, #25 source+line_offsets, #12-13 AST nodes+extra_children, #8/#19 LIR, #34-37 type_db). 8-I determines the REMAINING set so 8-F doesn't re-touch done work. **OPERATOR RULING (2026-08-16):** the 8-I re-audit (`.superpowers/sdd/task-F-SWEEP-I-report.md`) found the earlier list inaccurate — Tasks 4/6 did NOT cover #14-16 (AST identifiers/string_values/int_values/float_values/fn_protos), #21 (enum_value_table/error_code_registry/call_arg_types/call_param_map/comptime_values), or #30 (path_to_id/content_to_id). Evidence wins: **DONE=14 / REMAINING=23**; 8-F scope = the 23 REMAINING collections in the 8-I report.

**Files:**
- Investigate (read-only): `sf/src/` (the I-M2 catalog at `.superpowers/sdd/I-M2-wasteaudit-report.md` vs current source)
- Modify (docs): none
- Report: `.superpowers/sdd/task-F-SWEEP-I-report.md`

- [ ] **Step 1: Load the I-M2 catalog** (37 collections, each with file:line + growth strategy + lever) and the current git log (Tasks 1-7 commits).
- [ ] **Step 2: Mark each collection done-or-remaining** — for each of the 37, verify against live source whether the lever was already applied (token two-pass #1; source-into-perm + line_offsets #25; AST store pre-size #12-16; LIR relocate/reset #8/#19; MapInitCap #21/#30; type_db #34-37). Produce DONE list + REMAINING list.
- [ ] **Step 3: For each REMAINING collection** — confirm its current grow path (re-read the code; lines shifted), restate the recommended lever (exact-size / in-place `sandTryReallocInPlace` / per-scope reset / pre-size), and estimate the peak saving (KB, per --track-memory intuition or prior I-M2 numbers).
- [ ] **Step 4: Rank + write the report** — remaining set ordered by (saving ÷ risk), each with the exact lever + file:line for 8-F. Note any collection where the plan's lever is now inapplicable (already done or superseded).

**Gate:** complete DONE/REMAINING classification of all 37 collections + lever per remaining collection; zero source changes.

### Task 8-F: F-SWEEP implement — migrate the REMAINING collections

> **AMENDMENT (operator ruling, 2026-08-16):** Task 8-F implements ONLY the REMAINING collections from the 8-I re-audit (`.superpowers/sdd/task-F-SWEEP-I-report.md`). Do NOT re-touch collections already migrated by Tasks 1/4/5/6/7. The lever table below is the I-M2 reference; the 8-I report is the authoritative remaining-set + lever + file:line. **OPERATOR RULING (2026-08-16):** the 8-I re-audit showed the earlier "already migrated" list was inaccurate — Tasks 4/6 did NOT cover #14-16 (AST identifiers/string_values/int_values/float_values/fn_protos), #21 (enum_value_table/error_code_registry/call_arg_types/call_param_map/comptime_values), or #30 (path_to_id/content_to_id). Evidence wins: **8-F scope = the 23 REMAINING collections** listed in the 8-I report (DONE=14/REMAINING=23).

**Files:**
- Modify: the remaining cataloged collections (I-M2 report) — see the lever table below.
- Modify (docs): the covering tech doc per `INDEX.md` Table A for each file touched (`[updated: 2026-08-14]`).
- Report: `.superpowers/sdd/task-F-SWEEP-report.md`

**Interfaces:**
- Consumes: Task 3 helpers (`sandTryReallocInPlace`, exact-size helpers, map pre-size).
- Produces: every growable collection migrated to exact-size / in-place / per-scope-reset, eliminating the ~2× waste across the board.

Lever assignment (from I-M2 catalog; collection # → file:line → lever):
- Scratch: lexer `string_buf` (#2, `lexer.zig:29-32`) → per-scope reset/exact; parser child/decl/case buffers (#3, `parser.zig:480-495`) → in-place; per-phase DepGraph (#4, `symbol_registrator.zig:38-67`) → per-scope reset; TypeResolver edges/worklist (#5, `type_resolver.zig:56-101`) → per-scope reset; sema arrays (#6, `semantic_analyzer.zig:222-238,1673-1703`) → per-scope reset; analyzer defer_queue (#7, `analyzer.zig:394`) → per-scope reset; lowerer stacks/maps (#9,#10, `lower.zig:107-207,266-276`) → per-scope reset/in-place; c89 caches (#11, `c89_emit.zig:90-97,980-988,2529-2531`) → in-place.
- Module: ResolvedTypeTable (#17), CoercionTable (#18), LirFunctionArray (#19), GlobalDeclArray (#20), enum/error/call maps (#21) → in-place/pre-size (maps via Task 6).
- Perm: interner entries/buckets (#23–24) → pre-size; source text + line_offsets (#25) → exact-size/pre-size; SourceFileArray (#26), diagnostics (#27) → in-place; ModuleRegistry modules/edges/queue/dirs (#28–29), path_to_id (#30) → in-place; SymbolRegistry tables (#31) → in-place; const_alias_prepass (#32) → exact-size (already); classifyTypeEmissionGroups (#33) → exact-size (already).
- type_db: types/payloads/fe-em-xt-xn/caches (#34–37) → in-place (Task 7 area).

- [ ] **Step 1: Work collection-by-collection**

For each collection, change its `EnsureCapacity`/grow path to use `sandTryReallocInPlace` (tail) with copy fallback, or pre-size/exact-size where the count is knowable. Commit after each file (or logical group) so regressions are isolated. Each sub-change must keep the 4 MD5s byte-identical.

- [ ] **Step 2: Rebuild + full gate after each group**

After each file: rebuild + reinstall std lib + 4 MD5s + spot corpus. Fix any regression before continuing.

- [ ] **Step 3: Final sweep gate + measure**

Full gate battery + `--track-memory` on rogue_mud: record the new per-arena peaks. (Self-compile still blocked by the F-PARSERGAP parser defect; measure the F-SWEEP effect on rogue_mud + `sf/src/*.zig` per-module peaks.)

- [ ] **Step 4: Commit** (grouped logical commits, one per file or arena tier)

**Gate:** REMAINING collections migrated per the 8-I report (grep shows `sandTryReallocInPlace`/exact-size/reset used on each remaining collection); 4 MD5s byte-identical; corpus 253 unchanged; per-arena peaks reduced on rogue_mud.

---

### Task 9: F-SOURCE — read source into perm (ABSORBED into Task 1)

> **AMENDMENT (operator ruling Option A, 2026-08-14):** This task is **absorbed into Task 1** (F-TOKEN+F-SOURCE). Do NOT implement it as a standalone task — Task 1 already reads each module's source directly into perm and removes the scratch→perm double materialize. The only residue worth folding in is the `line_offsets` pre-allocation heuristic fix (`source_manager.zig:81-82`, `content.len/40 + 16` underestimates for long lines → extra doubling); apply that within Task 1's source-manager change if not already covered.

- [ ] **Step 1 (skip — done in Task 1):** source-into-perm + `line_offsets` heuristic fix (covered by Task 1).

---

### Task 10: F-PARSEARENA — enlarge parser arena (ABSORBED into Task 2)

> **AMENDMENT (operator ruling, 2026-08-14):** this task is **absorbed into Task 2** (F-PARSER+F-PARSEARENA). Do NOT implement it as a standalone task — Task 2 already enlarges `p_arena_buf[4096]` → `[16384]` (a 16 KB per-module STACK buffer, not a static arena) and verifies the `total=4096` parser-arena OOM is gone. No further work here.

- [ ] **Step 1 (skip — done in Task 2):** parser-arena enlargement + verification (covered by Task 2).

---

### Task 11: F-DEADCODE — remove dead `ctx.dep_graph` + dead buffers (DROPPED)

> **OPERATOR RULING (2026-08-16): Task 11 DROPPED.** The implementer's BLOCKED report proved two plan mis-citations: (1) `sf/src/symbol_registrator.zig`'s DepGraph is LIVE (scratch per-phase graphs) — not to be touched; (2) the `[256]u32` `in_degree`/`worklist_items` buffers in `moduleRegistrySortModules` are the LIVE Kahn topo-sort working set (`module_registry.zig:450,462`, written/read :452-507,:519), not dead. Only `ctx.dep_graph` (main.zig:102 field + :166 init + :185 assignment) is genuinely dead (0 reads), and it is ~4-8 bytes — negligible. Operator ruled: do NOT implement; the task is dropped from the plan.

**Files:**
- Modify: `sf/src/main.zig:164` (and `:101`, `:183`) — remove unused `ctx.dep_graph`; `sf/src/symbol_registrator.zig` (the module-arena `dep_graph` field), `sf/src/module_registry.zig:359,371` (dead `[256]u32`×2 in `moduleRegistrySortModules`)
- Modify (docs): `sf/docs/tech_docs/02_symbol_registration.md` (`[updated: 2026-08-14]`)
- Report: `.superpowers/sdd/task-F-DEADCODE-report.md`

**Interfaces:**
- Consumes: I-M2 finding — module-arena `ctx.dep_graph` never populated (live dep-graphs are scratch: `symbol_registrator.zig:18-68`, `type_resolver.zig:40-101`).
- Produces: dead module-arena field + dead buffers removed (no behavior change).

- [ ] **Step 1: Confirm deadness**

`grep` for `ctx.dep_graph` and `dep_graph` across `sf/src/`; confirm the module-arena field is never read/written and the `[256]u32` buffers in `moduleRegistrySortModules` are unused.

- [ ] **Step 2: Remove the dead code**

Delete the field, its init, and the dead buffers. (If `dep_graph` is referenced anywhere, STOP — it is not dead.)

- [ ] **Step 3: Rebuild + verify byte-identity**

4 MD5s byte-identical; corpus 252 unchanged; self-compile completes.

- [ ] **Step 4: Commit**

```bash
git add sf/src/main.zig sf/src/symbol_registrator.zig sf/src/module_registry.zig sf/docs/tech_docs/02_symbol_registration.md
git commit -m "refactor: remove dead ctx.dep_graph + dead sort buffers"
```

**Gate:** 4 MD5s byte-identical; corpus 252 unchanged.

---

### Task 12: F-RESIZE — size the single pool (trim BSS) [REORDERED after F-PARSERGAP]

> **AMENDMENT (operator long-term ruling, 2026-08-14):** with Task 3's unified pool, "resize arenas" becomes **size the single `memory_pool_buf`** to measured peak + margin. No more five constants.

> **OPERATOR RULING (2026-08-16):** Task 12 is REORDERED to execute AFTER the F-PARSERGAP family. Its gate requires measuring the self-compile pool peak (`--track-memory` `pool=XK`) and verifying "self-compile completes under the sized pool" — both impossible while the F-PARSERGAP parser defect aborts self-compile early (rc=2 during import resolution, before the summary prints; the pool peak is at later LIR/emission phases). F-PARSERGAP {Feas+repro, Inv, Fix} executes FIRST; Task 12 runs after, measuring the real post-fix self-compile pool peak.

> **AMENDMENT (operator long-term ruling, 2026-08-14):** with Task 3's unified pool, "resize arenas" becomes **size the single `memory_pool_buf`** to measured peak + margin. No more five constants.

**Files:**
- Modify: `sf/src/allocator.zig` (`memory_pool_buf` size)
- Modify (docs): `sf/docs/tech_docs/00_shared_infra.md` (`[updated: 2026-08-14]`)
- Report: `.superpowers/sdd/task-F-RESIZE-report.md`

**Interfaces:**
- Consumes: post-sweep measured pool peak (Task 3/8), `--track-memory` `pool=XK`.
- Produces: `memory_pool_buf` sized to measured peak + margin (≥25%); BSS trimmed; self-compile still completes.

- [ ] **Step 1: Record the measured pool peak**

Run `--track-memory --markers` on self-compile (`sf/src/main.zig`) and record `pool=XK` (the pool high-water). Add a safety margin (≥25%).

- [ ] **Step 2: Size `memory_pool_buf`**

Edit `allocator.zig` `memory_pool_buf` to the measured-peak + margin size. Do NOT raise `DEV_MAX_MEM`/`RELEASE_MAX_MEM` (16 MB is the target, not the lever).

- [ ] **Step 3: Rebuild + full gate**

Rebuild + reinstall std lib. Self-compile completes under the new pool size; 4 MD5s byte-identical; corpus 252 unchanged; `--track-memory` confirms the reduced BSS and that the pool peak remains under the new size.

- [ ] **Step 4: Commit**

```bash
git add sf/src/allocator.zig sf/docs/tech_docs/00_shared_infra.md
git commit -m "fix: size memory pool to measured peak + margin (trim BSS)"
```

**Gate:** self-compile completes under the sized pool; 4 MD5s byte-identical; corpus 252 unchanged; BSS reduced.
### F-PARSERGAP-Feas: Feasibility — parser value-position optional-capture gap

> **AMENDMENT (operator ruling, 2026-08-14):** the parser gap blocks self-compile COMPLETION independent of memory. Task 13 family (Feas/Inv/Fix).

> **AMENDMENT (operator directive, 2026-08-16):** F-PARSERGAP-Feas MUST create a small standalone **repro** fixture (like F-PATHNORM-Repro) to work with — the full self-compile is an ultra-huge test target and would cause scope creep. The repro should isolate the value-position optional-capture construct at minimal size (a few lines in a `.zig` file + expected diagnostic), committed under `repro/mi_matrix/`, so Feas/Inv/Fix and all gates run against the repro instead of self-compile.

**Files:**
- Investigate (read-only): `sf/src/parser.zig` (expression/`if`-expression parsing, optional-capture `|cap|`), `sf/src/main.zig:669` (the failing construct), repro of `error[2000]`
- Create: `repro/mi_matrix/parsergap_value_if_xmod/main.zig` (or similar name) — minimal value-position `if (opt) |cap| expr else expr` fixture + NOTES.md (per operator directive)
- Modify (docs): none
- Report: `.superpowers/sdd/F-PARSERGAP-Feas-report.md`

- [ ] **Step 1: Reproduce + confirm** — `if (opt) |cap| expr else expr` in VALUE position fails `error[2000]` (expected identifier/expression) at `main.zig:669`; stmt-position works. Record the exact failing source + diagnostic.
- [ ] **Step 2: Create the repro fixture** — commit `repro/mi_matrix/parsergap_value_if_xmod/` (minimal main.zig with the value-position construct + a NOTES.md recording RED baseline: dump rc=2, `error[2000]`, 0 `.c` emitted). Must be self-contained (std only via bare `@import("std")` if needed in main).
- [ ] **Step 3: Locate the parser path** — which `parserParseIfExpr`/expression grammar entry rejects value-position optional-capture, and where the stmt-position path differs.
- [ ] **Step 4: Write the report** (confirmed, locus, scope of the grammar fix) + feed F-PARSERGAP-Inv.

**Gate:** failure reproduced, repro fixture committed, parser locus identified; zero `sf/src/` changes (repro dir only).

---

### F-PARSERGAP-Inv: Investigation — design the value-position `if (opt) |cap|` fix

**Files:**
- Investigate (read-only): `sf/src/parser.zig` expression grammar + `ast.zig` node shapes for `if_expr`, `capture`; zig0 oracle behavior if applicable
- Modify (docs): none
- Report: `.superpowers/sdd/F-PARSERGAP-Inv-report.md`

**Interfaces:**
- Consumes: F-PARSERGAP-Feas findings.
- Produces: the exact parser change (which functions/nodes) to parse value-position `if (opt) |cap| expr else expr` identically to stmt-position.

> **OPERATOR RULING (2026-08-16):** Inv review found 2 Critical — the "downstream already capture-ready" premise was FALSE for the LOWERER. `lower.zig:3310` if_expr path never reads `node.payload` (no bindOptionalCapture → unbound capture → wrong C) and never converts the optional cond before `.branch` (C89 struct branch → gcc rejects). The design must cover parser + lowerer; scope finalized in the F-PARSERGAP-Fix section (C1+C2+C3).

- [ ] **Step 1: Study the grammar** — how stmt-position `if (opt) |cap|` parses vs value-position; what token/parse path the value form should take.
- [ ] **Step 2: Design the fix** — the parser function(s) + node emission change so value-position works (and byte-identity holds for existing stmt-position code).
- [ ] **Step 3: Write the report** (the design + affected functions + risk) + feed F-PARSERGAP-Fix.

**Gate:** fix design specified with affected functions; zero source changes.

---

### F-PARSERGAP-Fix: Implement — value-position optional-capture `if` expression

**Files:**
- Modify: `sf/src/parser.zig` (per F-PARSERGAP-Inv design) + `sf/src/lower.zig` (if_expr capture binding + optional cond conversion — see OPERATOR RULING below) + possibly `sf/src/ast.zig` if a node shape changes
- Modify (docs): `sf/docs/tech_docs/00_lexer_parser.md` (`[updated: 2026-08-14]`)
- Report: `.superpowers/sdd/F-PARSERGAP-Fix-report.md`

> **OPERATOR RULING (2026-08-16) — F-PARSERGAP-Fix scope = parser + lowerer (C1+C2+C3), NOT parser-only.** F-PARSERGAP-Inv review proved the plan's "downstream already capture-ready / parser-only" premise is FALSE for the LOWERER: `lower.zig:3310` if_expr path never reads `node.payload` (no `bindOptionalCapture` → unbound capture → wrong C) and never converts the optional cond before `.branch` (C89 struct branch → gcc rejects). `main.zig:680` needs both. Fix implements: **(C1)** `bindOptionalCapture(self, node.payload, orig_cond_temp)` at the top of `then_bb` in the if_expr runtime path (mirror `if_stmt:4100`); **(C2)** optional-cond conversion before branching (`check_optional` → `has_val` for `.branch`, mirror `if_stmt:4068-4075`, capture uses the original optional temp); **(C3)** the if_expr comptime-fold sub-path (`lower.zig:3314-3326`) must be verified to be capture-free (captures require an optional cond which `comptime_values` does not fold) and documented/guarded. Parser change: leading-pipe capture block verbatim from `parserParseIfStmt:1485-1495` into `parserParseIfExpr:782-800`, wire `payload = capture_node` (replace hardcoded 0).

> **OPERATOR RULING (2026-08-16) — repros:** create the cross-module repro `repro/mi_matrix/parsergap_value_if_xmod_cross/` (module exposes `pub fn get_opt() ?i32`; main does `var x: i32 = if (lib.get_opt()) |cap| cap else -1;` in value position) IN ADDITION to the existing single-module `parsergap_value_if_xmod`. Cross-module value-position optional-capture is valid Zig; the type-id/scope-local fix covers it with NO extension — the repro is the proof. Both repros RED pre-fix (error[2000] at the value-position capture), GREEN post-fix.

**Interfaces:**
- Consumes: F-PARSERGAP-Inv design + C1/C2/C3 review findings.
- Produces: `if (opt) |cap| expr else expr` parses, binds, and lowers correctly in value position, single- and cross-module (self-compile no longer fails `error[2000]` at main.zig:680).

- [ ] **Step 1: Implement the fix** — parser.zig (`parserParseIfExpr`: leading-pipe capture block verbatim from `parserParseIfStmt:1485-1495`, wire `payload = capture_node` replacing hardcoded 0) + lower.zig if_expr path (C1 bindOptionalCapture in then_bb mirroring if_stmt:4100; C2 optional-cond check_optional conversion before .branch mirroring if_stmt:4068-4075; C3 comptime-fold sub-path verified capture-free + documented/guarded).
- [ ] **Step 2: Rebuild + verify** — `bash sf/scripts/build_release.sh` → gate `=== [release] Done ===`; reinstall std lib.
- [ ] **Step 3: Gate** — 4 MD5 gates byte-identical; corpus 253 unchanged (OK=247/FAIL=2/GG=4, per-module recipe); both repros (`parsergap_value_if_xmod` + `parsergap_value_if_xmod_cross`) now parse (dump rc=0) and run printing the expected value; self-compile progresses past the old `main.zig:680` failure.
- [ ] **Step 4: Commit** (`git add` the touched files; message `fix: parse+lower if (opt) |cap| expr else expr in value position`)

**Gate:** 4 MD5s byte-identical; corpus 253 unchanged; both value-position capture repros (single + cross-module) parse and run correctly; self-compile no longer fails at `main.zig:680`.

---

### Task 14: F-GATE — final gate sweep + re-measure + docs reconciliation

**Files:**
- Modify: `repro/mi_matrix/EXPECTED_FAIL.md` (add F-plan record: memory-optimization closeout; version bump), `docs/sf/QUICK_REF.md` (new baseline line: corpus counts + 4 MD5s + new per-arena peaks + self-compile status)
- Modify (docs): memory-budget doc `00_shared_infra.md` (final arena sizes + measured peaks)
- Report: `.superpowers/sdd/task-F-GATE-report.md`

**Interfaces:**
- Consumes: all prior task outputs; final measured baselines.
- Produces: reconciled docs (EXPECTED_FAIL, QUICK_REF) + final gate record.

- [ ] **Step 1: Run the complete gate battery**

- Self-compile: `mkdir -p /tmp/fgate && timeout 300 /tmp/fx_subfolder/zig1 --dump-c89 --output-dir /tmp/fgate sf/src/main.zig` → rc=0.
- 4 MD5 gates byte-identical.
- Corpus 252: `OK=246 / FAIL=2 / ICE=0 / CRASH=0 / GG=4`.
- 21-example matrix 21/21; `test_analyzer_bin` PASS.
- `--track-memory --markers` on self-compile: record final perm/mod/scr/type_db peaks.

- [ ] **Step 2: Reconcile docs**

EXPECTED_FAIL.md version bump + F-plan closeout record (list the 13 fixes, self-compile now completes, arenas resized). QUICK_REF.md new baseline line (corpus counts unchanged, 4 MD5s unchanged, new peaks, self-compile GREEN).

- [ ] **Step 3: Commit**

```bash
git add repro/mi_matrix/EXPECTED_FAIL.md docs/sf/QUICK_REF.md sf/docs/tech_docs/00_shared_infra.md
git commit -m "docs: memory-optimization gate sweep + reconciliation"
```

**Gate:** all baselines confirmed; docs reconciled; self-compile completes under 16 MB with measured margin.

---

**Report back — final whole-branch review, then STOP** for operator sign-off (byte-identical gates + self-compile + BSS reduction evidence).
