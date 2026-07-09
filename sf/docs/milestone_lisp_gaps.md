# Milestone Lisp — Compiler Gaps for Lisp Interpreter Bootstrap

## 1. Executive Summary

The lisp interpreter (`examples/lisp_interpreter_curr/`, 10 files, 1009 lines) does not compile. 16 gaps across 5 subsystems prevent end-to-end compilation. The interpreter uses `try` (73x), `@ptrCast` (17x), `catch` (4x), `@ptrToInt` (2x), `@intToPtr` (2x), `continue`, `break`, `unreachable`, optional `?` types, and error unions. C89 emission is the bottleneck: 10 LIR instructions silently emit nothing (`else => {}` at c89_emit.zig:2834).

**Reference docs:** `sf/docs/milestone0.md` (pipeline + task format), `sf/docs/zig0_bootstrap_manual.md` (quirks §9, §6, §7, §8).


## 1.5 Wrapping Subsystem: CLOSED (v3)

`materializeInto` (`sf/src/lower.zig`) is the **sole** wrapper for optional/error_union of any nesting. It is reached only via `applyCoercion` delegation. Intent (`{value, null, error}`) is derived from the source AST node kind through `coercion.node_idx`. No `applyCoercion` wrap fallback exists.

Guarded by the **repro/mi_matrix** corpus (132 shapes) + `repro/mi_matrix/EXPECTED_FAIL.md` manifest. Lisp gate: **9→6** (the 3 eliminated were wrap-class errors).

Remaining lisp gate is **0** — **LISP FULLY COMPILES AND LINKS** (2026-07-05):
- **bug #3** — ~~undeclared void/comptime temps `zT_328–330`~~ **FIXED (commit 9f4d2095)** — comptime `@sizeOf`/`@alignOf` type args now resolved via canonical `resolveTypeExprFull`
- ~~`zT_329` undeclared in `zF_08D22E0F_eval`~~ **FIXED** — sema types `@sizeOf`/`@alignOf` as `TYPE_INT_LIT` so `count * @sizeOf(T)` no longer poisons the arithmetic result to VOID (undeclarable temp)
- ~~**G15/#6710** — Opt-from-int mismatch in `value_to_env_real`~~ **FIXED (commit c783cfc9)** — the mis-wrap was the **dead end-of-function epilogue** `emitValuelessReturn` (`lower.zig`), which for an error-union return synthesized `int_const(0)` and `wrap_error_ok`-ed it into the payload — invalid C when the payload is an aggregate (`?*EnvNode`). Now emits a **payload-typed** default (`nextTemp(eu_payload)`), valid C for any payload. The epilogue is emitted (dead) because the statement-switch handler unconditionally resets `block_terminated=0` after an all-returning switch (`lower.zig:3412`); skipping the dead epilogue entirely (LIR noreturn propagation) is deferred to a future LIR-improvement pass. Proven via EVR/SWEXIT/FNL markers (commits 1379a37, c4f56482); see `.superpowers/sdd/phase1-proof.md`.



## 1.6 Field-Store-Through-Pointer: WIRED (2026-07-07)

`store_field` (LIR since milestone0, `lir.zig:39`) was NEVER emitted by lowering, so `ptr.field = value` and `ptr.field OP= value` were universally mis-compiled (field loaded into a temp, assigned to the temp, never stored back) — silently breaking every runtime-exercised field store (lisp `self.pos = saved_pos`, `self.pos += 1`, `node.value = val`). Fixed by wiring `store_field` into the assignment lowerers:

- **Unified `lowerFieldStore` helper** (`lower.zig`) resolves the base (ptr-unwrap) and emits `store_field`; used by `plain_assign` + all 20 compound-assign sites (21 call sites, one impl). Commits `98d1c894`, `7e751257`, `26638c28`.
- **struct / pointer-to-struct**: real `base.field = v` / `base->field = v`.
- **slice `.ptr/.len` + tagged_union `.tag/.payload`**: added via **named field-index constants** in `type_registry.zig` (`SLICE_FIELD_PTR/LEN`, `TU_FIELD_TAG/PAYLOAD`) + emitter suffix-pending flag. Commit `0587ff35`.
- **Legacy bare-`0/1` field-index literals** (24 sites in `lower.zig`/`c89_emit.zig`) migrated to those constants — behavior-neutral, byte-identical. Commit `8f10bf2e`.
- **union field stores** (`v.data.Int = val`) remain **ICE'd** (`iceFieldStoreUnsupported`, ERR_9001) — a separate NESTED l-value chain bug, tracked, out of scope.
- Two-layer defensive ICE (unsupported base kind in `lowerFieldStore` + `found2==0` in emitter) — no silent mis-emit.

**zig1-lisp COMPILES but does NOT yet fully RUN.** The REPL now advances, but crashes on list expressions containing a number/atom: a **separate field-LOAD bug** — `self.input[start..self.pos]` drops the `load_field` for the slice END operand (`self.pos`) → uninitialized end → crash in `parse_int_simple`. The LOAD mirror of the store bug; tracked as a NEW plan. mandelbrot/game_of_life run correctly; corpus 117/14/1; byte-identical maintained.


## 1.7 Address-Of L-Value: FIXED (2026-07-08, Task 7)

The **deref-store-through-pointer** bug was fixed earlier (`ptr.* = X` / `ptr.* op= x` → `*ptr = ...` via `lowerDerefStore`, commits `5090d25a`, `55c20ff5`, `9d44671e`). Task 7 now **also fixes** the `address_of` scalar/deref/paren l-value family by consolidating the handler into a `lowerLValueAddr` dispatch (`lower.zig`, symmetric to the assignment-side l-value dispatch):

- **FIXED — address-of a scalar local/param (`&n`, `&param`):** previously lowered to `&(loaded copy)` (`operand=lowerExpr(child)` returned a `load_local` temp), so a store through the pointer silently no-op'd the caller's variable. Now, for a scalar local `ident_expr`, `lowerLValueAddr` emits `addr_of{ operand = findLocalTemp(name_id) }` — the **real** decl temp, which resolves via the emitter `fl_temps`/`resolveTempName` → `mangleLocalName` to `&<name>` (e.g. `&n`). **No new LIR was needed** (Task 7 Step 1 verified empirically: `addr_of` of the scalar's decl temp, incl. temp id 0, renders as `&n`, not `&zT_0`).
- **FIXED — `&(p.*)` / `&p.*` (deref):** now an identity — returns the pointer temp (`lowerExpr(child_0)`), no `addr_of`. **`&(expr)` (paren):** recurses into the inner l-value.
- **UNCHANGED (still correct, byte-identical):** `&arr[i]` (`index_access` base+idx, moved verbatim), `&struct`/`&slice`/`&tagged`/`&array` (aggregate idents return the real local temp; helper routes them through the existing `lowerExpr`+`addr_of` path), and address-of a global ident (kept on the current path).
- **STILL A GAP (documented, ICE):** `&base.field` (field-address of a value/struct field) — there is **no** `&base.field` emit (`addr_of` only emits `&<temp>`), so `field_access` l-values ICE via `iceAddrOfLValueUnsupported`. Zero occurrences in the corpus/gate programs (all field-address code is `&ptr.field[idx]`, i.e. outermost `index_access`, already handled). Deferred to a follow-up if ever needed.
- **Repros GREEN:** `repro/deref_store_scalar_addr` (`15`), `repro/deref_store_param_addr` (`&scalar_param` → `15`), `repro/addr_of_deref` (`&(p.*)` → `15`), plus `repro/deref_store_aggregate` (`16`) and `repro/deref_store_compound` (`&arr[0]` → `15`). man/gol/mud `--dump-c89` byte-identical vs parent (they use no broken form); corpus `117/14/1`.



## 1.8 Store-Side L-Value Dispatch: UNIFIED (2026-07-08, store-lvalue-dispatch-unify)

The store side of the l-value grammar previously had **two divergent dispatches** — inline in `plain_assign` and in `lowerCompoundLValueStore` — which disagreed on three l-value forms. They are now unified into **one shared, l-value-node-keyed helper `lowerAssignLValue(self, lv_node_idx, value_temp, diag_node_idx)`** (`lower.zig`), structurally symmetric with the address-side `lowerLValueAddr` (§1.7). Both `plain_assign` (value = `src`) and all 20 compound-assign handlers (value = `op_r`, via a thin `lowerCompoundLValueStore` wrapper) route through it. The helper dispatches `ident_expr` (`store_local` + conditional `assign`), `index_access` (`assign_index`, logic reproduced verbatim from the old plain path), `field_access` (`lowerFieldStore`), `deref` (`lowerDerefStore`), `paren_expr` (**recurses** on `child_0`), else (`iceAssignLValueUnsupported`).

- **FIXED — `(p.*) = x` (paren-plain):** previously hit the plain `else` → **hard ICE** (`ERR_9001`). Now the `paren_expr` recursion reaches the inner `deref` → real `*ptr = x` store. Handles nesting (`((p.*)) = x`) via recursion (the parser wraps once per `(`, so a 1-level unwrap would be incomplete).
- **FIXED — `(p.*) += x` (paren-compound):** previously hit the compound `else` → **silent `assign{dst=loaded-copy}`** → store DROPPED. Now stores correctly via the same paren recursion.
- **FIXED — `arr[i] += x` (index-compound):** the compound path had **no `index_access` branch** → fell to `else` → silent store DROP (load-index copy). The shared helper now emits a real `assign_index` (same bug class as the deref/field store bugs fixed earlier; compound simply never got an index branch).
- **RECONCILED — compound `else` silent-drop → loud ICE:** the compound `else` now calls `iceAssignLValueUnsupported` (matching the plain side) instead of silently emitting `assign{dst=lhs_val}` (a write into a loaded copy that never stored). Empirically gated: fires on **nothing** valid across lisp/man/gol/mud/corpus (0 occurrences); the only valid form its old `else` ever swallowed was `index_access`, which now has its own branch.
- **UNCHANGED (byte-identical):** plain `ident`/`index_access`/`field`/`deref`/`else` and compound `ident`/`field`/`deref` — same LIR (only stderr-only `pal.markerWrite` markers were dropped in the consolidation; they never appear in `--dump-c89`).
- **0-occurrence caveat:** all three fixed forms appear in **no** gate program, so man/gol/mud stay `--dump-c89` byte-identical; their correctness is **RUNTIME-verified** by new RED→GREEN repros: `repro/paren_deref_store` (`16`, incl. nested `((p.*))`), `repro/paren_compound_store` (`15`), `repro/index_compound_store` (`15`). Corpus `117/14/1`.

`lowerAssignLValue` is now the **sole store-side l-value dispatch**, mirroring `lowerLValueAddr` on the address side.



## 2. Gap Inventory
| # | Subsystem | File | Gap | Severity | Status |
|---|-----------|------|-----|----------|--------|
| G1 | Parser | `parser.zig:1100` | decl_buf[64] overflow → AST shared_store corruption | Critical | ✅ |
| G2 | Parser | `parser.zig:297-301` | dot_star token not handled in postfix chain → `x.*` universal failure | Critical | ✅ |
| G3 | Sema+Lowerer | `sema.zig:838`, `lower.zig:1576` | @ptrCast builtin_call → name dispatch + type resolution + ptr_cast LIR | High | ✅ |
| G4 | Parser+Sema+Lowerer | `parser.zig:239`, `sema.zig:853`, `lower.zig:1622` | catch \|err\| capture + nested save/restore + addLocalDecl | High | ✅ |
| G5 | c89_emit | `c89_emit.zig:2834` | check_error + unwrap_error_payload + unwrap_error_code → no C code | Critical | ✅ |
| G6 | c89_emit | `c89_emit.zig:2834` | wrap_error_ok + wrap_error_err → no C code | High | ✅ |
| G7 | c89_emit | `c89_emit.zig:2834` | check_optional + unwrap_optional → no C code | Medium | ✅ |
| G8 | c89_emit | `c89_emit.zig:2834` | ptr_cast → no C code | High | ✅ |
| G9 | Sema+Lowerer+c89 | `sema.zig:873`, `lower.zig:1590`, `c89_emit.zig:2965` | ptr_to_int + int_to_ptr — missing 3-layer pipeline | Medium | ✅ |
| G10 | c89_emit | `c89_emit.zig:1264` | Single-file --dump-c89 output duplication (module emitted 2×) | High | ✅ |
| G11 | Parser | `parser.zig:829` | Infix `!` in type parser (T!U, e.g., `LispError!*Value`) | Critical | ✅ |
| G12 | Parser | `parser.zig:601` | `error{}` in expression position — parserParseErrorLiteral expects `.Foo`, needs `{` delegation | Critical | ✅ |
| G13 | Parser/Sema | `parser.zig:601` | `error.Foo` literal — parsed end-to-end but needs error set context for sema resolution | High | ✅ |
| G14 | Sema | `main.zig:575` | `resolveAllFnTypes` strips error union → fn return type is `void` not `!T` | Critical | ❌ |
| G15 | Lowerer | `lower.zig:1602-1621` | `try`/`catch` error union temps get `TYPE_VOID` — coercion chain broken | Critical | ❌ |
| G16 | Lowerer/c89 | `lower.zig`/`c89_emit.zig:2999` | `decl_local` LIR not emitted for all `addLocalDecl` names → 94 undeclared C identifiers | High | ❌ |
| G17 | c89_emit | `c89_emit.zig:350-438` | `i64`/`u64` types emit as `z64`/`zu64` → unknown type name in C89 | Medium | ❌ |
| G18 | Sema/Lowerer | `sema.zig`/`lower.zig` | Coercion chain missing for error union patterns (`return try`, `return error.Foo`) | High | ❌ |
| G19 | c89_emit | `c89_emit.zig:1264` | Multi-module output duplication — functions emitted 2-3× (T9 regression) | Critical | ✅ |
| G20 | main.zig | `main.zig:535` | resolveTypeExprDepth missing field_access handler — cross-module qualified types return UNDEFINED | Critical | ❌ |
| G21 | c89_emit | `c89_emit.zig:525` | getCTypeName EU handler — self-reliant, no c_name_id dependency | Medium | ✅ |
| G22 | c89_emit | `c89_emit.zig:528` | ptr_type getCTypeName all returns 'unsigned char*' → EU name dedup collision | High | ❌ |
| G23 | c89_emit | `c89_emit.zig:754` | EnvNode struct typedef missing — unnamed guard skips struct_type | High | ❌ |
| G24 | c89_emit | `c89_emit.zig:529` | Non-deterministic EU name — same payload different hash prefix | Medium | ❌ |
| G25 | Lowerer | `lower.zig:3117` | func.return_type TYPE_VOID persists — RTT lookup fails for some functions | High | ❌ |
| G26 | c89_emit/lowerer | `emitHoistedDecls` | Undeclared locals in void-return functions — cascade from G25 | Medium | ❌ |
| G27 | Lowerer | `lower.zig:2977` | `lowerExprImpl` returns 0 for `AstKind.block` (void `{}` expr) → coercion into `E!void` flows temp-0 into `materializeInto`/`getTempType`. Now caught by ICE guards (ERR_9001) — was silent SEGV. Root unfixed, out of scope (block expr needs a void temp). | High | ❌ |
| B3 | ComptimeEval | `comptime_eval.zig:56` | `comptimeEvalResolveTypeArg` now delegates to canonical `resolveTypeExprFull` (handles `ptr_type`/`many_ptr_type`/`field_access`/etc.) → `@sizeOf`/`@alignOf(*T)` fold correctly | Critical | ✅ Fixed (9f4d2095) |
| B4 | Lowerer | `lower.zig:~3164` | `while_stmt` branches on raw `cond_temp` without `check_optional` (unlike if/orelse at `:2338`/`:3081`) → C output `if(cur)` on raw optional struct instead of `if(cur.has_value)` | Critical | ⚠️ Attrib (Lower) |
| G28 | Lowerer | `lower.zig` `lowerLValueAddr` | **FIXED (Task 7):** `address_of` consolidated into `lowerLValueAddr`. Scalar local/param `&n`/`&param` now `addr_of{ findLocalTemp(name_id) }` → `&<name>` (was `&`load-copy). `&(p.*)`/paren fixed; `&arr[i]`/`&struct`/`&slice`/`&tagged`/global unchanged (byte-identical). `&base.field` field-address ICEs (documented gap, 0 corpus uses). Repros GREEN: `deref_store_scalar_addr`/`deref_store_param_addr`/`addr_of_deref` (all 15). | High | ✅ |
| G29 | Lowerer | `lower.zig` `lowerAssignLValue` | **FIXED (store-lvalue-dispatch-unify):** store-side l-value dispatch unified into `lowerAssignLValue` (sole store dispatch, mirrors `lowerLValueAddr`); `plain_assign` + 20 compound handlers (via `lowerCompoundLValueStore` wrapper) route through it. Fixes `(p.*)=x` (was hard ICE), `(p.*)+=x` + `arr[i]+=x` (were silent store-drops); compound `else` silent-drop → loud ICE (empirically fires on nothing valid). All else byte-identical. Repros GREEN: `paren_deref_store` (16, incl. nested `((p.*))`), `paren_compound_store` (15), `index_compound_store` (15). | High | ✅ |
| G30 | Lowerer + Emitter | `lower.zig` struct_init (`~2607`) + `c89_emit.zig` `emitFieldAssign`/`store_field` | **FIXED (tagged-union-payload-store Tasks 1-3):** tagged-union struct-init previously wrote only the `.tag`, dropping the payload (`Value{.Int=n}` → garbage). Lowerer now emits a void-guarded payload `assign_field{ TU_FIELD_PAYLOAD, src }`; emitter resolves `.payload.<Variant>._<sub>` on BOTH write branches by SRC-temp type (mirrors read path). Void variants emit no store (gol byte-identical). Also anon-`.{}` init type inferred via `expected_type_stack` (Task 4) so mud `.Go` returns store correctly. Repros GREEN: `tagged_union_payload` (payload stored; residual 84 = G31-sibling capture bug T29), `tagged_union_anon_return`, `anon_init_var_decl`/`if_arm`. | High | ✅ |
| G31 | Lowerer/Emitter/Sema | `comptime_eval.zig`, `main.zig:377` | **SEPARATE / DEFERRED:** negative-literal `@intCast(iN,-k)` aborts zig1 at compile (`PANIC: integer overflow in @intCast`, rc=134). Untyped modular-u64 comptime evaluator: negate `0-v` wraps (`comptime_eval.zig:103-107`), @intCast fold discards target (`:85-88`), checked u32 store panics (`main.zig:377`). Approach-(a) mask REJECTED as rot; correct fix = typed `(value,width,signed)` comptime values. RED repro `repro/negative_intcast_ice` (dc40af40). FIX = separate plan `.opencode/plans/2026-07-09-typed-comptime-values.md`. | Medium | ❌ |
| G32 | Lowerer | `lower.zig:2262-2275` fold site | **FIXED (tagged-union-payload-store Task 10):** comptime-folded `@intCast` value temp was minted `TYPE_USIZE`, ignoring the cast target (root cause of the Task 3 out-of-contract retype patch). Now types the folded temp by its sema-resolved target via boxed `nextTemp(fold_ty_box[0])` — reads `resolvedTypeTableGet`, NO `hoisted_temps` post-hoc mutation; narrow guard excludes `@sizeOf`/`@alignOf`/`@ptrToInt`/`@intCast(usize)`. Task 3 retype patch (`lower.zig:2627-2629`) REMOVED. Repro `repro/comptime_fold_typed_payload` GREEN=42. man/gol byte-identical; mud rebaselined (oracle-correct `@intCast(u8,N)` → `unsigned char`, runtime-identical). | High | ✅ |


## 3. Task Details

**NOTE: Task IDs were renumbered on 2026-06-14. Section headers (T1, T2, T1.5) are legacy. See §5 Progress Tracking for canonical IDs (T1–T11).**

---

### T1: Fix Import Resolution Segfault

**File:** `sf/src/parser.zig` (parserParseModuleRoot), `sf/src/import_resolver.zig` (moduleRegistryResolveImports)

**Root cause (verified 2026-06-14):** `parserParseModuleRoot` (parser.zig:1100) used a fixed-size `[64]u32` stack buffer (`decl_buf`) for top-level declarations. Lisp eval.zig (469 lines, 18684 bytes) has >64 top-level declarations → buffer overflowed, writing node indices past the stack array into adjacent stack variables (return addresses, other locals). These garbage values were stored in `extra_children[1733]` → later read by `registerModuleSymbols` as `decls.ptr[67]` = 0xFFA72268 (stack pointer) → crash at `registerDecl` accessing `nodes.items[garbage]`.

**Fix applied:**
1. Migrated `import_resolver.zig` markers to `markerWriteInt` (removed crash-in-marker at line 626 — `nodes.items[decls[di2]]` was marker debug code, not logic)
2. Replaced `decl_buf[64]` with dynamic `decl_buf_items/len/capacity` on Parser struct (same pattern as `child_buf_items`, allocates via parser scratch arena)
3. Moved `registerModuleSymbols` marker code to use `markerWriteInt` (prints node index only, skips `nodes.items` lookup)

**Verification:** Lisp no longer crashes (EXIT=2 = diagnostics, not segfault). Mud_server: 0 errors, 1505 lines. No file-size limit on top-level declarations.

**Status:** ✅

---

### P1: Diagnose Parse Errors in eval.zig

**Status: ✅ (Resolved by T2 — dot-star fix)**

**[Removed — covered by T2 below]**

---

### T1.5: Diagnose + Fix `*Module.Type` Parser Gap

**Status: ✅ (Resolved — root cause was dot_star lexer token, not *Module.Type)**

**[Removed — covered by T2 below]**

---

### T2: @ptrCast End-to-End

**Files:** `sf/src/semantic_analyzer.zig`, `sf/src/lower.zig`, `sf/src/c89_emit.zig`

**Design reference:** `lir.zig:56` — `ptr_cast: struct { value: u32, target: TypeId, result: u32 }`. Already used in coercion system (`lower.zig:3009` — `CoercionKind.ptr_child_cast` emits `ptr_cast`).

**Lisp usage:** `@ptrCast([*]u8, &perm_buf_u64)` at `main.zig:104`.

**Zig0 quirk:** Follow `@intCast` pattern in lowerer.zig (`lowererInit` registers `intcast_name_id` at line 241-242, `builtin_call` handler matches by `node.child_0` at line 1579). String interning requires named variable (quirk §9.3).

**Plan T2a — Sema (sema.zig builtin_call handler line 838):**
```zig
// In semanticAnalyzerInit (line 48-73): add field
ptrcast_name_id: u32,
// In init body, after existing code:
var ptrcast_s: []const u8 = "@ptrCast";
.ptrcast_name_id = si_mod.stringInternerIntern(interner, ptrcast_s),

// In resolveExpr builtin_call handler (line 838-844), BEFORE existing generic branch:
if (node.child_0 == self.ptrcast_name_id) {
    var ec = astStoreGetExtraChildren(self.store, node.payload);
    if (ec.len >= 2) {
        var ty_child = ec[0];  // target type AST node (e.g., [*]u8)
        var val_child = ec[1]; // value expression
        _ = semanticAnalyzerResolveExpr(self, val_child);
        // Resolve target type: call resolveExpr on ty_child → TYPE_TYPE,
        // then get RTT[ty_child] which should be the resolved pointer type.
        // Or call resolveTypeExpr if available from main.zig context.
        // Store result in RTT[node_idx] = resolved_ptr_type.
    }
    result = TYPE_VOID;
    break; // or return
}
// Existing generic branch (resolveExpr on ec[0]) stays as fallback.
```

**Plan T2b — Lowerer (lower.zig builtin_call handler line 1576):**
```zig
// In lowererInit (line 240-271): add field after inttofloat_name_id
ptrcast_name_id: u32,
// In init body:
var ptrcast_s: []const u8 = "@ptrCast";
.ptrcast_name_id = si_mod.stringInternerIntern(ctx.registry.interner, ptrcast_s),

// In builtin_call handler (line 1576-1601), add before existing intCast check:
} else if (node.child_0 == self.ptrcast_name_id) {
    var t_target = self._fn_ret_type; // fallback; resolve from ec[0]
    var ec = ast_mod.astStoreGetExtraChildren(store, node.payload);
    var val_temp = lowerExpr(self, ec[@intCast(usize, 1)]);
    // Resolve target type from ec[0] — look up in RTT or name_cache
    var ty_node = store.nodes.items[@intCast(usize, ec[@intCast(usize, 0)])];
    if (ty_node.kind == AstKind.many_ptr_type or ty_node.kind == AstKind.ptr_type) {
        // Use resolveTypeExpr (from main.zig) or read from resolved_types
        var rt = resolved_mod.resolvedTypeTableGet(self.ctx.resolved_types, ec[@intCast(usize, 0)]);
        if (rt) |t| { t_target = t; }
    }
    var result = nextTemp(self, t_target);
    emitInst(self, LirInst{ .ptr_cast = .{
        .value = val_temp, .target = t_target, .result = result,
    } });
    return result;
} else if (node.child_0 == self.intcast_name_id) {
```

**Plan T2c — c89_emit (emitInst, before `else => {}` at line 2834):**
```zig
// Follow .int_cast unchecked pattern (line 2743-2753):
.ptr_cast => |c| {
    var dst = resolveTempName(emitter, c.result);
    var src = resolveTempName(emitter, c.value);
    var ctype_s: []const u8 = "CT:n"; pal_markerWrite(ctype_s);
    // ... optional itoa marker for c.target ...
    var ctype = getCTypeName(emitter.registry, emitter.mangler, c.target);
    bufferedWriterWriteIndent(&emitter.writer, emitter.indent);
    bufferedWriterWrite(&emitter.writer, dst);
    var s1: []const u8 = " = (";
    bufferedWriterWrite(&emitter.writer, s1);
    bufferedWriterWrite(&emitter.writer, ctype);
    var s2: []const u8 = ")";
    bufferedWriterWrite(&emitter.writer, s2);
    bufferedWriterWrite(&emitter.writer, src);
    var s3: []const u8 = ";\n";
    bufferedWriterWrite(&emitter.writer, s3);
},
```

**Zig0 constraints for T2c:**
- All string fragments MUST be named variables (quirk §9.3: "string literal not wrapped" → `" = ("` must be `var s1: []const u8 = " = (";`)
- `resolveTempName`, `getCTypeName`, `bufferedWriterWrite` are free functions (quirk §6: no methods)
- `@intCast(usize, ...)` for all indices (quirk §9.7)

---

### T3: Error Union Check + Unwrap (D1, D2, D3)

**File:** `sf/src/c89_emit.zig`

**Design reference:** `c89_emit.zig:1034-1115` — `emitOptionalType` and `emitErrorUnionType` generate C structs:
```
// EU with void payload:   typedef struct { int err; int is_error; } EU_Name;
// EU with non-void payload: typedef struct { union { T payload; int err; } data; int is_error; } EU_Name;
// Optional:                 typedef struct { T value; int has_value; } Opt_Name;
```

**Root cause:** Lowerer emits `check_error{value, result}`, `unwrap_error_payload{value, result}`, `unwrap_error_code{value, result}` — all fall to `else => {}` (c89_emit.zig:2834). The `result` temp is never initialized → branch on garbage → silent runtime failure.

**Flow for `try expr` (lower.zig:1602-1621):**
```
1. check_error  value=lhs  result=is_err_bool   → [NO-OP, is_err_bool uninit]
2. branch       cond=is_err_bool  then=err  else=ok  → [branch on uninit]
3. (ok path) unwrap_error_payload  value=lhs  result=ok_temp  → [NO-OP]
4. (err path) ret  lhs  → [returns the error union itself]
```

**Plan D1 — `.check_error` handler:**
```zig
.check_error => |e| {
    // Pattern: result = !value.is_error;
    var dst = resolveTempName(emitter, e.result);
    var src = resolveTempName(emitter, e.value);
    bufferedWriterWriteIndent(&emitter.writer, emitter.indent);
    bufferedWriterWrite(&emitter.writer, dst);
    var s1: []const u8 = " = !";
    bufferedWriterWrite(&emitter.writer, s1);
    bufferedWriterWrite(&emitter.writer, src);
    var s2: []const u8 = ".is_error;\n";
    bufferedWriterWrite(&emitter.writer, s2);
},
```
**C output:** `zT_N = !zT_M.is_error;`

**Plan D2 — `.unwrap_error_payload` handler:**
```zig
.unwrap_error_payload => |e| {
    // Pattern: result = value.data.payload;
    var dst = resolveTempName(emitter, e.result);
    var src = resolveTempName(emitter, e.value);
    bufferedWriterWriteIndent(&emitter.writer, emitter.indent);
    bufferedWriterWrite(&emitter.writer, dst);
    var s1: []const u8 = " = ";
    bufferedWriterWrite(&emitter.writer, s1);
    bufferedWriterWrite(&emitter.writer, src);
    var s2: []const u8 = ".data.payload;\n";
    bufferedWriterWrite(&emitter.writer, s2);
},
```
**C output:** `zT_N = zT_M.data.payload;`

**Plan D3 — `.unwrap_error_code` handler:**
```zig
.unwrap_error_code => |e| {
    // Pattern: result = value.data.err;
    var dst = resolveTempName(emitter, e.result);
    var src = resolveTempName(emitter, e.value);
    bufferedWriterWriteIndent(&emitter.writer, emitter.indent);
    bufferedWriterWrite(&emitter.writer, dst);
    var s1: []const u8 = " = ";
    bufferedWriterWrite(&emitter.writer, s1);
    bufferedWriterWrite(&emitter.writer, src);
    var s2: []const u8 = ".data.err;\n";
    bufferedWriterWrite(&emitter.writer, s2);
},
```
**C output:** `zT_N = zT_M.data.err;`

---

### T4: Error Union Wrap (D6, D7)

**File:** `sf/src/c89_emit.zig`

**Design reference:** 
- `c89_emit.zig:2705-2719` — `.wrap_optional` emits two-field assignment pattern. Follow this EXACTLY.
- `c89_emit.zig:1073-1115` — `emitErrorUnionType` generates TWO C struct layouts:
  - **Void payload:** `typedef struct { int err; int is_error; } EU_Name;` (NO `.data` field)
  - **Non-void payload:** `typedef struct { union { T payload; int err; } data; int is_error; } EU_Name;` (HAS `.data.payload` / `.data.err`)
- `type_registry.zig:68` — `EUPayload = struct { payload: TypeId, error_set: TypeId }` — use `.payload` field to check void.

**Lowerer flow** (`applyCoercion`, lower.zig:2979-2986):
- `wrap_error_success` → emits `wrap_error_ok{value, result, type_id}`
- `wrap_error_err` → emits `wrap_error_err{value, result, type_id}`

**LIR instruction** (`lir.zig:48-49`):
- `wrap_error_ok: struct { value: u32, result: u32, type_id: TypeId }`
- `wrap_error_err: struct { value: u32, result: u32, type_id: TypeId }`

**CRITICAL — Void payload check:** Both handlers MUST look up `w.type_id` → `eu_items[payload_idx].payload` → check `kind == void_type` → use different field paths for void vs non-void error unions. Without this check, `wrap_error_ok` emits `.data.payload` on a `!void` struct with no `.data` field → GCC "has no member named 'data'" error.

---

**Plan D6 — `.wrap_error_ok` handler:**
```zig
.wrap_error_ok => |w| {
    var dst = resolveTempName(emitter, w.result);
    var src = resolveTempName(emitter, w.value);
    var eu_ty = emitter.registry.types_items[@intCast(usize, w.type_id)];
    var eu = emitter.registry.eu_items[@intCast(usize, eu_ty.payload_idx)];
    var pay_ty = emitter.registry.types_items[@intCast(usize, eu.payload)];
    var is_void: u8 = @intCast(u8, if (pay_ty.kind == type_mod.TypeKind.void_type) @as(u8, 1) else @as(u8, 0));
    if (is_void != @intCast(u8, 0)) {
        bufferedWriterWriteIndent(&emitter.writer, emitter.indent);
        bufferedWriterWrite(&emitter.writer, dst);
        var l1: []const u8 = ".err = 0;\n"; bufferedWriterWrite(&emitter.writer, l1);
        bufferedWriterWriteIndent(&emitter.writer, emitter.indent);
        bufferedWriterWrite(&emitter.writer, dst);
        var l2: []const u8 = ".is_error = 0;\n"; bufferedWriterWrite(&emitter.writer, l2);
    } else {
        bufferedWriterWriteIndent(&emitter.writer, emitter.indent);
        bufferedWriterWrite(&emitter.writer, dst);
        var l1: []const u8 = ".data.payload = "; bufferedWriterWrite(&emitter.writer, l1);
        bufferedWriterWrite(&emitter.writer, src);
        var semi1: []const u8 = ";\n"; bufferedWriterWrite(&emitter.writer, semi1);
        bufferedWriterWriteIndent(&emitter.writer, emitter.indent);
        bufferedWriterWrite(&emitter.writer, dst);
        var l2: []const u8 = ".is_error = 0;\n"; bufferedWriterWrite(&emitter.writer, l2);
    }
},
```
**C output (void):**
```
zT_N.err = 0;
zT_N.is_error = 0;
```
**C output (non-void):**
```
zT_N.data.payload = zT_M;
zT_N.is_error = 0;
```

---

**Plan D7 — `.wrap_error_err` handler:**
```zig
.wrap_error_err => |w| {
    var dst = resolveTempName(emitter, w.result);
    var src = resolveTempName(emitter, w.value);
    var eu_ty = emitter.registry.types_items[@intCast(usize, w.type_id)];
    var eu = emitter.registry.eu_items[@intCast(usize, eu_ty.payload_idx)];
    var pay_ty = emitter.registry.types_items[@intCast(usize, eu.payload)];
    var is_void: u8 = @intCast(u8, if (pay_ty.kind == type_mod.TypeKind.void_type) @as(u8, 1) else @as(u8, 0));
    if (is_void != @intCast(u8, 0)) {
        bufferedWriterWriteIndent(&emitter.writer, emitter.indent);
        bufferedWriterWrite(&emitter.writer, dst);
        var l1: []const u8 = ".err = "; bufferedWriterWrite(&emitter.writer, l1);
        bufferedWriterWrite(&emitter.writer, src);
        var semi1: []const u8 = ";\n"; bufferedWriterWrite(&emitter.writer, semi1);
        bufferedWriterWriteIndent(&emitter.writer, emitter.indent);
        bufferedWriterWrite(&emitter.writer, dst);
        var l2: []const u8 = ".is_error = 1;\n"; bufferedWriterWrite(&emitter.writer, l2);
    } else {
        bufferedWriterWriteIndent(&emitter.writer, emitter.indent);
        bufferedWriterWrite(&emitter.writer, dst);
        var l1: []const u8 = ".data.err = "; bufferedWriterWrite(&emitter.writer, l1);
        bufferedWriterWrite(&emitter.writer, src);
        var semi1: []const u8 = ";\n"; bufferedWriterWrite(&emitter.writer, semi1);
        bufferedWriterWriteIndent(&emitter.writer, emitter.indent);
        bufferedWriterWrite(&emitter.writer, dst);
        var l2: []const u8 = ".is_error = 1;\n"; bufferedWriterWrite(&emitter.writer, l2);
    }
},
```
**C output (void):**
```
zT_N.err = zT_M;
zT_N.is_error = 1;
```
**C output (non-void):**
```
zT_N.data.err = zT_M;
zT_N.is_error = 1;
```

---

**Zig0 constraints for T4:**
- Same two-line pattern as `.wrap_optional` at line 2705 (proven working)
- All strings in named variables (quirk §9.3)
- Indent must be explicitly written per line (not auto-indented by bufferedWriter)
- Void check uses `emitter.registry` (available as `*TypeRegistry` in emitter struct) and `type_mod.TypeKind.void_type` (imported via `const type_mod = @import("type_registry.zig")`)
- Lisp interpreter uses `!*value_mod.Value` (non-void) — void branch won't be exercised by T8, but must be correct for completeness

---

### T5: Optional Check + Unwrap (D4, D5)

**File:** `sf/src/c89_emit.zig`

**Note:** Lisp interpreter does NOT use `orelse`. But D4+D5 fix `orelse` for free and unblocks future `if(opt)|x|`.

**C struct** from `emitOptionalType` (line 1034): `typedef struct { T value; int has_value; } Opt_Name;`

**Plan D4 — `.check_optional` handler:**
```zig
.check_optional => |e| {
    var dst = resolveTempName(emitter, e.result);
    var src = resolveTempName(emitter, e.value);
    bufferedWriterWriteIndent(&emitter.writer, emitter.indent);
    bufferedWriterWrite(&emitter.writer, dst);
    var s1: []const u8 = " = ";
    bufferedWriterWrite(&emitter.writer, s1);
    bufferedWriterWrite(&emitter.writer, src);
    var s2: []const u8 = ".has_value;\n";
    bufferedWriterWrite(&emitter.writer, s2);
},
```
**C output:** `zT_N = zT_M.has_value;`

**Plan D5 — `.unwrap_optional` handler:**
```zig
.unwrap_optional => |e| {
    var dst = resolveTempName(emitter, e.result);
    var src = resolveTempName(emitter, e.value);
    bufferedWriterWriteIndent(&emitter.writer, emitter.indent);
    bufferedWriterWrite(&emitter.writer, dst);
    var s1: []const u8 = " = ";
    bufferedWriterWrite(&emitter.writer, s1);
    bufferedWriterWrite(&emitter.writer, src);
    var s2: []const u8 = ".value;\n";
    bufferedWriterWrite(&emitter.writer, s2);
},
```
**C output:** `zT_N = zT_M.value;`

---

### T6: @ptrToInt / @intToPtr End-to-End (D9, D10)

**Files:** `sf/src/semantic_analyzer.zig`, `sf/src/lower.zig`, `sf/src/c89_emit.zig`

**Problem:** `emitHoistedDecls` has type-tracking for `ptr_to_int`→`TYPE_USIZE` and `int_to_ptr`→`itp.target` (c89_emit.zig:1620-1637) but these handlers are **dead code** — never reached. The lowerer never emits `ptr_to_int` or `int_to_ptr` LIR because there is no sema dispatch and no lowerer dispatch for `@ptrToInt`/`@intToPtr` builtins. Three layers are missing.

**Pattern reference:** `@ptrCast` (T2, completed) — same 3-layer pipeline: sema name_ids + dispatch → lowerer name_ids + LIR emission → c89 emitInst handlers.

---

**Plan T6a — Sema (`semantic_analyzer.zig`, ~7 lines):**

1. Add fields to `SemanticAnalyzer` struct (~L45):
```zig
ptrtoint_name_id: u32,
inttoptr_name_id: u32,
```

2. Intern name strings in `semanticAnalyzerInit` (~L75):
```zig
var pti_s: []const u8 = "@ptrToInt";
var ptin_id = si_mod.stringInternerIntern(interner, pti_s);
var itp_s: []const u8 = "@intToPtr";
var itp_id = si_mod.stringInternerIntern(interner, itp_s);
// ... in return struct:
.ptrtoint_name_id = ptin_id,
.inttoptr_name_id = itp_id,
```

3. Dispatch in `resolveExpr` builtin_call handler (~L845, after ptrcast branch):
```zig
} else if (node.child_0 == self.ptrtoint_name_id) {
    var ec = ast_mod.astStoreGetExtraChildren(self.store, node.payload);
    if (ec.len >= 1) { _ = semanticAnalyzerResolveExpr(self, ec[0]); }
    result = type_mod.TYPE_USIZE;
} else if (node.child_0 == self.inttoptr_name_id) {
    var ec = ast_mod.astStoreGetExtraChildren(self.store, node.payload);
    if (ec.len >= 1) { _ = semanticAnalyzerResolveExpr(self, ec[0]); }
    var target_type = semanticAnalyzerResolveTypeFromNode(self, ec[0]);
    result = if (target_type != type_mod.TYPE_UNDEFINED) target_type else type_mod.TYPE_VOID;
```
**Type resolution for intToPtr:** Must parse `@intToPtr(*T, val)` — target type from first AST arg. Follows `@ptrCast` pattern.

---

**Plan T6b — Lowerer (`lower.zig`, ~20 lines):**

1. Add fields to `LirLowerer` struct (~L230):
```zig
ptrtoint_name_id: u32,
inttoptr_name_id: u32,
```

2. Intern in `lowererInit` (~L265):
```zig
var pti_s: []const u8 = "@ptrToInt";
var ptin_id = si_mod.stringInternerIntern(ctx.registry.interner, pti_s);
var itp_s: []const u8 = "@intToPtr";
var itp_id = si_mod.stringInternerIntern(ctx.registry.interner, itp_s);
// ... in return struct:
.ptrtoint_name_id = ptin_id,
.inttoptr_name_id = itp_id,
```

3. Dispatch in `lowerExprImpl` builtin_call handler (~L1584, after ptrcast branch):
```zig
} else if (node.child_0 == self.ptrtoint_name_id) {
    var ec = ast_mod.astStoreGetExtraChildren(self.ctx.store, node.payload);
    var arg_val = if (ec.len >= 1) lowerExpr(self, ec[0]) else nextTemp(self, type_mod.TYPE_UNDEFINED);
    var result = nextTemp(self, type_mod.TYPE_USIZE);
    emitInst(self, LirInst{ .ptr_to_int = .{ .value = arg_val, .result = result } });
    return result;
} else if (node.child_0 == self.inttoptr_name_id) {
    var ec = ast_mod.astStoreGetExtraChildren(self.ctx.store, node.payload);
    var arg_val = if (ec.len >= 2) lowerExpr(self, ec[1]) else nextTemp(self, type_mod.TYPE_UNDEFINED);
    var target_type = type_mod.TYPE_USIZE;
    if (ec.len >= 1) {
        // Resolve target type from AST (same pattern as @ptrCast)
        var type_node_idx = ec[0];
        var rtt = resolved_mod.resolvedTypeTableGet(self.ctx.resolved_types, type_node_idx);
        if (rtt) |t| { target_type = t; }
    }
    var result = nextTemp(self, target_type);
    emitInst(self, LirInst{ .int_to_ptr = .{ .value = arg_val, .target = target_type, .result = result } });
    return result;
```
**Note for @intToPtr:** Second arg is the integer value to cast. `@ptrCast(*T, val)` takes first-arg-type, second-arg-value; but `@intToPtr(*T, val)` might use the same convention. Verify lisp usage in `util.zig:52-53` — `@ptrToInt(ptr)` is single-arg (ptr→usize). `@intToPtr` not used in lisp but define for completeness.

---

**Plan T6c — c89 emitInst (`c89_emit.zig`, ~30 lines):**

Design reference: `.int_cast` at line 2720 — uses `getCTypeName` + `(ctype)src`.

```zig
.ptr_to_int => |c| {
    var dst = resolveTempName(emitter, c.result);
    var src = resolveTempName(emitter, c.value);
    bufferedWriterWriteIndent(&emitter.writer, emitter.indent);
    bufferedWriterWrite(&emitter.writer, dst);
    var s1: []const u8 = " = (unsigned int)";
    bufferedWriterWrite(&emitter.writer, s1);
    bufferedWriterWrite(&emitter.writer, src);
    var s2: []const u8 = ";\n";
    bufferedWriterWrite(&emitter.writer, s2);
},
```
**C output:** `zT_N = (unsigned int)zT_M;`

```zig
.int_to_ptr => |c| {
    var dst = resolveTempName(emitter, c.result);
    var src = resolveTempName(emitter, c.value);
    var ctype = getCTypeName(emitter.registry, emitter.mangler, c.target);
    bufferedWriterWriteIndent(&emitter.writer, emitter.indent);
    bufferedWriterWrite(&emitter.writer, dst);
    var s1: []const u8 = " = (";
    bufferedWriterWrite(&emitter.writer, s1);
    bufferedWriterWrite(&emitter.writer, ctype);
    var s2: []const u8 = ")(unsigned int)";
    bufferedWriterWrite(&emitter.writer, s2);
    bufferedWriterWrite(&emitter.writer, src);
    var s3: []const u8 = ";\n";
    bufferedWriterWrite(&emitter.writer, s3);
},
```
**C output:** `zT_N = (zT_TypeName)(unsigned int)zT_M;`

---

**Lisp usage context:** `@ptrToInt` used 2× in `util.zig:52-53` (single-arg `@ptrToInt(ptr)` → usize). `@intToPtr` unused but implement for completeness.

**Verification:**
```bash
# Minimal ptrToInt test
echo 'extern fn get_ptr() *u8; fn main() void { _ = @ptrToInt(get_ptr()); }' > /tmp/t6a.zig
./out_release/zig1 --dump-c89 /tmp/t6a.zig > /tmp/t6a.c
grep "unsigned int" /tmp/t6a.c
# Expect: zT_N = (unsigned int)zT_M;
```

**Status:** ✅ (Fixed incidentally — single-file compilation no longer produces duplicates. Verified with empty + var_decl tests: int main(void) appears 1×, Module: output appears 1×.)

---

**Plan T7d — Nested catch save/restore (parser.zig parserParseCatchRHS line 381):**

`parserParseCatchRHS` clears `self.catch_capture = 0` unconditionally at entry. This overwrites the outer catch's capture in nested `catch` expressions:
```
try fn() catch |outer| { try fn2() catch |inner| { ... } }
```
After inner catch finishes, `self.catch_capture` holds inner capture — outer `parserAddBinary` reads wrong value.

**Fix:** Save/restore `catch_capture` around `parserParseCatchRHS` body:
```zig
fn parserParseCatchRHS(self: *Parser, next_min: Prec) ParserError!u32 {
    var saved_capture = self.catch_capture;   // save outer
    self.catch_capture = @intCast(u32, 0);
    var ptok = parserPeek(self);
    if (ptok.kind == TokenKind.pipe) {
        _ = parserAdvance(self);
        var name_raw2 = parserPeek(self);
        _ = try parserExpect(self, TokenKind.identifier);
        _ = try parserExpect(self, TokenKind.pipe);
        var name_id = name_raw2.value.string_id;
        self.catch_capture = ast_mod.astStoreAddNode(self.store, AstKind.payload_capture, 0,
            name_raw2.span_start, name_raw2.span_start + @intCast(u32, name_raw2.span_len),
            0, 0, 0, name_id);
    }
    // ... existing body parsing ...
    var result = if (parserPeek(self).kind == TokenKind.lbrace)
        try parserParseBlock(self)
    else
        try parserParseExprPrec(self, next_min);
    self.catch_capture = saved_capture;       // restore outer
    return result;
```
2 lines added: save at top, restore before return. Prevents nested catch corruption.

**Status:** ❌ (New)

### T7.5: Fix Single-File `--dump-c89` Output Duplication

**Files:** `sf/src/c89_emit.zig`

**Symptom:** Single-file programs with `pub fn main()` (and no `@import`) produce duplicated C output — the module header, includes, forward declarations, function signature, hoisted temps, and function body are emitted twice. Multi-module projects (mud_server, mandelbrot, GOL) produce correct output. The duplicated output causes C89 compilation failures for standalone test programs.

**Evidence from output analysis:** C output shows two complete copies:
```
[copy 1] zig_compat.h + zig_runtime.h + Module: output + includes + forward decls + int main(void) { temps } + body + EOF
[copy 2] Module: output + includes + forward decls + int main(void) { indented temps + body + EOF
```
Copy 1 has hoisted temps at indent 0 (wrong — `emitFunctionSignature` increments indent to 1 before `emitHoistedDecls`). Copy 2 has correct indentation. `zig_runtime.h` appears 2× but `emitIncludes` (sole writer of `zig_runtime.h`) is called once at main.zig:806. `emitModule` is called once at main.zig:809. `emitModuleHeader` is called once from `emitModule:1266`.

**Hypotheses (ranked by likelihood):**
1. **`emitter.dl_hoisted = 0` at line 1274** — resets dedup flag after `emitHoistedDecls`, causing `emitFunctionBody:2893` to re-emit all `decl_local` LIR instructions as a second variable-declaration pass. Combined with some other write path that also emits module-level content.
2. **`BufferedWriter` buffer aliasing** — `cwriter` and `emitter.writer` are separate structs but both flush to stdout. If buffer pointers overlap in C89 codegen, one flush may re-emit stale buffer content.
3. **`emitSpecialTypes` writes module-level content** — `tstTopologicalSort` + type emission loop at lines 702-758 may emit type definitions that include `zig_compat.h` or module header text when certain type patterns exist.

**Diagnostic plan:**
```zig
// In emitModule (line 1264), add compact markers at each phase:
pal_markerWriteInt("MDL:e", fns.len);              // entry
// after emitSpecialTypes:
pal_markerWrite("SPC:D\n");                        // special types done
// after emitModuleHeader:
pal_markerWrite("HDR:D\n");                        // header done
// on each function in loop:
pal_markerWriteInt("FNP:n", func.name_id);         // function emitted
// before emitModuleFooter:
pal_markerWrite("FTR:D\n");                        // footer done
```

**Trace:** Count marker occurrences. If `HDR` fires 2× → `emitModuleHeader` called twice (chase upstream). If `FNP` fires 2× → duplicate LIR functions (chase lowerer). If `MDL` fires 2× → `emitModule` called twice (chase main.zig).

**Fix candidates (apply after root cause confirmed):**
- **Fix A:** Remove `emitter.dl_hoisted = 0` at line 1274 → restores correct single-emission behavior for hoisted declarations (set `emitter.dl_hoisted = 1` after `emitHoistedDecls`).
- **Fix B:** If `emitModuleHeader` called twice → audit callers and deduplicate.
- **Fix C:** If `fns` has duplicate entries → fix lowerer to not duplicate functions in `lir_fns` for single-module programs.

**Test plan:**
```bash
# Diagnostic build
rm -rf out_release && mkdir out_release
./sf/build/zig0 --header-priority-include -o out_release/zig1.c sf/src/main.zig
gcc -m32 -g -O0 -std=c89 -Wno-long-long -Iinclude out_release/*.c -o out_release/zig1_dbg

# Trace markers
echo 'pub fn main() void {}' > /tmp/t75_empty.zig
./out_release/zig1_dbg --markers --dump-c89 /tmp/t75_empty.zig > /tmp/t75_empty.c 2>/tmp/t75_markers.txt
grep -a "^MDL:\|^SPC\|^HDR\|^FNP:\|^FTR\|^FLUSH:" /tmp/t75_markers.txt

# Verify fix
echo 'pub fn main() void {}' > /tmp/t75_test.zig
./out_release/zig1 --dump-c89 /tmp/t75_test.zig > /tmp/t75_test.c
grep -c "int main(void)" /tmp/t75_test.c    # must be 1
grep -c "Module: output" /tmp/t75_test.c    # must be 1

# Regression
./out_release/zig1 --dump-c89 examples/mud_server/main.zig > /tmp/mud_t75.c
gcc -m32 -std=c89 -Wno-pointer-sign -Iout_release -Isf/src/include /tmp/mud_t75.c sf/src/include/zig_runtime.c sf/src/include/zig_pal.c sf/src/include/net_runtime.c -o /tmp/mud_t75 2>&1 | grep -c "error:"  # must be 0
```

**Status:** ❌ (New)

---

### T10: Remaining Lisp Parse Gaps (G11, G12, G13)

**Files:** `sf/src/parser.zig`, `sf/src/token.zig`, `sf/src/ast.zig`

**Root cause (2026-06-14):** After T1-T8, 160 parse errors remain across all 10 lisp files. All are parser-level `error[2000]`. Three distinct parse gaps:

| Gap | Source pattern | Example | Files affected |
|:---|:---|:---|:---|
| G11 | `!T` error union fn return type | `fn foo() util.LispError!*Value {` | 8/10 files |
| G12 | `error {}` error set declaration | `pub const LispError = error { OutOfMemory, ... }` | util.zig:1 |
| G13 | `error.Foo` error set member literal | `return error.NotAnInt;` | 6+ files (73 uses) |

**Execution order:** G12 first (LispError must exist), then G11 (all functions need it), then G13 (return statements need it).

---

**Plan T10a — G12: Error set declaration (`parser.zig`, `parserParseErrorLiteral` line 601)**

**Prerequisites (all verified ✅):**
- `TokenKind.kw_error` exists at token.zig:82
- `AstKind.error_set_decl` exists at ast.zig:11
- `parserParseErrorSetDecl` (parser.zig:931) parses `error { A, B }` → `error_set_decl` AST node with member name_ids in `payload`
- `parserParseErrorLiteral` (parser.zig:601) currently expects `error.Foo` form → creates `error_literal` node

**Root cause:** In expression context (`const X = error { ... }`), `parserParsePrimary` (line 272) dispatches `kw_error` → `parserParseErrorLiteral`. This function always expects `.identifier` next (line 603: `try parserExpect(self, TokenKind.dot)`). When `error` is followed by `{` (error set declaration in expression position), the dot expectation fails → parse error.

**Fix (parser.zig:601):** In `parserParseErrorLiteral`, BEFORE `parserExpect(TokenKind.dot)`, add:
```zig
if (parserPeek(self).kind == TokenKind.lbrace) {
    return parserParseErrorSetDecl(self);
}
```
This delegates `error { ... }` to the existing `parserParseErrorSetDecl` handler. After this change, `parserParseErrorLiteral` handles both `error.Foo` (existing) and `error { ... }` (via delegation).

**Resolution:** `const LispError = error { ... }` — the `error_set_decl` AST node flows through `resolveExpr` (sema.zig:920) which returns `TYPE_TYPE` for type-expression nodes. `resolveAllFnTypes` (main.zig) resolves the named type via `typeRegistryRegisterNamedType` → type registry gets `error_set_type` entry. Downstream sema/lowerer already handle `error_set_decl` and `error_set_type`.

---

**Plan T10b — G11: Infix `!` error union return type (`parser.zig`, `parserParseType` line 817)**

**Prerequisites (all verified ✅):**
- `TokenKind.bang` (`!`) exists at token.zig:25
- `AstKind.error_union_type` exists at ast.zig:91
- `parserParseErrorUnionType` (parser.zig:890) handles PREFIX `!T` form only — advances `!`, calls `parserParseType`, wraps in `error_union_type` with `child_0 = payload_type`
- `parserParseType` (parser.zig:817-829) dispatches prefix operators (`*`, `[]`, `?`, `!`, `fn`, `error`, `struct`, `enum`, `union`) then falls through to `parserParseTypeName`

**Root cause:** The `!` in `util.LispError!*Value` appears AFTER the error set type (INFIX), not before (PREFIX). `parserParseType` parses `util.LispError` via `parserParseTypeName` and returns. The `!` is left as the next unconsumed token. `parserParseFnDecl` expects `;` or `{` next → sees `!` → parse error.

**Fix (parser.zig:829, after parserParseTypeName):** Add infix `!` handling. After parsing the base type (via `parserParseTypeName`), if the next token is `bang`, consume it, parse the payload type, and wrap both in `error_union_type`:
```zig
pub fn parserParseType(self: *Parser) ParserError!u32 {
    // ... existing prefix checks (lines 819-828) ...
    var base = try parserParseTypeName(self);
    if (parserPeek(self).kind == TokenKind.bang) {
        _ = parserAdvance(self);
        var payload = try parserParseType(self);
        return ast_mod.astStoreAddNode(self.store, AstKind.error_union_type, 0,
            base, payload, 0, 0);
        // child_0 = error_set_type (e.g. util.LispError)
        // child_1 = payload_type    (e.g. *value_mod.Value)
    }
    return base;
}
```

**Node structure change:** `error_union_type` currently uses only `child_0 = payload_type`. After this change:
- `child_0` = error set type expression (the left side of `!`)
- `child_1` = payload type expression (the right side of `!`)
- `resolveTypeExprDepth` (main.zig:575) must be updated to resolve the error union via `typeRegistryGetOrCreateErrorUnion(child_0_resolved_type, child_1_resolved_type)` instead of just returning `child_0` stripped

This handles `!` in ALL type positions — return types, parameters, var annotations, not just fn return position.

---

**Plan T10c — G13: `error.Foo` error set member literal (`parser.zig`, `semantic_analyzer.zig`, `lower.zig`)**

**Prerequisites (all verified ✅):**
- `AstKind.error_literal` exists at ast.zig:21
- `parserParseErrorLiteral` (parser.zig:601) parses `error.Foo` → `error_literal` node with `payload = name_id`
- Sema handles `error_literal` at sema.zig:817
- Lowerer handles `error_literal` at lower.zig:597

**Root cause analysis:** `error.Foo` IS already parsed end-to-end. The `parserParseErrorLiteral` function reads `error`, expects `.`, reads identifier, creates `error_literal` node. Sema and lowerer both have handlers. However, whether `error.NotAnInt` correctly resolves to the error set TYPE depends on whether `LispError` (the `error {}` declaration from G12) is registered in the type registry BEFORE any `error.NotAnInt` usage is resolved.

**Execution order matters:** G12 (error set declaration) MUST complete first so the error set type exists in the registry. Then `error.NotAnInt` expressions can resolve the `.NotAnInt` variant against that error set's field list. The sema `error_literal` handler may need to look up which error set type the `error` keyword refers to — this likely requires passing context (the function's return type tells you which error set is expected).

**Potential secondary fix (after G12+G11):** If `error.NotAnInt` doesn't resolve automatically, the sema may need the same `current_switch_cond_tu` pattern used for tagged union switch prong enum_literals: in a function whose return type is `LispError!T`, set `current_error_set = LispError` so `error.NotAnInt` resolves to the variant index within `LispError`.

---

**Test plan:**
```bash
# G12: error set declaration (expression context)
echo 'error { OutOfMemory, NotAnInt };' > /tmp/t10a.zig
./out_release/zig1 --dump-c89 /tmp/t10a.zig 2>&1 | grep -c "error\[2000\]"  # expect 0

# G12: error set as const init
echo 'const E = error { A, B };' > /tmp/t10a2.zig
./out_release/zig1 --dump-c89 /tmp/t10a2.zig 2>&1 | grep -c "error\[2000\]"  # expect 0

# G11: infix !T return type
echo 'const E = error { A, B }; fn f() E!void {}' > /tmp/t10b.zig
./out_release/zig1 --dump-c89 /tmp/t10b.zig 2>&1 | grep -c "error\[2000\]"  # expect 0 (after G12+G11 fix)

# G13: error.Foo literal
echo 'const E = error { A, B }; fn f() void { _ = error.A; }' > /tmp/t10c.zig
./out_release/zig1 --dump-c89 /tmp/t10c.zig 2>&1 | grep -c "error\[2000\]"  # expect 0 (after G12 only)

# Full lisp regression
./out_release/zig1 --dump-c89 examples/lisp_interpreter_curr/main.zig 2>&1 | grep -c "error\[2000\]"
# Target: < 160 (some parse errors eliminated, maybe sema/lowerer errors appear)

# mud/man/gol regression
./out_release/zig1 --dump-c89 examples/mud_server/main.zig > /tmp/mud.c
gcc -m32 -std=c89 -Wno-pointer-sign -Iout_release -Isf/src/include /tmp/mud.c sf/src/include/zig_runtime.c sf/src/include/zig_pal.c sf/src/include/net_runtime.c -o /tmp/mud_app 2>&1 | grep -c "error:"  # must be 0
```

**Status:** ✅ (Completed 2026-06-14 — 0 parse errors across all 10 lisp files, 3 regressions clean)

---

### T11: Error union fn return type — resolveAllFnTypes (G14, contributes to C2+C1)

**Files:** `sf/src/main.zig` (resolveAllFnTypes, resolveTypeExprDepth)

**Root cause:** `resolveTypeExprDepth` (main.zig:575) handles `error_union_type` by returning only `child_type` (child_0 = payload). This discards the error set from `T!U` → function return type resolves to `U` only, not the error union. Downstream: sema `resolveFnCall` return type, lowerer `func.return_type`, and c89_emit all see `void`/`u8` instead of `error_union_type`.

**Prerequisites verified:**
- `AstKind.error_union_type` stores `child_0` = error set type expr, `child_1` = payload type expr (from T10b fix)
- `typeRegistryGetOrCreateErrorUnion` exists at type_registry.zig:393 — creates `error_union_type` TypeId with `EuPayload{payload, error_set}`

**Fix (main.zig:575):**
```zig
if (node.kind == AstKind.error_union_type) {
    var err_set_type = resolveTypeExpr(ctx, node.child_0);
    var payload_type = resolveTypeExpr(ctx, node.child_1);
    return type_mod.typeRegistryGetOrCreateErrorUnion(ctx.typereg, payload_type, err_set_type);
}
```
Currently it does `return child_type` where `child_type = resolveTypeExpr(child_0)` — that's the PAYLOAD when old node structure had `child_0 = payload` only. After T10b, `child_0 = error_set, child_1 = payload`. Must resolve both and call `getOrCreateErrorUnion`.

**Verification:**
```bash
echo 'const E = error { A, B }; fn f() E!void {}' > /tmp/t11.zig
./out_release/zig1 --dump-c89 /tmp/t11.zig 2>/dev/null | grep "void f"  # should see return type as error_union struct, not void
```

**Status:** ✅ (Completed 2026-06-14. Two fixes: resolveTypeExprDepth resolves child_0+child_1 → getOrCreateErrorUnion; symbol_registrator.zig added error_set_decl to named-type registration. RTR:n5t22 confirms TypeId resolves. Lisp: 0→2505 GCC errors — cascade exposes T12-T18. Mud/man/gol: 0 regressions.)

---

### T12: Lowerer error union type propagation (G15, contributes to C1+C7)

**Files:** `sf/src/lower.zig` (try_expr, catch_expr handlers)

**Root cause:** `try_expr` (lower.zig:1602) and `catch_expr` (lower.zig:1667) emit `check_error`/`unwrap_error_payload` on the inner value but the result temps are created with `TYPE_UNDEFINED` or wrong types. The error union type from sema's RTT is not propagated to the hoisted temps. c89_emit handlers (from T4) see wrong base type → emit `.is_error`/`.data` on non-error-union struct → 54+54 GCC errors.

**Prerequisites verified:**
- T4: c89_emit handlers for `check_error`, `unwrap_error_payload`, `unwrap_error_code` exist ✅
- T5: `wrap_error_ok`, `wrap_error_err` handlers exist ✅
- T11: `resolveAllFnTypes` returns correct error union TypeId (pending)
- `LirInst` types: `.check_error`, `.unwrap_error_payload`, `.unwrap_error_code` in lir.zig

**Fix (lower.zig:1602, try_expr):**
```zig
// After inner_temp = lowerExpr(child_0), determine error union base type:
var eu_type = getTempType(self, inner_temp);
var err_base: u32 = type_mod.TYPE_U8;  // fallback for non-error-union
if (eu_type != type_mod.TYPE_UNDEFINED) {
    var ty = self.ctx.registry.types_items[@intCast(usize, eu_type)];
    if (ty.kind == type_mod.TypeKind.error_union_type) {
        err_base = eu_type;
    }
}
var is_err_temp = nextTemp(self, err_base);
emitInst(self, LirInst{ .check_error = .{ .value = lhs_temp, .result = is_err_temp } });
// ... branch, err BB ...
self.current_bb = ok_bb;
var ok_val = nextTemp(self, err_base);  // SAME type for unwrap result
emitInst(self, LirInst{ .unwrap_error_payload = .{ .value = lhs_temp, .result = ok_val } });
```
Same pattern for catch_expr at line 1667 — both `is_err_temp` AND `ok_val` must get `err_base` (error_union_type from inner_temp), not TYPE_U8/TYPE_UNDEFINED. The c89_emit handlers read the base temp's hoisted type to determine struct layout — if the temp has TYPE_U8 (primitive), `is_error`/`data` field access fails with "request for member in something not a structure or union".

**Verification:**
```bash
echo 'const E = error { A, B }; fn f() E!void { return error.A; }' > /tmp/t12.zig
./out_release/zig1 --dump-c89 /tmp/t12.zig > /tmp/t12.c
gcc -m32 -std=c89 -Wno-pointer-sign ... /tmp/t12.c ... -o /tmp/t12 2>&1 | grep -c "is_error\|data"
# Target: 0 (no struct field complaints on non-struct)
```

**Status:** ❌

---

### T13: decl_local emission pipeline for named locals (G16, contributes to C3)

**Files:** `sf/src/lower.zig` (addLocalDecl), `sf/src/c89_emit.zig` (emitFunctionBody, emitHoistedDecls)

**Root cause:** 94 undeclared C identifiers (names like `val`, `data`, `s`, `car`, `cdr`). Two possible upstream sources:

1. **Sema never registers the local.** `resolveStmtDepth` var_decl handler (sema.zig:1080-1085) stores `local_decl_names[count] = name_id` and `local_decl_types[count] = type_id`. If the var_decl's resolved type is TYPE_VOID, the local_decl is registered but the type is void → lowerer `addLocalDecl` still fires → `decl_local` LIR emitted → c89_emit sees TYPE_VOID → emits `void car;` → GCC error.

2. **`addLocalDecl` skipped or emits wrong type.** The lowerer's `addLocalDecl` (lower.zig) emits `.decl_local` LIR with `name_id` and `type_id`. If the type_id is TYPE_VOID or TYPE_UNDEFINED, c89_emit produces `void zT_N;` or skips the declaration.

**What's already correct:**
- `dedup_count = 0` reset per-function at c89_emit.zig:3005 ✅
- `dedup_names[128]` overwritten per-function (dedup_count resets logical length) ✅
- `dl_hoisted = 0` reset per-function at line 1274 ✅

**Diagnostic approach (before fix):**
1. Add marker at sema `resolveStmtDepth` var_decl handler (line 1080) printing name_id + type_id for every registered local
2. Add marker at lowerer `addLocalDecl` printing name_id + type_id
3. Add marker at c89_emit `emitFunctionBody` decl_local handler printing name_id + type_id
4. Cross-reference: for each undeclared C name, check (1) was it registered in sema? (2) did addLocalDecl fire? (3) did decl_local handler fire?
5. If (1) fires but (2) doesn't → gap in sema→lowerer pipeline (local_decl_names not read by lowerer for error union functions)
6. If (1)+(2) fire but (3) doesn't → gap in lowerer→c89_emit (decl_local not emitted or dedup skipped)
7. If (1) fires with TYPE_VOID → gap in sema type resolution (error union var_decl type not resolved)

```bash
echo 'const E = error {A, B}; fn f() E!void { var x: u32 = 1; _ = x; }' > /tmp/t13.zig
./out_release/zig1 --markers --dump-c89 /tmp/t13.zig > /tmp/t13.c 2>/tmp/t13_m.txt
grep -a "^VDC:\|^ADL:\|^DCL:" /tmp/t13_m.txt  # Trace local through all 3 layers
```

**Status:** ❌

---

### T14: i64/u64 C89 typedefs — short-term fix (G17, contributes to C5)

**Files:** `sf/src/c89_emit.zig` (getCTypeName lines 447, 451)

**Root cause:** `getCTypeName` returned raw strings `"z64"`/`"zu64"` for `i64_type`/`u64_type`, bypassing the name-mangling pipeline. This was ALWAYS a shortcut — primitives should use the same backend-independent mangled-name pattern as user-defined types.

**Fix applied (2026-06-14):** Replaced `"z64"`→`"long long"` and `"zu64"`→`"unsigned long long"`. Works (C5 eliminated, −99 errors), but **architecturally wrong** — ties type names to C89 backend.

**Status:** ⚠️ (Partial — escalated to T14.5 for proper architectural fix)

---

### T14.5: i64/u64 — back-end-independent type names (G17, replaces T14)

**Architectural problem:** T14 hardcoded C89 strings in `getCTypeName`. If back-end changes (e.g., 16-bit MSVC, WASM, Lisp), must find+replace all `"long long"` occurrences in code. The codebase already has the correct pattern: type names go through `nameManglerMangle` → `stringInternerGet` (backend-independent), and C89 content goes through `emitTypeDefinition` → `emitSpecialTypes` (single backend-specific location). All other named types (struct, enum, tagged_union, array) follow this pattern.

**Part A — getCTypeName (c89_emit.zig:447,451):** Replace hardcoded strings with mangled-name pattern:
```zig
if (ty.kind == TypeKind.i64_type) {
    var mid = nameManglerMangle(mangler, ty.name_id, @intCast(u8, 2), ty.module_id);
    return interner_mod.stringInternerGet(mangler.interner, mid);
}
if (ty.kind == TypeKind.u64_type) {
    var mid = nameManglerMangle(mangler, ty.name_id, @intCast(u8, 2), ty.module_id);
    return interner_mod.stringInternerGet(mangler.interner, mid);
}
```

**Part B — emitTypeDefinition (c89_emit.zig, in emitTypeDefinition switch):** Add cases for `i64_type`/`u64_type` to emit typedefs using the same mangled name as getCTypeName:
```zig
if (ty.kind == TypeKind.i64_type) {
    var tn = interner_mod.stringInternerGet(mangler.interner, mid);
    bufferedWriterWriteIndent(writer, indent);
    var pre: []const u8 = "typedef long long ";
    bufferedWriterWrite(writer, pre);
    bufferedWriterWrite(writer, tn);
    var semi: []const u8 = ";\n";
    bufferedWriterWrite(writer, semi);
    return;
}
if (ty.kind == TypeKind.u64_type) {
    var tn = interner_mod.stringInternerGet(mangler.interner, mid);
    bufferedWriterWriteIndent(writer, indent);
    var pre: []const u8 = "typedef unsigned long long ";
    bufferedWriterWrite(writer, pre);
    bufferedWriterWrite(writer, tn);
    var semi: []const u8 = ";\n";
    bufferedWriterWrite(writer, semi);
    return;
}
```

**Test plan:**
```bash
echo 'fn main() void { var x: i64 = 0; _ = x; }' > /tmp/t14r.zig
./out_release/zig1 --dump-c89 /tmp/t14r.zig > /tmp/t14r.c
grep "typedef.*long long" /tmp/t14r.c  # should show typedef for i64 mangled name
grep -c "long long" /tmp/t14r.c        # appears in typedef + variable decl
gcc -m32 -std=c89 -Wno-long-long -Wno-pointer-sign -Iinclude ... -o /tmp/t14r 2>&1

# Lisp regression
./out_release/zig1 --dump-c89 examples/lisp_interpreter_curr/main.zig > /tmp/lisp_t14r.c
gcc -m32 -std=c89 -Wno-long-long -Wno-pointer-sign -Iout_release -Isf/src/include /tmp/lisp_t14r.c sf/src/include/zig_runtime.c sf/src/include/zig_pal.c -o /tmp/lisp_t14r 2>&1 | grep -c "error:"  # must be ≤ 428

# mud/man/gol regression
```

**Status:** ❌ (New)

---

### T15: Coercion chain for error union patterns (G18, contributes to C4)

**Files:** `sf/src/semantic_analyzer.zig` (return_stmt, resolveFnCall, resolveAssign)

**Root cause:** After T11+T12+T13, error union types will reach the lowerer but coercion between error union value and unwrapped payload may not be recorded. Patterns like `return try expr` (error union → unwrapped → return), `x = try expr` (unwrapped → local), `return error.Foo` (error literal → error union) need `tryRecordCoercion` or equivalent type unification.

**Existing infrastructure:** `tryRecordCoercion` (sema.zig:434) records `(node_idx, source_type, target_type)` → coercionTable → lowerer `applyCoercion`. Already used for:
- `resolveAssign` (line 721) — `var x: T = expr`
- `resolveFnCall` (lines 512, 564) — argument passing
- `resolveStructInit` (lines 675, 701) — field initialization
- `return_stmt` (lines 936, 1266) — return value coercion

**Missing patterns (need verification):**
1. `return try expr` — return_stmt resolves child (try_expr → resolves inner → unwrapped type). May mismatch fn return (error_union).
2. `return error.Foo` — return_stmt resolves child (error_literal → TYPE_U32 or error_set). Must coerce to fn return type.
3. `x = try expr` — resolveAssign resolves rhs (try_expr → unwrapped). Must coerce to x's declared type.

**Fix approach:** Add marker at return_stmt handler to log child_resolved_type vs current_fn_return, and at resolveAssign to log rhs_type vs lhs_type. If mismatches exist where they shouldn't, add tryRecordCoercion calls. This is a diagnostic + targeted-fix task — range may be 0-3 call sites.

**Verification:**
```bash
echo 'const E = error { A, B }; fn f() E!u32 { return error.A; }' > /tmp/t15.zig
./out_release/zig1 --markers --dump-c89 /tmp/t15.zig > /tmp/t15.c 2>/tmp/t15_m.txt
grep -a "^RET:\|^COE:\|^COR:" /tmp/t15_m.txt  # Verify coercion recorded for error.Foo → !u32
```

**Status:** ✅ (Verified 2026-06-14. T2F/COE/COR/RET markers all fire correctly. Coercion chain already working. The 428 lisp errors are from T18 (resolveTypeExprDepth missing field_access) + T19 (c89_emit name mismatch). 0 regressions.)

---

### T17: Multi-module output duplication (G19)

**Status:** ✅ (Obsolete 2026-06-14. Zero redefinition errors in current 428 GCC output. Original appearance was cascade from T18 void signatures. Fixed incidentally by T12+T14.)

---

### T18: resolveTypeExprDepth field_access handler (G20)

**Files:** `sf/src/main.zig` (resolveTypeExprDepth line 535)

**Root cause (proven by diagnostic markers 2026-06-14):** FNR:y=48, FNR:n=0 — all 48 functions have `return_type_node != 0`. UND:n=1, UND:k25=0 — only 1 node hits the fallthrough (not field_access). The 43 RTT misses come from explicit `return TYPE_UNDEFINED` guards at lines 537 and 580: `resolveTypeExpr(child_0)` on the error set expression (`util.LispError`) returns UNDEFINED because `resolveTypeExprDepth` has no `field_access` handler for cross-module qualified types.

**Missing handler pattern:**
```zig
if (node.kind == AstKind.field_access) {
    // child_0 = base (module reference → ident_expr → module_type)
    // child_1 = field_name_id
    var base_type = resolveTypeExprDepth(ctx, node.child_0, depth + 1);
    if (base_type == TYPE_UNDEFINED) return TYPE_UNDEFINED;
    var base_ty = ctx.typereg.types_items[base_type];
    if (base_ty.kind == TypeKind.module_type) {
        var mod_id = base_ty.module_id;
        var name_id = node.payload;
        var sym = symbolRegistryQualifiedLookup(ctx.symbol_reg, mod_id, name_id);
        if (sym) |s| {
            if (s.type_id != 0) return s.type_id;
        }
    }
    return TYPE_UNDEFINED;
}
```

Same pattern as `semanticAnalyzerResolveFieldAccess` (sema.zig:267-307) for module-qualified symbol lookup. Fixes ALL cross-module qualified types (`util.LispError`, `value_mod.Value`) — not just error sets.

**Verification:**
```bash
./out_release/zig1 --markers --dump-c89 examples/lisp_interpreter_curr/main.zig > /tmp/lisp.c 2>/tmp/m.txt
grep -ac "HR" /tmp/m.txt   # expect HR:48 (all functions get RTT)
grep -ac "MR" /tmp/m.txt   # expect MR:0
./out_release/zig1 --dump-c89 examples/mud_server/main.zig > /tmp/mud.c
gcc -m32 -std=c89 ... /tmp/mud.c ... 2>&1 | grep -c "error:"  # expect 0
```

**Status:** ❌ (Redefined 2026-06-14 after diagnostic markers disproved lowerer theory)

---

### T19: c89_emit error union name mismatch (G21)

**Files:** `sf/src/c89_emit.zig` (emitErrorUnionType line 1093, getCTypeName line 517), `sf/src/type_registry.zig` (Type.c_name_id)

**Root cause:** `getCTypeName` and `emitErrorUnionType` generate different mangled C names for the same error union TypeId. `getCTypeName` uses `ty.name_id` → `nameManglerMangle` producing e.g. `zT_811C9DC5_`. `emitErrorUnionType` synthesizes `EU_<payload_mangled>` as an intermediate name, then mangles THAT → `zT_88EC7F60_EU_zT_05F374B1_u32`. The C output has `typedef zT_88EC7F60_...` but forward declarations use `zT_811C9DC5_` → GCC: unknown type.

**Fix:** `Type.c_name_id` field already exists on the Type struct (type_registry.zig). Two-step fix:
1. **emitErrorUnionType** (c89_emit.zig:1124): after computing `mangled_c_name`, intern it and write `reg.types_items[tid].c_name_id = interner_mod.stringInternerIntern(emitter.interner, mangled_c_name)`.
2. **getCTypeName** (c89_emit.zig:431): after the `if (ty.kind == ...)` chain and before the fallback, add: `if (ty.c_name_id != 0) { return interner_mod.stringInternerGet(mangler.interner, ty.c_name_id); }`.

This eliminates the 5 `unknown type zT_811C9DC5_` errors in lisp (GCC error category from classification). Same pattern as struct/enum/tagged_union types which already store their emitted names.

**Test plan:**
```bash
echo 'const E = error { A, B }; fn f() E!u32 { return error.A; }' > /tmp/t19.zig
./out_release/zig1 --dump-c89 /tmp/t19.zig > /tmp/t19.c 2>/dev/null
gcc -m32 -std=c89 -Wno-pointer-sign -Iout_release -Isf/src/include /tmp/t19.c sf/src/include/zig_runtime.c sf/src/include/zig_pal.c -o /tmp/t19 2>&1 | grep -c "unknown type"
# Expect 0
grep -c "zT_811C9DC5_" /tmp/t19.c  # Expect 0 — no stale name
```

**Status:** ✅ (Completed 2026-06-16. Self-reliant EU handler in getCTypeName computes EU_+payload_cname inline. No dependency on emitSpecialTypes ordering. −39 errors, 5 EU typedefs. Remaining 577 from T20-T25.)

---

### T20: E1 — ptr_type EU name dedup collision (181 errors, G22)

**Where:** `c89_emit.zig:528` (getCTypeName EU handler), `:2315` (emitSpecialTypes dedup)

**Theory:** EU handler computes `EU_` + `getCTypeName(payload)`. For pointer payloads (`*Value`), `getCTypeName` returns `unsigned char*` — identical for ALL pointer types. Second EU with pointer payload gets same getCTypeName string → same dedup hash → `emitted_type_set.Put` skips ↔ typedef never emitted → `zT_B69C4BFB_EU_zT_D147F96A_Valu` unknown type.

**Investigation:** GDB at emitSpecialTypes pass 2 for `LispError!*Value` TypeId. Break on `hash_mod.u32ToU32MapPut(&emitter.emitted_type_set, dedup_key)` — verify dedup_key collision with already-emitted `EU_unsigned_char_ptr`.

**Fix candidate:** `getCTypeName` for ptr_type must return a DISTINCT string per pointee type, not the raw C pointer type. Use `nameManglerMangle(ty.name_id, ...)` for ptr_type too (same pattern as struct_type).

**Status:** ❌

---

### T21: E2 — EnvNode struct typedef missing (30 errors, G23)

**Where:** `c89_emit.zig:754-761` (unnamed whitelist)

**Theory:** EnvNode struct has `name_id==0` (unnamed by construction?). `emitSpecialTypes` pass 2 unnamed guard at line 754 skips unnamed types NOT in whitelist. Whitelist at line 757: `error_union_type, optional_type, array_type, slice_type, fn_type` — struct_type is EXCLUDED. EnvNode never emitted → `zT_267BF390_EnvNode` unknown type.

**Investigation:** GDB at emitSpecialTypes pass 2 for EnvNode TypeId. Print `ty.name_id`. If 0 → check whitelist bypass. If non-zero → issue is elsewhere (dedup collision with another struct).

**Fix candidate:** Add `TypeKind.struct_type` (and possibly `tagged_union_type`, `union_type`) to whitelist. Guard already exists for unnamed named types — safe.

**Status:** ❌

---

### T22: E3 — non-deterministic EU name hash (5 errors, G24)

**Where:** `c89_emit.zig:529-534` (EU handler buf construction)

**Theory:** Same payload Token produces two different EU hashes: `zT_1530EB8C_EU_zT_3A355BD2_Toke` (typedef exists) and `zT_C262C708_EU_zT_3A355BD2_Toke` (unknown type). The buf used to construct `EU_<pay_cname>` may have uninitialized trailing bytes that participate in interner string hash → non-deterministic interned ID → different mangled names.

**Investigation:** Read EU handler at lines 526-535. Check if `buf[0..p]` is fully written (all bytes initialized) before `stringInternerIntern`. Check if `p` accurately represents the written length.

**Fix candidate:** Ensure buf is zero-initialized before write, or use exact-length slice.

**Status:** ❌

---

### T23: E4 — lowerer func.return_type TYPE_VOID (112 errors, G25)

**Where:** `lower.zig:3117` (lowerFn reads RTT for proto.return_type_node)

**Theory:** T18 fixed field_access in resolveTypeExprDepth but some functions still have void return type. Lowerer at line 3117 reads `resolvedTypeTableGet(resolved_types, proto.return_type_node)` → may still return null for edge cases → `func.return_type = TYPE_VOID` → `nextTemp(self, TYPE_VOID)` → void temps → `is_error` on void struct.

**Investigation:** GDB at lowerFn for a void-return function. Break on RTT lookup — print proto.return_type_node and resolved_types entry. Identify WHY lookup fails despite T18 fix.

**Fix candidate:** If RTT lookup returns null and fn_type HAS an error union return type, use `fn_type.return_type_id` directly (available from fn_type struct in type_registry).

**Status:** ❌

---

### T24: E5 — undeclared locals in void functions (22 errors, G26)

**Where:** `c89_emit.zig:emitHoistedDecls` / `lower.zig:addLocalDecl`

**Theory:** Inside void-return functions (T23), `addLocalDecl` fires but the `decl_local` LIR instruction may be skipped during emission. Or the locals are declared with TYPE_VOID and getCTypeName returns "void" → GCC rejects them.

**Expected:** Fixed as cascade from T23. Only investigate independently if E5 persists after T23.

**Status:** ❌

---

### T25: E6 — type mismatches cascade (215 errors)

**Where:** No investigation needed — cascade from T20-T24.

**Theory:** 215 Slice/int/pointer assign mismatches, aggregate-as-integer, subscript failures. All disappear when typedefs exist and function return types are correct.

**Fix:** Verify after T20-T24. If errors remain → classify independently.

**Status:** ❌

---

### T26: Bug #3 Layer Attribution — @sizeOf/@alignOf undeclared temps (UPSTREAM)

**Where:** `comptime_eval.zig:56` (`comptimeEvalResolveTypeArg`), `lower.zig:2125` (comptime_values fold)

**Proven layer:** UPSTREAM (`comptime_eval`). `comptimeEvalResolveTypeArg` resolves only `ident_expr` type args and returns null for `ptr_type`, so `@sizeOf`/`@alignOf` of a pointer type never get a comptime value. `lower.zig:2125` folds only on a `comptime_values` hit and leaves a dangling temp on the miss → undeclared C temps `zT_328`/`zT_329`/`zT_330` from `eval.zig:152` using `arg_count * @sizeOf(*value_mod.Value)` / `@alignOf(*value_mod.Value)`.

**Diagnostic evidence (D1):** `./out_release/zig1 --dump-c89 examples/lisp_interpreter_curr/main.zig` aborts with `error[48]: internal: comptime value unresolved for @sizeOf/@alignOf (node 2145)` exit 3. The ICE guard `iceUnresolvedComptime` in `lower.zig` confirms the lowerer is NOT at fault — the comptime value never arrived from upstream.

**Fix location:** UPSTREAM — extend `comptimeEvalResolveTypeArg` to resolve non-`ident_expr` type arguments (e.g., `ptr_type`, `many_ptr_type`). A lower-level fallback would mask the real gap.

**Status:** ✅ Fixed.

**RESOLVED (2026-07-05, commit 9f4d2095):** `comptimeEvalResolveTypeArg` now delegates to the canonical `resolveTypeExprFull` (which handles `ptr_type`/`many_ptr_type`/`field_access`/etc.), so `@sizeOf`/`@alignOf(*T)` fold correctly; the D1 ICE is eliminated and lisp `--dump-c89` compiles again.

**Cast-target resolver (commit 9ae6d1f0):** `@intCast`/`@ptrCast` cast-target resolution in `lower.zig` (previously ident-only, silently defaulted pointer targets to `u32`) now delegates to `resolveTypeExprFull`; proven via the `CASTDFLT` diagnostic (commit 10476bf5) which fired on lisp's `many_ptr` `*value_mod.Value` cast and no longer fires after the fix. Fixed a real silent-wrong-type bug; did not change the lisp gate count.

**direct_ret fallback (commit f32258a0):** a gated `DRETFB` marker on the `semantic_analyzer.zig` ident-only fn-return fallback shows it **never fires** across lisp/man/gol/mud/132 corpus repros — the resolved-type-table main path covers all cases (confirmed never-exercised smell; safe to delete in future).

---

### T27: Bug #4 Layer Attribution — while optional capture missing check_optional (LOWER)

**Where:** `lower.zig:~3164` (while_stmt emission), compare `lower.zig:2338`/`:3081` (if/orelse optional capture)

**Proven layer:** LOWER. The `while_stmt` handler branches on the raw `cond_temp` and calls `bindOptionalCapture` without first emitting `check_optional`. In contrast, `if`/`orelse` optional-capture paths (`:2338`/`:3081`) correctly emit `check_optional` before the capture. This causes the C output to emit `if (cur)` on a raw optional struct instead of `if (cur.has_value)`, triggering GCC "struct used as scalar" errors on lines ~3743, ~3796.

**Diagnostic evidence (D3):** The `WCAPKIND` diagnostic marker reports `WCAPKIND:21` — `21` is the ordinal of `TypeKind.optional_type`, confirming the condition expression is correctly typed as optional upstream. The bug is thus in LOWER's failure to unwrap that optional for the branch condition.

**Fix location:** LOWER — at `lower.zig:~3164`, emit `check_optional` for the optional-capture condition before `bindOptionalCapture`, matching the pattern used in if/orelse optional capture.

**Status:** ⚠️ Attributed (Lower). Fix is separate future task.

---

### T16: Integration Test

**Target:** Lisp interpreter compiles (0 errors), runs (produces output), mud_server regression (0 errors).

**Build + test sequence:**
```bash
# Build zig1
rm -rf out_release && mkdir out_release
./sf/build/zig0 --header-priority-include -o out_release/zig1.c sf/src/main.zig
gcc -m32 -g -O0 -std=c89 -Wno-long-long -Iinclude out_release/*.c -o out_release/zig1
test -f out_release/zig1 && echo "BUILD OK" || echo "BUILD FAILED"

# Compile lisp
./out_release/zig1 --dump-c89 examples/lisp_interpreter_curr/main.zig > /tmp/lisp.c
wc -l /tmp/lisp.c
gcc -m32 -std=c89 -Wno-pointer-sign -Iout_release -Isf/src/include \
  /tmp/lisp.c sf/src/include/zig_runtime.c sf/src/include/zig_pal.c -o /tmp/lisp
echo "GCC exit: $?"

# Run lisp
echo "(+ 1 2)" | /tmp/lisp 2>&1 | head -5

# Regression: mud_server
./out_release/zig1 --dump-c89 examples/mud_server/main.zig > /tmp/mud.c
gcc -m32 -std=c89 -Wno-pointer-sign -Iout_release -Isf/src/include \
  /tmp/mud.c sf/src/include/zig_runtime.c sf/src/include/zig_pal.c sf/src/include/net_runtime.c -o /tmp/mud
gcc -m32 ... /tmp/mud.c ... -o /tmp/mud 2>&1 | grep -c "error"
  # expect 0

# Regression: mandelbrot
./out_release/zig1 --dump-c89 examples/mandelbrot/mandelbrot.zig > /tmp/man.c
gcc -m32 -std=c89 -Wno-pointer-sign -Iout_release -Isf/src/include \
  /tmp/man.c sf/src/include/zig_runtime.c sf/src/include/zig_pal.c -o /tmp/man
/tmp/man | head -3  # expect ASCII art

# Regression: GOL
./out_release/zig1 --dump-c89 examples/game_of_life/main_lin.zig > /tmp/gol.c
gcc -m32 -std=c89 -Wno-pointer-sign -Iout_release -Isf/src/include \
  /tmp/gol.c sf/src/include/zig_runtime.c sf/src/include/zig_pal.c -o /tmp/gol
gcc ... 2>&1 | grep -c "error"  # expect 0
```

## 4. Build Pipeline (from milestone0.md §3)

```bash
# zig0 from C++ bootstrap
g++ -std=c++98 -Isrc/include src/bootstrap/bootstrap_all.cpp -o sf/build/zig0

# zig0 compiles Z98 → C89
./sf/build/zig0 --header-priority-include -o out_release/zig1.c sf/src/main.zig

# GCC compiles C89 → zig1 binary
gcc -m32 -std=c89 -Wno-long-long -Iinclude out_release/*.c -o out_release/zig1

# zig1 compiles examples
./out_release/zig1 --dump-c89 <source.zig> > out.c

# GCC links example
gcc -m32 -std=c89 -Wno-pointer-sign -Iout_release -Isf/src/include \
  out.c sf/src/include/zig_runtime.c sf/src/include/zig_pal.c -o app
```

## 5. Progress Tracking

| Task | Description | Files | Status |
|------|-------------|-------|--------|
| T1 | Parser decl_buf overflow → shared_store corruption | `parser.zig`, `import_resolver.zig` | ✅ |
| T2 | Dot-star parser gap → `switch(v.*)` and `.*` deref universal failure | `parser.zig` | ✅ |
| T3 | @ptrCast end-to-end (sema dispatch + lowerer LIR + c89_emit codegen) | `sema.zig`, `lower.zig`, `c89_emit.zig` | ✅ |
| T4 | check_error + unwrap_error_payload + unwrap_error_code handlers | `c89_emit.zig` | ✅ |
| T5 | wrap_error_ok + wrap_error_err handlers | `c89_emit.zig` | ✅ |
| T6 | check_optional + unwrap_optional handlers | `c89_emit.zig` | ✅ |
| T7 | @ptrToInt/@intToPtr end-to-end (sema+lowerer+c89) | `sema.zig`, `lower.zig`, `c89_emit.zig` | ✅ |
| T8 | catch \|err\| capture + nested save/restore | `parser.zig`, `sema.zig`, `lower.zig` | ✅ |
| T9 | Fix single-file --dump-c89 output duplication | `c89_emit.zig` | ✅ |
| T10 | Remaining lisp parse gaps: `!T` return type, `error{}` decl, `error.Foo` literal | `parser.zig`, `token.zig`, `ast.zig` | ✅ |
| T11 | Error union fn return type via resolveAllFnTypes + symbol_reg error_set_decl (G14) | `main.zig`, `symbol_registrator.zig` | ✅ |
| T12 | Lowerer error union type propagation for try/catch (G15) | `lower.zig` | ❌ |
| T13 | decl_local emission pipeline — named locals in error union fns (G16) | `lower.zig`, `c89_emit.zig` | ❌ |
| T14 | i64/u64 C89 typedefs — short-term `"long long"` fix (G17) | `c89_emit.zig` | ⚠️ |
| T14.5 | i64/u64 back-end-independent type names via mangled-name pipeline (G17) | `c89_emit.zig` | ❌ |
| T15 | Coercion chain for error union patterns (G18) | `sema.zig` | ✅ |
| T16 | Integration test (lisp compiles + runs + mud/man/gol regression) | All | ❌ |
| T17 | Multi-module output duplication — functions emitted 2-3× (G19, T9 regression) | `c89_emit.zig` | ✅ |
| T18 | resolveTypeExprDepth field_access handler — cross-module qualified types (G20) | `main.zig` | ❌ |
| T19 | c89_emit error union name mismatch — self-reliant getCTypeName EU handler (G21) | `c89_emit.zig` | ✅ |
| T20 | E1: ptr_type EU name collision — all ptr types→same 'unsigned char*' → dedup skips (G22) | `c89_emit.zig:528,2315` | ❌ |
| T21 | E2: EnvNode struct typedef missing — unnamed guard skips struct_type (G23) | `c89_emit.zig:754-761` | ❌ |
| T22 | E3: Non-deterministic EU name hash — same payload different prefix (G24) | `c89_emit.zig:529-534` | ❌ |
| T23 | E4: is_error/data on non-struct — T18 void return (lowerer func.return_type) (G25) | `lower.zig:3117` | ❌ |
| T24 | E5: Undeclared locals (val/data/s/name) — cascade from T23 (G26) | `c89_emit.zig:emitHoistedDecls` | ❌ |
| T25 | E6: Type mismatches (Slice/int/pointer assign) — cascade from T20-T24 | — | ❌ |
| T26 | Bug #3 attribution — @sizeOf/@alignOf temps: root in comptime_eval (upstream), D1 ICE evidence | `comptime_eval.zig`, `lower.zig` | ✅ Fixed |
| T27 | Bug #4 attribution — while optional capture: root in lower while_stmt (lower), D3 WCAPKIND=21 evidence | `lower.zig` | ⚠️ Attrib |
| T28 | Tagged-union payload store on struct-init + anon-`.{}` init inference via expected_type_stack (return/var-decl/call-arg/assign/field/module-const + if-arm/switch-prong by propagation) | `lower.zig`, `c89_emit.zig`, `semantic_analyzer.zig`, `main.zig` | ✅ Done |
| T28a | Anon-`.{}` in `orelse` RHS — DEFERRED gap (needs new resolveExpr(child_1) in resolveOrelseExpr; 0 corpus uses). Repro `repro/anon_init_orelse_rhs` | `semantic_analyzer.zig:742-752` | ❌ Deferred |
| T28b | Array-of-tagged-union read wrong value (SEPARATE, both anon+explicit init; store is correct, read/index path wrong). Repro `repro/array_tagged_union_read` | `lower.zig`/`c89_emit.zig` (array elem read) | ❌ Separate |
| T28c | Same-type tagged-union variants (`union(enum){A:i32,B:i32}`) resolve payload by first-match TYPE — runtime-correct by union aliasing + correct tag; verified non-issue. Repro `repro/tagged_union_same_type` | `c89_emit.zig` (read+write variant match) | ✅ Non-issue |
| T29 | Switch capture-name-reuse READ bug (SEPARATE, study/quantified). Two sequential switches reusing capture `\|v\|` over same-typed payload variant: 2nd switch's capture read binds 1st switch's value; predictable `actual = N*A` (later payloads dropped); distinct names correct. `maybeDisambiguateCapture` only renames on TYPE mismatch; switch scope resets `capture_shadow` but not `local_decl_*`; first-match binding + c89 decl dedup cement collision. Repro `repro/switch_capture_name_reuse`. FIX = separate follow-on plan | `lower.zig:494-520,2815,931,1592`, `c89_emit.zig:1655-1682,2175-2186` | ❌ Separate |


**Legend**: ✅ Done | ⚠️ Partial | ❌ Missing | ⚠️ Attrib = Confirmed layer attribution, fix is separate future task | ❌ Deferred/Separate = out-of-scope, documented for a future plan
