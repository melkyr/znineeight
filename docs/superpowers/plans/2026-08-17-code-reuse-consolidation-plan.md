# Code-Reuse Consolidation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

> **OPERATOR RULING (2026-08-17):** Code-reuse workstream moved OUT of the parser-gaps plan into this dedicated plan. All byte-identity-SAFE candidates (~70) are implemented as F tasks grouped per cluster. Byte-identity-RISKY candidates (~12, STOP-flagged in the C-I audits) get I tasks to investigate how to lower the risk (report → operator ruling → F placeholders). The audits are complete; this plan implements the consolidations.

**Goal:** Consolidate duplicated logic, helpers, and allocations across the Z98 compiler to increase code reuse, preserving emitted-C byte-identity (4 MD5 gates) throughout.

**Architecture:** Part 1 = shared primitives (grow-array-into-sand, moduleKey, integer formatting) land first — everything consumes them. Part 2 = one F task per cluster implementing its SAFE candidates. Part 3 = I tasks investigating risk-lowering for the byte-identity-RISKY candidates, followed by operator ruling and F placeholders. A final gate sweep reconciles docs.

**Tech Stack:** Z98 compiler (`sf/src/*.zig`), compiler under test `/tmp/fx_subfolder/zig1`, 4 MD5 gates, corpus 255, `--dump-c89`.

## Global Constraints

- **Read `docs/sf/QUICK_REF.md` first** — the ⭐ SUBAGENT CHEAT-SHEET (lines 1-70) is MANDATORY. Copy exact commands. **Compiler under test is `/tmp/fx_subfolder/zig1`** (NOT `sf/build/out_release/zig1`).
- **`sf/build/out_release/` is WEDGED — any command touching it HANGS; NEVER touch/list/build into it. Use `timeout` on all risky commands.**
- **Build:** `bash sf/scripts/build_release.sh` → gate line `=== [release] Done: /tmp/fx_subfolder/zig1 ===`. **The script wipes `/tmp/fx_subfolder/` (including `lib/`) — reinstall the std lib after every rebuild:** `cp sf/src/std.zig sf/src/std_io.zig sf/src/std_arena.zig sf/src/std_net.zig /tmp/fx_subfolder/lib/`.
- **Editing:** `edit`/`fastedit` only (AGENTS.md §X.7: re-read region before each edit, bottom-to-top). NO sed/python/bulk transforms. fastedit: re-read after every edit; keep new_code a single contiguous block; NEVER end_line=start_line-1.
- **Z98 constraints** (AGENTS.md §1.3): no anytype/@Type; concrete maps (`U32ToU32Map` etc.); `@intCast` for i32↔usize; no pointer captures; switch requires `else`.
- **The plan is the ONLY authority.** STOP on any issue. Do NOT re-flag already-migrated memory patterns (see `docs/superpowers/plans/2026-08-14-memory-optimization-plan.md`).
- **MD5 gate recipe:** single-file `--dump-c89` to stdout piped to `md5sum`. Baselines (unchanged since memory-optimization closure, HEAD `de630979`):
  - gol `9cf758d96f25d41980379564a5501bc8`
  - lisp `524d2872daefb2677c8ddc1ac8f34cf5`
  - json `066c99974f6052317636854dc4c2a2d5`
  - mud `a1d0dd55aada9c3fd904ae33f54de32e`
- **Baselines to preserve:** corpus 255 dirs `OK=249 / FAIL=2 / ICE=0 / CRASH=0 / GG=4` (FAIL=2 = `field_store_drop` + `self_embed_optional_cycle`; GG=4 = `eu_assign_incompat_payload`, `euvoid_val_catch`, `field_access_optional`, `var_declared_void`). Corpus recipe is **per-module** (`--dump-c89 --output-dir DIR` then gcc each `.c`); the stdout-concat recipe falsely fails `fn_ptr_struct_field`. 21-example matrix 21/21; `test_analyzer_bin` "5 passed, 4 failed".
- **Every F task must run the 4 MD5 gates** after building; any MD5 change = STOP (byte-identity broken).
- **Audit sources of record** (authoritative for every F task): `.superpowers/sdd/task-C-I1-report.md` (frontend), `task-C-I2-report.md` (module/import), `task-C-I3-report.md` (semantic), `task-C-I4-report.md` (type system), `task-C-I5-report.md` (lowering), `task-C-I6-report.md` (emission), `task-C-I7-report.md` (infra/util). Each F task reads its cluster's report for exact file:line and designs.

---

## Part 1 — Shared primitives

### Task C-F0: Shared primitives — grow-array-into-sand + moduleKey + integer formatting

**Files:**
- Modify: `sf/src/growable_array.zig` (add in-place grow variant for the 5 typed lists), `sf/src/type_registry.zig` (add `moduleKey` helper), `sf/src/util/itoa.zig` or `util/format.zig` (pick the surviving decimal formatter)
- Report: `.superpowers/sdd/task-C-F0-report.md`

**Interfaces:**
- Consumes: C-I1 §H1, C-I2 §C1/A5, C-I3 §2.3, C-I4 §H2, C-I5 §2A, C-I7 §H1/H2 (all cross-reference these shared primitives).
- Produces: three shared primitives that C-F1..C-F7 consume:
  - `growArrayEnsureCapacity(alloc, items, len, cap, elem_size, align, min_cap)` (in-place → copy fallback; exact grow sequence: 2× doubling, min 8, same in-place/copy choice order as today)
  - `moduleKey(mod_id: u32, name_id: u32) u64` (`(u64)mod * 4294967296 + (u64)name`) in `type_registry.zig` next to `nameCacheGet/Put`
  - one surviving decimal integer formatter (count-returning `itoa` or slice-returning `formatU32`; the other is retired)

- [ ] **Step 1: Add `growArrayEnsureCapacity` to `growable_array.zig`**

Port the in-place grow body that already exists verbatim in `parser.zig:480-508`/`ast.zig:127-262` (C-I1 H1) into `growable_array.zig` as a shared raw-pointer helper. Keep the exact grow sequence (2× doubling, min 8, in-place attempt then copy-into-bump) so allocation behavior is byte-identical. Preserve `byteArrayListGrow`'s existing in-place path (`growable_array.zig:66-89`) as the reference.

- [ ] **Step 2: Add `moduleKey` to `type_registry.zig`**

```zig
pub fn moduleKey(mod_id: u32, name_id: u32) u64 {
    return @intCast(u64, mod_id) * 4294967296 + @intCast(u64, name_id);
}
```
Place next to `nameCacheGet/Put` (the canonical key shape at `type_registry.zig:658`). This is the ONE owner of the 15-site key composition (C-I3/C-I4 coordination: the STOP assigns C-F0 as the owner; C-F3/C-F4 re-point their sites, they do NOT re-implement).

- [ ] **Step 3: Pick one decimal formatter**

Choose `util/itoa.zig` (count-returning, null-terminated) OR `util/format.zig` (slice-returning, no null) as the single primitive. The other is retired by C-F7 (which owns the `lexer.zig:706-723`, `diagnostics.zig:136-150`, `tests/lexer_tests.zig:63-80` deletions). C-F0 only confirms the choice and the per-caller slice-math contract (C-I7 §2 Concern: diagnostics writes `[16-len..16]` no-null; format returns `[start..len-1]`). Do NOT delete any caller yet — C-F7 owns that.

- [ ] **Step 4: Build + gates**

`bash sf/scripts/build_release.sh` → gate; reinstall std; 4 MD5s byte-identical; corpus 255 unchanged. (C-F0 adds helpers but re-points nothing yet, so byte-identity is expected trivially — verify anyway.)

- [ ] **Step 5: Commit + report**

Commit `feat: shared primitives — growArrayEnsureCapacity + moduleKey + formatter choice`. Report `.superpowers/sdd/task-C-F0-report.md` (helper signatures, grow-sequence contract, formatter decision).

---

## Part 2 — SAFE consolidation candidates (one F task per cluster)

> Every task in Part 2 is byte-identity-SAFE per its cluster audit (alloc-strategy, pure-extraction, or dead-file). Each re-points its cluster's duplicated sites onto the C-F0 primitives or consolidates in-cluster. Each runs the full gate battery (4 MD5s + corpus + matrix + test_analyzer).

### Task C-F1: Frontend/parse cluster consolidation (SAFE)

**Files:**
- Modify: `sf/src/parser.zig`, `sf/src/lexer.zig`, `sf/src/token.zig`, `sf/src/ast.zig`, `sf/src/growable_array.zig` (re-point to C-F0 helper)
- Report: `.superpowers/sdd/task-C-F1-report.md`

**Interfaces:**
- Consumes: C-I1 report; C-F0 primitives.
- Produces: consolidated parser/lexer/token/ast helpers.

- [ ] **Step 1: Token plumbing** — `tokenEnd`/`parseTokenEnd` (H2, 70+ sites), `parserInternIdent` (H3, 21 sites), `parserConsumeIf` (H4, ~35 sites), `parserLastEnd` + make `parserExpect` update `last_end` (H5, 10 sites). All pure extraction; interner insertion order unchanged (H3 dedups, never adds).
- [ ] **Step 2: Parser structural helpers** — capture-name helper (H6, 5-6 copies; keep switch-prong/catch distinct node shapes), block-vs-expr body helper (H7), container-field parser (H8, verify MD5), single operator table (H9, verify MD5), `tokenKindName` → `token.zig` (H10).
- [ ] **Step 3: Lexer + ast consolidation** — `formatU32` → `util/format.zig` (H11), char predicates → util (H12), test fixture/assert helpers (H13/H14, test_analyzer gate), ast literal-add twins (H15), lexer inline Token builds → `lexerMakeToken` (H16), 3-part diag builder (H17).
- [ ] **Step 4: Re-point 6 private grow bodies** (C-I1 D1: `parser.zig:480-508`, `ast.zig:127-262`) onto C-F0's `growArrayEnsureCapacity`; retire the private copies.
- [ ] **Step 5: Route 7 parser local buffers through `child_buf`** (C-I1 A3/D16) — verify MD5.
- [ ] **Step 6: Build + full gates**

Rebuild, reinstall std, 4 MD5s byte-identical, corpus 255 unchanged, matrix 21/21, `test_analyzer_bin` "5 passed, 4 failed".

- [ ] **Step 7: Commit + report**

Commit `refactor: consolidate frontend/parse helpers (token plumbing, capture-name, operator table, grow re-point)`. Report `.superpowers/sdd/task-C-F1-report.md`.

---

### Task C-F2: Module/import cluster consolidation (SAFE)

**Files:**
- Modify: `sf/src/import_resolver.zig`, `sf/src/module_registry.zig`, `sf/src/source_manager.zig`, `sf/src/string_interner.zig`, `sf/src/util/path.zig`, `sf/src/util/mem.zig`
- Report: `.superpowers/sdd/task-C-F2-report.md`

**Interfaces:**
- Consumes: C-I2 report; C-F0 grow helper.
- Produces: consolidated module/import helpers.

- [ ] **Step 1: Path helpers → `util/path.zig`** (C-I2 A1/C2): move `joinPath`/`moduleDirPath`/`appendZigExt` as `joinPath`/`dirname`/`appendExt`, preserving exact alloc + `orelse return full` fallback + in-place normalize semantics. Interning order unchanged.
- [ ] **Step 2: `mem.copyToArena`** (C-I2 A2/C3): merge `stringInternerCopyToArena` + `sourceManagerCopyToArena`; document the empty-input contract (interner alloc-0; source_manager callers pass non-empty).
- [ ] **Step 3: Resolve-triple helper** (C-I2 A4): `moduleRegistryLinkImport(reg, importer_id, imported_id)` = `moduleRegistryAddImport + importQueueEnqueue + u32ToU32MapPut(path_to_id)`; collapse the 4× tail at `module_registry.zig:342-376`. Parse-time re-enqueue loop keeps its distinct state-filtered semantics but calls the same primitive.
- [ ] **Step 4: 3-part error-message helper** (C-I2 C5/D8): `diagAddFileError(diag, interner, code, prefix, path)`; keep both 3048 message texts distinct.
- [ ] **Step 5: Strip debug instrumentation** (C-I2 C7/D9): dead ECB/ECD vars (`import_resolver.zig:101-128`), duplicate IRP/IRD decl-dump loops (`:180-192`, `:209-226`). Marker writes are runtime-gated — removal is behavior-neutral.
- [ ] **Step 6: Re-point 6 local `EnsureCapacity` bodies** (C-I2 D6) onto C-F0 `growArrayEnsureCapacity` (parameterize the min-cap: searchDir min-2 vs min-8). Do NOT restructure struct layout (C-I2 C1 low-risk variant: raw-ptr helper, keep `ImportQueue`/`ModuleRegistry` fields as-is so `tests/test_mod_reg_bin.zig` still compiles).
- [ ] **Step 7: Build + full gates**

Rebuild, reinstall std, 4 MD5s byte-identical, corpus 255, matrix, test_analyzer.

- [ ] **Step 8: Commit + report**

Commit `refactor: consolidate module/import (path helpers, copyToArena, link-import triple, grow re-point)`. Report `.superpowers/sdd/task-C-F2-report.md`.

---

### Task C-F3: Semantic cluster consolidation (SAFE)

**Files:**
- Modify: `sf/src/semantic_analyzer.zig`, `sf/src/analyzer.zig`, `sf/src/coercion.zig`, `sf/src/const_alias_prepass.zig`; delete `sf/src/semantic.zig`
- Report: `.superpowers/sdd/task-C-F3-report.md`

**Interfaces:**
- Consumes: C-I3 report; C-F0 `moduleKey` + grow helper.
- Produces: consolidated semantic helpers; `semantic.zig` deleted.

- [ ] **Step 1: Re-point in-cluster `moduleKey` sites** (C-I3 §1.1: const_alias_prepass.zig:164/174/186/221, semantic_analyzer.zig:1921) onto C-F0's `moduleKey`. (C-F4 owns type_resolver/symbol_registrator/type_registry sites.) Pure arithmetic, byte-identity safe.
- [ ] **Step 2: `recordCoercionOrDiagnose`** (C-I3 §2.4): unify the 3 `tryRecordCoercion`/`errLitSrcType` call sites (return :744, local var :1876-1880, module var :2122-2124). Keep the emitted add-set identical.
- [ ] **Step 3: `identNameId`** (C-I3 §2.5): consolidate the ~30 inline one-liners (extraction only, `ast.zig` home).
- [ ] **Step 4: Re-point grow bodies** (C-I3 §2.3: coercion.zig:43-64, resolved_type_table.zig:37-60/84-106, semantic_analyzer.zig:222-238/1673-1700, analyzer.zig:389-400, const_alias_prepass.zig:43-58) onto C-F0.
- [ ] **Step 5: Delete `semantic.zig`** (C-I3 §1.5/§2.7: 0 importers, stale spec sketch shadowing live names).
- [ ] **Step 6: Build + full gates**

Rebuild, reinstall std, 4 MD5s byte-identical, corpus 255, matrix, test_analyzer.

- [ ] **Step 7: Commit + report**

Commit `refactor: consolidate semantic cluster (moduleKey re-point, recordCoercionOrDiagnose, identNameId, delete semantic.zig)`. Report `.superpowers/sdd/task-C-F3-report.md`.

---

### Task C-F4: Type-system cluster consolidation (SAFE)

**Files:**
- Modify: `sf/src/type_resolver.zig`, `sf/src/type_registry.zig`, `sf/src/resolved_type_table.zig`, `sf/src/symbol_table.zig`, `sf/src/symbol_registrator.zig`
- Report: `.superpowers/sdd/task-C-F4-report.md`

**Interfaces:**
- Consumes: C-I4 report; C-F0 `moduleKey` + grow helper.
- Produces: consolidated type-system helpers.

- [ ] **Step 1: Re-point in-cluster `moduleKey` sites** (C-I4 D1: type_resolver.zig:701/711/1115/1166, symbol_registrator.zig:274/278, type_registry.zig:658) onto C-F0 `moduleKey` — including the lone shift-form `type_resolver.zig:1026` (`(mod_id << 32) | ...` → `moduleKey`). C-F0 is the owner; C-F3/C-F4 only re-point.
- [ ] **Step 2: `alignUp` dedup** (C-I4 H1): delete the private `type_resolver.zig:125-127` copy, call `type_mod.alignUp`.
- [ ] **Step 3: `registerType`/`typeRegistryAppendTyped`** (C-I4 D3): collapse ~10 `Type` literal constructions in the 8 GetOrCreate bodies; preserve `types_len` order.
- [ ] **Step 4: `typeRegistrySetLastPayloadIdx`** (C-I4 D6): collapse 5 backpatch blocks in symbol_registrator.zig:123-220.
- [ ] **Step 5: Field-decl collection helper** (C-I4 D5): share the field-loop between `resolveTypeExprFull` struct arm + `resolveDeclAggregateFieldTypes`; preserve `fe_`/`st_` append order.
- [ ] **Step 6: `makeSymbol`** (C-I4 H6): collapse 6 `Symbol` literals in symbol_registrator.zig:287-397.
- [ ] **Step 7: `isNumeric`/`isInteger` compose + kind-predicate set helper** (C-I4 H4/H5).
- [ ] **Step 8: Re-point grow bodies** (C-I4 H2: type_registry.zig:145-177, resolved_type_table.zig:37-60/84-106, symbol_table.zig:40-61/91-112, symbol_registrator.zig:38-57, type_resolver.zig:56-123) onto C-F0. NOTE type_registry grow paths stay copy-into-bump if C-F0's helper preserves the current choice — do NOT change behavior, only share the body.
- [ ] **Step 9: Build + full gates**

Rebuild, reinstall std, 4 MD5s byte-identical, corpus 255 (incl. `r_fallback_*` green-guards), matrix, test_analyzer.

- [ ] **Step 10: Commit + report**

Commit `refactor: consolidate type-system cluster (moduleKey re-point, registerType, SetLastPayloadIdx, makeSymbol, grow re-point)`. Report `.superpowers/sdd/task-C-F4-report.md`.

---

### Task C-F5: Lowering cluster consolidation (SAFE)

**Files:**
- Modify: `sf/src/lower.zig`, `sf/src/lir.zig`, `sf/src/comptime_eval.zig`, `sf/src/state_map.zig`, `sf/src/constraint_checker.zig`
- Report: `.superpowers/sdd/task-C-F5-report.md`

**Interfaces:**
- Consumes: C-I5 report; C-F0 grow helper.
- Produces: consolidated lowering helpers.

- [ ] **Step 1: `foldComptimeIntConst`** (C-I5 #2): extract the 7-line comptime-fold arm shared by 10 binary + 2 unary arms (lower.zig:1485-1642, 1758-1784). Preserve fold order/temp allocation exactly.
- [ ] **Step 2: `lowerCondToBool`** (C-I5 #3): extract the optional→bool conversion from if_expr/if_stmt/while (lower.zig:3334-3344, 4074-4099, 4170-4189). Keep the if_stmt-only tagged-union arm a separate concern (parameterize or leave as a distinct arm — do NOT change its behavior).
- [ ] **Step 3: Capture-binding tail helper** (C-I5 #4): share `maybeDisambiguateCapture+addLocalDecl+decl_local` across bindOptionalCapture/catch/for (lower.zig:1275-1276, 3228-3230, 4257).
- [ ] **Step 4: `newLirFunctionHeader`** (C-I5 #5): dedup the `LirFunction` header build between `lowerFn` (:5246-5260) and `lowerModuleInit` (:5344-5356).
- [ ] **Step 5: comptime_eval helpers** (C-I5 #6/#7/#14): `wrapWidth` sign-extension helper (:141-151 vs :183-196), signed div/mod abs-trick (:63-71 vs :77-85), size_of/align_of arm merge (:114-131).
- [ ] **Step 6: `typeRegistryMemberCount`** (C-I5 #8): extract the enum-vs-tagged-union member-count walk from constraint_checker.zig:39-46 + lower.zig:2153-2170/2363-2396 into type_registry.zig.
- [ ] **Step 7: eu unwrap + applyCoercion merge** (C-I5 #9/#10): eu_box detection + ok-unwrap helper (lower.zig:3144-3260); merge the byte-identical int_widen/int_literal_coerce arms (:4922-4933).
- [ ] **Step 8: stateMap + misc** (C-I5 #11/#15): stateMapEnsureCapacity via C-F0 grow + `sandTryReallocInPlace`; `stateMapFork` → `initWithParent` (:62-71 vs :17-25).
- [ ] **Step 9: LirFunction list-growth re-point** (C-I5 1A): re-point the 7 lir.zig + 3 lower.zig ArrayList types onto C-F0 grow helper (preserving the in-place/copy choice each currently makes).
- [ ] **Step 10: Build + full gates**

Rebuild, reinstall std, 4 MD5s byte-identical, corpus 255, matrix, test_analyzer.

- [ ] **Step 11: Commit + report**

Commit `refactor: consolidate lowering cluster (fold helper, cond-to-bool, capture tail, comptime_eval helpers)`. Report `.superpowers/sdd/task-C-F5-report.md`.

---

### Task C-F6: Emission cluster consolidation (SAFE)

**Files:**
- Modify: `sf/src/c89_emit.zig`, `sf/src/print_decomposition.zig`; delete `sf/src/name_mangler.zig`, `sf/src/c89_types.zig`, `sf/src/assign_helper.zig`; drop the write-only `name_mangler` field in `sf/src/main.zig` (:94/153/178) and `sf/src/strip_main.zig`
- Report: `.superpowers/sdd/task-C-F6-report.md`

**Interfaces:**
- Consumes: C-I6 report.
- Produces: consolidated emission helpers; 3 dead stubs deleted.

- [ ] **Step 1: `moduleHasAnyInst(fns, tag_mask)`** (C-I6 #2): replace 6 module scans (`c89_emit.zig:1985-2121`) with one predicate. Pure, no emission change.
- [ ] **Step 2: Delete the 3 dead stub modules** (C-I6 #1): `name_mangler.zig:1-7` (conflicts by name with the real `c89_emit.zig:90-97` mangler; write-only field in main.zig/strip_main.zig), `c89_types.zig:1-22` (uses `std.ArrayList` — non-compiling plan artifact), `assign_helper.zig:1-5` (dead twin of `resolveTempName`). Drop `main.zig:94/153/178` write-only field. **Scope:** only `main.zig` + `strip_main.zig` are cleanable; `main_dump.zig` is expected-broken, leave it (do NOT touch).
- [ ] **Step 3: `cnameDedupKey`** (C-I6 #4): extract the 7× FNV-31 loop (`:1129-2301`).
- [ ] **Step 4: `markerU32`/`markerStr` → util/** (C-I6 #5): fold the 76 itoa-triples + 32 `[20]u8` variants onto `dbgPrintU32`-style helpers (`c89_emit.zig:82-88`). Markers are `--markers`-gated stderr — keep marker text identical.
- [ ] **Step 5: `typeMangledName`** (C-I6 #3): fold the 12× mangle+intern tail of `getCTypeName` + the 6 emit*Type name derivations. Verify 4 MD5s (names must stay byte-identical).
- [ ] **Step 6: `getTempDecl`/`hoistedType`** (C-I6 #7): consolidate the 19 inline hoisted-temp scans.
- [ ] **Step 7: `isMainName`** (C-I6 #13): 4 copies (`:1877/2383/2393/2496`).
- [ ] **Step 8: Print-scanner unification** (C-I6 #8): share the format grammar between `lowerPrintFmt` (lower.zig:522-576) and `printDecompScanFormat` (print_decomposition.zig:14-35); keep the validator's `error[0001]` arg-count diagnostic behavior (test_semantic_bin asserts it).
- [ ] **Step 9: Build + full gates**

Rebuild, reinstall std, 4 MD5s byte-identical, corpus 255, matrix, test_analyzer. (`main_dump.zig` is expected-broken — not a gate.)

- [ ] **Step 10: Commit + report**

Commit `refactor: consolidate emission cluster (moduleHasAnyInst, dedupKey, markerU32, typeMangledName, delete 3 dead stubs)`. Report `.superpowers/sdd/task-C-F6-report.md`.

---

### Task C-F7: Infra/util cluster consolidation (SAFE)

**Files:**
- Modify: `sf/src/diagnostics.zig`, `sf/src/allocator.zig`, `sf/src/panic.zig`, `sf/src/source_manager.zig` (remove unused `util_mod` import at `:6`), `sf/src/growable_array.zig`; delete 7 dead util files
- Report: `.superpowers/sdd/task-C-F7-report.md`

**Interfaces:**
- Consumes: C-I7 report (AUTHORITATIVE dead-file census); C-F0 formatter + grow helper.
- Produces: dead util files deleted; formatting/sort/grow unified.

- [ ] **Step 1: Delete the 7 dead/effective-dead util files** (C-I7 R1): `util/growable_array.zig`, `util/main.zig` (non-compiling), `util/lexer_tests.zig`, `util/test_utils.zig`, `util/sort.zig`, `util/diagnostic_sort.zig`, `util/util.zig` — **plus** remove the now-dead `const util_mod = @import("util/util.zig")` at `source_manager.zig:6` in the same commit (C-I7 Concern #2). All byte-identity-safe (0 compiler importers).
- [ ] **Step 2: Integer-formatting unification** (C-I7 H2): delete `lexer.zig:706-723`, `diagnostics.zig:136-150`, `tests/lexer_tests.zig:63-80`; route the itoa→slice→write idiom onto the C-F0-chosen formatter + `pal.zig:139` `markerWriteInt`. **Preserve per-caller slice math exactly** (diagnostics `[16-len..16]` no-null vs format `[start..len-1]`) — verify stderr/diagnostic baselines.
- [ ] **Step 3: Re-point 6 typed-list grow bodies** (C-I7 H1/A1): `growable_array.zig:20-32/121-133/163-175/205-217/249-261` + `diagnostics.zig:193-216` onto C-F0 `growArrayEnsureCapacity` (completes in-place for the 5 typed lists; 7 importing modules).
- [ ] **Step 4: Map-boilerplate consolidation** (C-I7 H4): share grow/zero/rehash primitives across the 3 hash maps (`util/hash.zig`), parameterized by key/value byte sizes + key-mask fn. **Freeze** load factor (`count*4 >= cap*3`), probe order, `mapCapacityFromHint` sizing — verify 4 MD5s.
- [ ] **Step 5: `sortDiagnostics` single copy** (C-I7 H3): keep `diagnostics.zig:163-175`; the util duplicates are already deleted in Step 1.
- [ ] **Step 6: Related-span grow helper** (C-I7 H5): dedup the identical `sandAlloc+copy` branches at `diagnostics.zig:337-355`.
- [ ] **Step 7: Single OOM reporter** (C-I7 #7): `allocator.zig:67-74` → one `panicHandler` call (stderr only).
- [ ] **Step 8: Build + full gates**

Rebuild, reinstall std, 4 MD5s byte-identical, corpus 255, matrix, test_analyzer. **Do NOT touch `util/format.zig formatF64`** (emission path `c89_emit.zig:4554`).

- [ ] **Step 9: Commit + report**

Commit `refactor: consolidate infra/util (delete 7 dead util files, unify formatting/sort/map-grow)`. Report `.superpowers/sdd/task-C-F7-report.md`.

---

## Part 3 — Byte-identity-RISKY candidates (I tasks → ruling → F placeholders)

> Each C-R task investigates ONE risky consolidation: how to lower the byte-identity risk (order-preserving strategy, gate battery design, or scoping down to a safe subset). Reports → operator ruling → F placeholders filled.

### Task C-R1: name_cache/symbol-table lookup-order unification

**Files:**
- Read: `sf/src/type_resolver.zig` (:695-735, :710-733, :796-812), `sf/src/semantic_analyzer.zig` (:260-314, :772-775), `sf/src/const_alias_prepass.zig` (:162-182), `sf/src/symbol_registrator.zig` (:270-283)
- Report: `.superpowers/sdd/task-C-R1-report.md`

**Interfaces:**
- Consumes: C-I3 §2.2 + C-I4 D2 findings (4 divergent bare-name chains).
- Produces: risk-lowering strategy for `nameCacheResolveWithFallback` unification; the 4 green-guard repros (`r_fallback_*`) pin the order.

- [ ] **Step 1: Enumerate the 4 divergent chains** with exact resolution order + canonicalization/write-back behavior (C-I3 §1.1 table).
- [ ] **Step 2: Design a per-site behavior-preserving unification** — one helper that reproduces each site's exact chain (not one forced order). Identify which sites can share a single chain without changing `r_fallback_*` results.
- [ ] **Step 3: Risk assessment + gate plan** — how to prove byte-identity (4 MD5s + corpus incl. `r_fallback_*` repros + targeted shadowing repro). Recommend take/scope/rollback.
- [ ] **Step 4: Report + STOP**

Write report; present risk-lowering options to operator.

---

### Task C-R2: `isAssignable`/`classifyCoercion` unification

**Files:**
- Read: `sf/src/type_registry.zig` (:822-918 `typeRegistryIsAssignable`), `sf/src/coercion.zig` (:96-187 `classifyCoercion`)
- Report: `.superpowers/sdd/task-C-R2-report.md`

**Interfaces:**
- Consumes: C-I3 §1.4 (both ~80% structurally identical, already diverged: EU→EU isAssignable-only; wrap_error_err/ptr_to_optional_ptr classifyCoercion-only).
- Produces: risk-lowering strategy for unifying the two predicates (both feed emitted C89 via CoercionTable + diagnostics).

- [ ] **Step 1: Diff the two predicates** line-by-line (shared rules + each side's exclusives).
- [ ] **Step 2: Design a shared predicate** that preserves both call-site behaviors exactly (parameterized rule-set, or one predicate + both tables derived).
- [ ] **Step 3: Risk assessment + gate plan** — the CoercionTable feeds lowering/emission; diagnostics feed corpus classification. Recommend take/scope/rollback.
- [ ] **Step 4: Report + STOP**

---

### Task C-R3: local-decl SoA consolidation + triple-write (rtt+nc+sym)

**Files:**
- Read: `sf/src/semantic_analyzer.zig` (:222-249, :263-276, :1914-1922), `sf/src/lower.zig` (:602-634, :790-791, :1180-1188, :2060-2103), `sf/src/type_resolver.zig` (:1099-1122, :1195-1261), `sf/src/main.zig` (:426-464)
- Report: `.superpowers/sdd/task-C-R3-report.md`

**Interfaces:**
- Consumes: C-I3 §1.2 (local-decl duplication) + C-I4 D4 (triple-write overlap).
- Produces: risk-lowering strategy for both.

- [ ] **Step 1: Local-decl SoA** — enumerate the sema growable-array vs lowerer fixed-`[64]`+map vs analyzer StateMap variants; assess whether a shared structure can preserve the differing scope/lookup semantics (sema no scope_depth; lowerer has temp/kind/scope + map). C-I3 verdict was SKIP — investigate a SAFE subset (e.g. only the grow primitive, not the lookup).
- [ ] **Step 2: Triple-write** — assess whether `resolvedTypeTableSet` + `nameCachePut` + `sym.type_id` can share one bookkeeping helper without changing order-sensitive feeds.
- [ ] **Step 3: Risk assessment + gate plan** — recommend take/scope/rollback per sub-item.
- [ ] **Step 4: Report + STOP**

---

### Task C-R4: hoistTemps double-buffer + if_stmt/if_expr fold-guard merge

**Files:**
- Read: `sf/src/lower.zig` (:4861-4884 hoistTemps, :4048-4063 if_stmt fold, :3313-3331 if_expr fold)
- Report: `.superpowers/sdd/task-C-R4-report.md`

**Interfaces:**
- Consumes: C-I5 #12/#13.
- Produces: risk-lowering strategy for both.

- [ ] **Step 1: hoistTemps** — design an order-preserving in-place strategy (decls first, then originals) that avoids the new-insts double-buffer; assess gate (entry-block inst order is MD5-observable).
- [ ] **Step 2: if_stmt/if_expr fold-guard** — assess sharing the capture-free guard + dispatch while keeping the differing bodies; the if_expr fold is the fresh `b33f412a` path — guard must stay `payload==0`.
- [ ] **Step 3: Risk assessment + gate plan** — recommend take/scope/rollback.
- [ ] **Step 4: Report + STOP**

---

### Task C-R5: emission-order walker + emitted-text refactors

**Files:**
- Read: `sf/src/c89_emit.zig` (:818-976 tstEdgesCount/Fill/IsDep, :290-301/3746-4697 array loops, :4980-5452 cast arms, :205-231/4066-4210 variant-field, :1184-1196/1235-1247/2305-2316 guard-wrap, :4564-4597 string-escape, :3249-3680 #ifdef arms)
- Report: `.superpowers/sdd/task-C-R5-report.md`

**Interfaces:**
- Consumes: C-I6 #6/#9/#10/#11/#12/#14/#17.
- Produces: risk-lowering strategy for the emitted-text / emission-order refactors.

- [ ] **Step 1: tstEdgesCount walker** — assess whether an order-preserving single-walker can replace the 3× walk without changing topo-sort visit order (emission order is MD5-observable). This is the highest-risk item.
- [ ] **Step 2: Emitted-text helpers** (emitArrayCopy/emitCast/resolveVariantField/emitGuardWrap/string-escape/#ifdef-arm) — for each, design a helper that reproduces exact bytes (index var, spacing, newlines); each gets a differential-verify step (old vs new emitted text on the 4 gates + corpus).
- [ ] **Step 3: Risk assessment + gate plan** — rank by risk; recommend which to take, scope, or leave audit-only.
- [ ] **Step 4: Report + STOP**

---

## Part 4 — Gate sweep

### Task C-GATE: Final sweep + reconciliation

**Files:**
- Read: `repro/mi_matrix/EXPECTED_FAIL.md`, `docs/sf/QUICK_REF.md`
- Modify (if gate numbers moved): `repro/mi_matrix/EXPECTED_FAIL.md`, `docs/sf/QUICK_REF.md`

- [ ] **Step 1: Rebuild + reinstall std**
- [ ] **Step 2: 4 MD5 gates byte-identical** (gol/lisp/json/mud)
- [ ] **Step 3: Corpus 255 per-module recipe** — `OK=249/FAIL=2/ICE=0/CRASH=0/GG=4` unchanged
- [ ] **Step 4: 21-example matrix 21/21 + `test_analyzer_bin` "5 passed, 4 failed"**
- [ ] **Step 5: Reconcile docs + commit** — update `EXPECTED_FAIL.md` (version bump + closeout entry) and `QUICK_REF.md` if any gate number moved; commit all remaining F-task + gate changes with a summary message.
