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

### Task 2: F-PARSER+F-PARSEARENA — growable field buffers + enlarge parser arena (ASan + 4KB-arena OOM)

> **AMENDMENT (operator ruling, 2026-08-14):** this task now ALSO includes F-PARSEARENA (enlarge the parser stack buffer `p_arena_buf[4096]` → `[16384]`, i.e. 16 KB — a per-module STACK buffer, NOT one of the three static arenas, zero BSS/budget impact). Rationale: Task 1 fixed the scratch OOM, which had masked this; large modules now hit `OOM: total=4096` in the parser stack arena. The standalone Task 10 (F-PARSEARENA) is **absorbed** here. The three static arenas (perm 4 MB / module 8 MB / scratch 2 MB = 14 MB BSS) must sum well UNDER 16 MB — F-RESIZE (Task 12) shrinks them, nothing grows any arena toward 16 MB.

**Files:**
- Modify: `sf/src/parser.zig:1104-1185` (`parserParseEnumType` `members_buf[64]`, `parserParseUnionType` `fields_buf[64]`), plus the sibling `[64]u32` field buffers at `:1077` (struct), `:1731`, `:1773` (same overflow class).
- Modify: `sf/src/import_resolver.zig:48` (`p_arena_buf: [4096]u8` → `[16384]u8`)
- Modify (docs): `sf/docs/tech_docs/00_lexer_parser.md` (`[updated: 2026-08-14]`)
- Report: `.superpowers/sdd/task-F-PARSER-report.md`

**Interfaces:**
- Consumes: `Parser` struct has a `*Sand` arena (passed as `&p_arena` in `import_resolver.zig:48-50`); `astStoreAddExtraChildren` (`ast.zig`).
- Produces: struct/union/enum with >64 fields/members parse correctly (no stack-buffer-overflow); parser arena enlarged so long field-init/switch-case lists no longer hit `OOM: total=4096`. Byte-identical for ≤64-field inputs.

- [ ] **Step 1: Reproduce the ASan overflow (baseline)**

```bash
mkdir -p /tmp/fp && timeout 120 /tmp/fx_subfolder/zig1 --dump-c89 --output-dir /tmp/fp sf/src/ast.zig 2>&1 | tail -5
```
Expected: `ERROR: AddressSanitizer: stack-buffer-overflow in parserParseEnumType` (or `parserParseUnionType`). Record the function + buffer. Also reproduce the parser-arena OOM: `timeout 120 /tmp/fx_subfolder/zig1 --dump-c89 --output-dir /tmp/fp2 sf/src/c89_emit.zig 2>&1 | grep "OOM:"` → `total=4096`.

- [ ] **Step 2: Replace the fixed `[64]u32` buffers with arena-backed growable arrays**

Each parser function does `var fields_buf: [64]u32 = undefined; fields_buf[fields_count] = field_node;`. Replace with a growable u32 list in the parser arena. Add a small helper (in `parser.zig`) `parserPushU32(self: *Parser, buf: *[*]u32, len: *usize, cap: *usize, v: u32) void` that grows via `sandAlloc(self.arena, ...)` with copy (bounded by the parser arena). Apply to all 5 `[64]u32` sites. Preserve the existing `astStoreAddExtraChildren(store, buf[0..count])` call shape so emitted C is byte-identical for the common case.

- [ ] **Step 3: Enlarge the parser stack buffer**

Change `sf/src/import_resolver.zig:48` `var p_arena_buf: [4096]u8 = undefined;` → `var p_arena_buf: [16384]u8 = undefined;`. This is a local stack frame (16 KB), auto-reclaimed on return — no BSS/arena/budget impact.

- [ ] **Step 4: Rebuild + verify no ASan crash + no parser-arena OOM + byte-identity**

Rebuild (`build_release.sh`, reinstall std lib). Re-run the repros: `ast.zig` (no ASan), `c89_emit.zig`/`lower.zig` (no `OOM: total=4096`). Then the 4 MD5 gates + corpus 252 must be unchanged.

- [ ] **Step 5: Commit**

```bash
git add sf/src/parser.zig sf/src/import_resolver.zig sf/docs/tech_docs/00_lexer_parser.md
git commit -m "fix: growable struct/union/enum field buffers + enlarge parser arena (ASan + 4KB OOM)"
```

**Gate:** no ASan crash on `ast.zig`/`parser.zig`/`main.zig` standalone; no parser-arena `total=4096` OOM on `c89_emit.zig`/`lower.zig`; 4 MD5s byte-identical; corpus 252 unchanged.

---

### Task 3: F-PRIMITIVES — in-place realloc + exact-size + hash-map grow helpers

**Files:**
- Modify: `sf/src/allocator.zig:55-65` (fix `sandReallocInPlace` end-check; add `sandTryReallocInPlace`)
- Modify: `sf/src/util/hash.zig` (pre-size at init; reuse the in-place path)
- Modify (docs): `sf/docs/tech_docs/00_shared_infra.md` (`[updated: 2026-08-14]`)
- Report: `.superpowers/sdd/task-F-PRIMITIVES-report.md`

**Interfaces:**
- Consumes: `Sand` (`allocator.zig:1-7`), `sandAlloc` (`:26-45`), `sandReallocInPlace` (`:55-65`).
- Produces: `pub fn sandTryReallocInPlace(sand: *Sand, old_ptr: [*]u8, old_size: usize, new_size: usize, alignment: usize) ?[*]u8` that returns the same pointer when `old_ptr+old_size == sand.start+sand.pos` AND the growth fits within `sand.end`; returns `null` otherwise. This is the tail-guarded in-place grow used by later tasks.

- [ ] **Step 1: Fix `sandReallocInPlace` to bound-check `sand.end`**

Current `sandReallocInPlace` (`allocator.zig:55-65`) extends `sand.pos` WITHOUT checking it stays within `sand.end`. Fix:

```zig
pub fn sandTryReallocInPlace(sand: *Sand, old_ptr: [*]u8, old_size: usize, new_size: usize, alignment: usize) ?[*]u8 {
    if (new_size <= old_size) return old_ptr;
    var old_end: usize = @ptrToInt(old_ptr) + old_size;
    var arena_end: usize = @ptrToInt(sand.start) + sand.pos;
    if (old_end != arena_end) return null;
    var grow: usize = new_size - old_size;
    if (sand.pos + grow > sand.end) return null;   // NEW: bound check
    sand.pos += grow;
    if (sand.pos > sand.peak) sand.peak = sand.pos;
    return old_ptr;
}
```

- [ ] **Step 2: Add exact-size + in-place grow helpers to `util/hash.zig`**

For each map (`u32ToU32MapGrow` `:40-71`, `u64ToU32MapGrow` `:123-154`, `u32ToU64MapGrow` `:198-229`), use `sandTryReallocInPlace` for the three arrays (keys/values/occupied) when they are arena-tail (they are, when allocated contiguously in one grow), falling back to the current copy. Additionally add an init-with-capacity path `u32ToU32MapInitCap(alloc: *Sand, cap_hint: usize)` that pre-allocates buckets at a power-of-2 ≥ cap_hint, so maps that know their size never rehash.

- [ ] **Step 3: Rebuild + verify byte-identity**

Rebuild + reinstall std lib. 4 MD5 gates + corpus 252 must be byte-identical/unchanged (no behavior change — these are allocation-path-only edits).

- [ ] **Step 4: Commit**

```bash
git add sf/src/allocator.zig sf/src/util/hash.zig sf/docs/tech_docs/00_shared_infra.md
git commit -m "feat: tail-guarded in-place realloc + hash-map pre-size helpers"
```

**Gate:** 4 MD5s byte-identical; corpus 252 unchanged; `sandTryReallocInPlace` now has call sites (grep confirms >0).

---

### Task 4: F-AST — pre-size AST store (module arena)

**Files:**
- Modify: `sf/src/ast.zig:127-210` (append helpers for `nodes`, `extra_children`, `identifiers`, `string_values`, `int_values`, `float_values`, `fn_protos`)
- Modify: `sf/src/import_resolver.zig` (or wherever AST store is initialized) to pre-size `nodes`/`extra_children` from a line-count heuristic.
- Modify (docs): `sf/docs/tech_docs/00_lexer_parser.md` (`[updated: 2026-08-14]`)
- Report: `.superpowers/sdd/task-F-AST-report.md`

**Interfaces:**
- Consumes: `AstStore` (`ast.zig:101-210`), `astStoreEnsureCapacity`-style helpers.
- Produces: AST `nodes`/`extra_children` allocated with a near-final pre-size (line-count × ~4 for nodes), eliminating most of the ~2× module-arena waste (~2.5 MB on self-compile).

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

### Task 6: F-HASHMAP — migrate all hash maps to pre-size/in-place

**Files:**
- Modify: `sf/src/util/hash.zig` (already done in Task 3) + every call site that can pre-size: `string_interner.zig:136-153`, `type_registry.zig` caches, `hash.zig` consumers in `semantic_analyzer.zig`, `type_resolver.zig`, `c89_emit.zig`.
- Modify (docs): `sf/docs/tech_docs/00_shared_infra.md` (`[updated: 2026-08-14]`)
- Report: `.superpowers/sdd/task-F-HASHMAP-report.md`

**Interfaces:**
- Consumes: Task 3 helpers (`u32ToU32MapInitCap`, in-place grow).
- Produces: maps that know their expected size pre-size at init; others grow in-place. Eliminates the 3-array-per-grow leak.

- [ ] **Step 1: Enumerate map init sites**

`grep` for `u32ToU32MapInit`/`u64ToU32MapInit`/`u32ToU64MapInit` in `sf/src/`. For each, determine whether an expected-size hint is available at the init site.

- [ ] **Step 2: Pre-size where a hint exists; in-place elsewhere**

Convert sites with a known/derivable size to `...MapInitCap(alloc, hint)`. Confirm the remaining maps now grow via the in-place path (Task 3).

- [ ] **Step 3: Rebuild + verify byte-identity**

4 MD5s byte-identical; corpus 252 unchanged; `--track-memory` on rogue_mud shows reduced module/perm peaks from map rehash elimination.

- [ ] **Step 4: Commit**

```bash
git add sf/src/util/hash.zig sf/src/string_interner.zig sf/src/type_registry.zig sf/src/semantic_analyzer.zig sf/src/type_resolver.zig sf/src/c89_emit.zig sf/docs/tech_docs/00_shared_infra.md
git commit -m "fix: pre-size hash maps + in-place grow (eliminate 3-array rehash leak)"
```

**Gate:** 4 MD5s byte-identical; corpus 252 unchanged.

---

### Task 7: F-TYPEDB — type_db peak exposure + soft OOM

**Files:**
- Modify: `sf/src/type_registry.zig:127-136, 143-153` (`arrayGrow`, `typeRegistryEnsureCapacity`: `catch unreachable` → soft OOM)
- Modify: `sf/src/main.zig:239-258` (`--track-memory` block: add `type_db` peak)
- Modify (docs): `sf/docs/tech_docs/03_type_resolution.md` (`[updated: 2026-08-14]`)
- Report: `.superpowers/sdd/task-F-TYPEDB-report.md`

**Interfaces:**
- Consumes: `type_db_buf: [131072]u8` (`main.zig:155-157`), `TypeRegistry` (`type_registry.zig`).
- Produces: `--track-memory` prints `type_db=XK`; type-registry OOM is a soft `pal.exit(1)` (not `catch unreachable` panic).

- [ ] **Step 1: Change `catch unreachable` to a soft OOM in `type_registry.zig`**

In `arrayGrow` (`:129`) and `typeRegistryEnsureCapacity` (`:148`), replace `catch unreachable` with a path that prints `OOM: type_db ...` (reuse the `sandAlloc` OOM style) and `pal.exit(1)`. (No `error` return needed — the existing callers don't handle errors.)

- [ ] **Step 2: Expose type_db peak in `--track-memory`**

In `main.zig:239-258`, add a `type_db_kb` read of the type-db sand's `peak` and append ` type_db=XK` to the printed line. The type-db sand must be reachable from `ctx` (it is created in `main.zig:155-157`).

- [ ] **Step 3: Rebuild + verify**

Rebuild. Run `--track-memory --markers` on rogue_mud — confirm the new `type_db=XK` field prints and the other 3 arena values are unchanged. 4 MD5s byte-identical (the `--track-memory` flag is not used in the MD5 recipe, so output is unaffected); corpus 252 unchanged.

- [ ] **Step 4: Commit**

```bash
git add sf/src/type_registry.zig sf/src/main.zig sf/docs/tech_docs/03_type_resolution.md
git commit -m "fix: type_db soft OOM + peak exposure in --track-memory"
```

**Gate:** `--track-memory` prints `type_db=XK`; no `catch unreachable` remains in `type_registry.zig` OOM paths; 4 MD5s byte-identical.

---

### Task 8: F-SWEEP — migrate remaining collections to exact-size/in-place/reset

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

Full gate battery + `--track-memory` on rogue_mud and self-compile (now possible): record the new per-arena peaks.

- [ ] **Step 4: Commit** (grouped logical commits, one per file or arena tier)

**Gate:** all collections migrated (grep shows `sandTryReallocInPlace` used across the board); 4 MD5s byte-identical; corpus 252 unchanged; per-arena peaks reduced; self-compile still completes.

---

### Task 9: F-SOURCE — read source into perm (ABSORBED into Task 1)

> **AMENDMENT (operator ruling Option A, 2026-08-14):** This task is **absorbed into Task 1** (F-TOKEN+F-SOURCE). Do NOT implement it as a standalone task — Task 1 already reads each module's source directly into perm and removes the scratch→perm double materialize. The only residue worth folding in is the `line_offsets` pre-allocation heuristic fix (`source_manager.zig:81-82`, `content.len/40 + 16` underestimates for long lines → extra doubling); apply that within Task 1's source-manager change if not already covered.

- [ ] **Step 1 (skip — done in Task 1):** source-into-perm + `line_offsets` heuristic fix (covered by Task 1).

---

### Task 10: F-PARSEARENA — enlarge parser arena (ABSORBED into Task 2)

> **AMENDMENT (operator ruling, 2026-08-14):** this task is **absorbed into Task 2** (F-PARSER+F-PARSEARENA). Do NOT implement it as a standalone task — Task 2 already enlarges `p_arena_buf[4096]` → `[16384]` (a 16 KB per-module STACK buffer, not a static arena) and verifies the `total=4096` parser-arena OOM is gone. No further work here.

- [ ] **Step 1 (skip — done in Task 2):** parser-arena enlargement + verification (covered by Task 2).

---

### Task 11: F-DEADCODE — remove dead `ctx.dep_graph` + dead buffers

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

### Task 12: F-RESIZE — re-measure + shrink arenas (trim BSS)

**Files:**
- Modify: `sf/src/allocator.zig:74-76` (arena sizes)
- Modify (docs): `sf/docs/tech_docs/00_shared_infra.md` (`[updated: 2026-08-14]`)
- Report: `.superpowers/sdd/task-F-RESIZE-report.md`

**Interfaces:**
- Consumes: post-sweep measured peaks (Task 8), I-M3 projection (module ~4.5 MB, perm ~1.5 MB after F2).
- Produces: reduced static BSS (arena buffers) sized to measured peaks + margin. Candidates: module 8→6 MB, perm 4→3 MB, scratch 2 MB kept (needed for the token burst headroom).

- [ ] **Step 1: Record post-sweep peaks**

Run `--track-memory --markers` on self-compile (`sf/src/main.zig`) — now that it completes — and record perm/mod/scr/type_db peaks. Add a safety margin (≥25%).

- [ ] **Step 2: Resize the arena buffers**

Edit `allocator.zig:74-76` to the measured-peak + margin sizes. Do NOT raise `DEV_MAX_MEM`/`RELEASE_MAX_MEM` (16 MB is the target, not the lever).

- [ ] **Step 3: Rebuild + full gate**

Rebuild + reinstall std lib. Self-compile completes under the new sizes; 4 MD5s byte-identical; corpus 252 unchanged; `--track-memory` confirms the reduced BSS (static buffer sizes) and that peaks remain under the new caps.

- [ ] **Step 4: Commit**

```bash
git add sf/src/allocator.zig sf/docs/tech_docs/00_shared_infra.md
git commit -m "fix: shrink arena buffers to measured peaks + margin (trim 14MB BSS)"
```

**Gate:** self-compile completes under the resized arenas; 4 MD5s byte-identical; corpus 252 unchanged; BSS reduced.

---

### Task 13: F-GATE — final gate sweep + re-measure + docs reconciliation

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
