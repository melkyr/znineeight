# Task 10 Step 2 Report — Root-Cause Investigation + STOP Checkpoint

## STATUS: READY FOR OPERATOR APPROVAL

---

## 1. Exact Narrow Condition + Mechanism

### Current code (the bug)

**`sf/src/lower.zig:2262-2266`** — the `comptime_values` general fold consumer:

```zig
if (hash_mod.u32ToU32MapGet(self.ctx.comptime_values, node_idx)) |cv| {
    var cres = nextTemp(self, type_mod.TYPE_USIZE);                                    // (A) always TYPE_USIZE
    emitInst(self, LirInst{ .int_const = .{ .value = @intCast(u64, cv), .result = cres } });
    var cm: []const u8 = "CEV\n"; pal.markerWrite(cm);
    return cres;                                                                       // (B) short-circuits, never hits cast path below
}
```

Line (A) unconditionally mints the folded temp as `TYPE_USIZE`. The folded value's actual (cast target) type is ignored. The `return` at (B) short-circuits the entire `builtin_call` handler — the non-folded `@intCast`/`@ptrCast` resolvers at lines 2278-2321 are never reached.

### The mechanism: `resolvedTypeTableGet`

**Pathway:**

1. The **semantic analyzer** (`semantic_analyzer.zig:1078-1082`) already resolves `@intCast(i64, expr)`'s target type:
   ```zig
   if (semanticAnalyzerIsTypeValueCast(self, node.child_0)) {
       _ = semanticAnalyzerResolveExpr(self, ec[@intCast(usize, 1)]);
       result = type_resolver.resolveTypeExprFull(&tre_env, ec[0], @intCast(u32, 0));
       // result = TYPE_I64 for @intCast(i64, ...)
   }
   ```

2. At `semantic_analyzer.zig:1218`, EVERY expression node gets its resolved type stored:
   ```zig
   rtt_mod.resolvedTypeTableSet(self.type_table, node_idx, result);
   // @intCast(i64,42) → node_idx → TYPE_I64
   // @intCast(usize,42) → node_idx → TYPE_USIZE
   // @sizeOf(T) → node_idx → TYPE_INT_LIT
   ```

3. The **lowerer** has access to the same table via `self.ctx.resolved_types` (confirmed at `main.zig:630` → `lower.zig:86`). It's already read at every node entry (`lower.zig:1018`):
   ```zig
   var rt = resolved_mod.resolvedTypeTableGet(self.ctx.resolved_types, node_idx);
   ```

4. The **pipeline order** is correct: semantic analysis (`phase_StaticAnalyzers`) runs before comptime evaluation (`phase_ComptimeEvaluation`) and LIR lowering. The `resolved_types` table is fully populated when the lowerer runs.

### Proposed narrow condition

```zig
if (hash_mod.u32ToU32MapGet(self.ctx.comptime_values, node_idx)) |cv| {
    var fold_type: u32 = type_mod.TYPE_USIZE;                         // default: preserve existing behavior
    if (node.child_0 == self.intcast_name_id) {                       // ONLY @intCast
        var rt = resolved_mod.resolvedTypeTableGet(
            self.ctx.resolved_types, node_idx);                       // reuse sema's work
        if (rt) |t| {
            if (t != type_mod.TYPE_USIZE
                and t != type_mod.TYPE_UNDEFINED
                and t != type_mod.TYPE_INT_LIT) {
                fold_type = t;                                        // narrow: non-usize integer target
            }
        }
    }
    var cres = nextTemp(self, fold_type);                             // typed correctly at the root
    emitInst(self, LirInst{ .int_const = .{ .value = @intCast(u64, cv), .result = cres } });
    var cm: []const u8 = "CEV\n"; pal.markerWrite(cm);
    return cres;
}
```

**Why this is the SINGLE narrowest mechanism:**

- **`node.child_0 == self.intcast_name_id`:** Only `@intCast` nodes. Excludes `@sizeOf`/`@alignOf` (different `child_0`), excludes `@ptrToInt` (handled at line 2252, returns before line 2262), excludes any future builtin folds.
- **`resolvedTypeTableGet`:** Reuses work the semantic analyzer already did. No re-resolution of type expressions. One hash-table lookup.
- **Guard `t != TYPE_USIZE`:** `@intCast(usize, N)` folds stay `TYPE_USIZE`. This is the load-bearing usize case — all game_of_life `@intCast(usize, 0)` struct-inits are untouched.
- **Guard `t != TYPE_UNDEFINED`:** If the type couldn't be resolved, don't propagate undefined types to the emitter.
- **Guard `t != TYPE_INT_LIT`:** `@sizeOf`'s resolved type is `TYPE_INT_LIT` (sema `:1077`). Even though `@sizeOf` doesn't match the `intcast_name_id` check (its `child_0` is `size_of_name_id`), this guard is defense-in-depth.

**What about option (a) — resolving `ec[0]` via `resolveTypeExprFull`?**

That duplicates work the semantic analyzer already completed. It's heavier (recursive type resolution) and would need a `TypeResolveEnv` construction at this call site. The `resolvedTypeTableGet` approach is simpler, faster, and uses already-validated data.

**What about option (b) — `resolvedTypeTableGet` without the `intcast_name_id` filter?**

Using `resolvedTypeTableGet` WITHOUT the `intcast_name_id` check would change fold typing for ALL builtins, not just `@intCast`. For example, `@sizeOf(T)` has a resolved type of `TYPE_INT_LIT` — if we used that, we'd emit a `TYPE_INT_LIT` temp, which the emitter doesn't handle. The `intcast_name_id` filter is the narrow guard.

---

## 2. Consumer Enumeration — Safety Analysis

Only ONE reader of `comptime_values` exists: `sf/src/lower.zig:2262`. The `cres` return value flows to all callers of `lowerExpr`. Consumer-by-consumer:

### 2.1 Struct_init field value (tagged-union payload) — the Task 3 case

**Path:** `lower.zig:2569-2631` (struct_init handling), specifically the tagged-union branch at `:2607`.
**Effect:** `cres` becomes `val_temp` at the `struct_init` field storage site.
**Old behavior:** TYPE_USIZE `val_temp` → retype patch (`:2627-2629`) overwrites `hoisted_temps[].type_id` to field type → emitter sees correct type → payload store works.
**New behavior:** TYPE_I64 `val_temp` (typed correctly at root) → retype patch is a NO-OP (field type == temp type) → emitter sees correct type directly → payload store works.
**Verdict:** **SAFE.** The retype patch becomes redundant.

### 2.2 Struct_init field value (ordinary struct) — `lower.zig:2635-2646`

**Path:** `struct_type` branch at line 2635. No retype patch exists here (the patch is only in the tagged-union branch).
**Effect:** `val_temp` is used directly in `assign_field`.
**Old behavior:** TYPE_USIZE temp for folded @intCast → field type mismatch? In practice, Z98 programs use @intCast correctly (target type == field type), so if the field is `usize`, the fold is `@intCast(usize, ...)` → TYPE_USIZE → no mismatch. If the field is `i32`, the fold is `@intCast(i32, ...)` → old: TYPE_USIZE → actual type mismatch (masked because the emitter might not check, or the struct field coercion handles it).
**New behavior:** Fold temp typed as field's target type → direct match → no mismatch.
**Verdict:** **SAFE.** Fixes a latent type mismatch in ordinary structs' folded @intCast field values.

### 2.3 Var_decl initialization

**Path:** `lower.zig:1046-1097` (var_decl lowering). The init expression is lowered via `lowerExpr`, which may return a comptime-folded temp.
**Effect:** The var_decl target type is checked against the init temp type.
**Old behavior:** Folded @intCast(T, val) → TYPE_USIZE → might not match var type → implicit coercion gap masked by same-width coincidence.
**New behavior:** Fold temp type == @intCast target type → matches var type when correctly written → no mismatch.
**Verdict:** **SAFE for correctly written code.** `var x: i64 = @intCast(i64, 42)` → temp is i64 → matches. `var x: usize = @intCast(i64, 42)` → temp is i64 → does NOT match usize → this IS correct behavior (the code has a type error that was previously masked).

### 2.4 Call argument

**Path:** `lower.zig:2107-2164` (fn_call argument lowering).
**Effect:** Same as var_decl — the call arg type should match param type.
**Old behavior:** TYPE_USIZE for all folded casts → potential mismatch masked.
**New behavior:** Correct target type → matches intCast usage.
**Verdict:** **SAFE.** Correctly written calls are already type-matched; our change makes the fold temp match reality.

### 2.5 Binary/unary/compare operand

**Path:** Lowering of `add/sub/mul/div/cmp` etc. where one operand is a comptime-folded @intCast.
**Effect:** The binary operation lowering may check operand types.
**Old behavior:** TYPE_USIZE for folded @intCast(i32, N) → comparison with i32 variable.
**New behavior:** TYPE_I32 for folded @intCast(i32, N) → both operands are i32.
**Verdict:** **SAFE.** More correct type alignment.

### 2.6 @sizeOf / @alignOf / @ptrToInt folds

**Path:** These nodes also enter the `comptime_values` fold path (line 2262).
**Old behavior:** TYPE_USIZE temp.
**New behavior:** The `intcast_name_id` check EXCLUDES them (their `node.child_0` is `size_of_name_id`/`align_of_name_id`, not `intcast_name_id`). They stay TYPE_USIZE.
**Verdict:** **SAFE.** No change for these folds.

### 2.7 @intCast(usize, N) folds

**Path:** Fold path at line 2262.
**Old behavior:** TYPE_USIZE.
**New behavior:** `resolvedTypeTableGet` returns TYPE_USIZE → the `t != TYPE_USIZE` guard keeps fold_type = TYPE_USIZE → no change.
**Verdict:** **SAFE.** byte-identical for man/gol/mud (game_of_life uses `@intCast(usize, 0)` extensively in struct_inits).

### 2.8 Unresolved @intCast types

**Path:** If the semantic analyzer couldn't resolve the @intCast target type, `resolvedTypeTableGet` returns TYPE_UNDEFINED.
**Old behavior:** TYPE_USIZE temp.
**New behavior:** Guard `t != TYPE_UNDEFINED` keeps fold_type = TYPE_USIZE.
**Verdict:** **SAFE.** Graceful fallback to existing behavior.

---

## 3. Patch-Removal Plan

### Current retype patch (lines 2627-2629)

```zig
if (val_temp != @intCast(u32, 0) and @intCast(usize, val_temp) < self.hoisted_temps.len) {
    self.hoisted_temps.items[@intCast(usize, val_temp)].type_id
        = self.ctx.registry.fe_items[fs + fj].type_id;
}
```

This overwrites `val_temp`'s hoisted-temp `type_id` to the variant field type. It was added in Task 3 to work around the fact that comptime-folded @intCast values arrive as TYPE_USIZE.

### After the root fix

The comptime-folded @intCast temp is already typed as the target type at the root (line 2262-2266 → `fold_type = resolved target type`). When this temp reaches the struct_init tagged-union branch:

1. `val_temp`'s `type_id` == field type (e.g., both are `TYPE_I64`)
2. The retype patch writes `field.type_id` into `hoisted_temps[val_temp].type_id` → same value → NO-OP
3. The emitter's tagged-union variant match (`c89_emit.zig` write-path) sees the correct type on the SRC temp and targets the correct union member

### Removal

Delete lines 2627-2629 entirely. The surrounding code becomes:

```zig
if (self.ctx.registry.fe_items[fs + fj].type_id != type_mod.TYPE_VOID) {
    emitInst(self, LirInst{ .assign_field = .{
        .name_id = @intCast(u32, 0),
        .base = base_temp,
        .field_id = type_mod.TU_FIELD_PAYLOAD,
        .src = val_temp,
    } });
}
```

### Verification

The Step 1 repro `repro/comptime_fold_typed_payload/main.zig` is the direct gate:
- WITH patch: GREEN (dump rc=0, gcc rc=0, run prints `42`)
- WITHOUT patch (Step 1 experiment): RED (gcc error: `incompatible types when assigning to type 'union <anonymous>' from type 'unsigned int'`)
- WITH root fix + WITHOUT patch: expected GREEN again — the fold temp is now typed `TYPE_I64` from the root, so gcc sees `zT_C69B2266_i64 zT_2 = 42; ... payload.Int._0 = zT_2;` — matching types.

`repro/tagged_union_payload` must still behave: prints `84` (the Task 7 capture-name-reuse bug is orthogonal).

---

## 4. Regression-Detection & Reconciliation Plan

### Detection (Step 3 gates)

1. **`repro/comptime_fold_typed_payload`** → GREEN (prints `42`)
2. **`repro/tagged_union_payload`** → still GREEN (prints `84`, the Task 7 bug unchanged)
3. **Corpus gate (132 repros `repro/mi_matrix/*/`):** classify by gcc EXIT CODE (NOT empty-stderr). Baseline: `OK=117 FAIL=14 ICE=1 CRASH=0`. Must stay `117/14/1/0` or improve. If ANY repro regresses (a previous OK becomes FAIL), STOP + present reconciliation.
4. **Byte-identical gate (man/gol/mud):** `--dump-c89` md5-compare against parent. man/gol must be byte-identical (game_of_life uses `@intCast(usize, N)` which stays TYPE_USIZE; mandelbrot's few casts are runtime). mud may differ if it was already differing — only report if new.

### What to do if a regression appears

**STOP.** Do NOT force the fix. Present:
- Which repro regressed
- The diff (old vs new emitted C)
- Diagnosis of what consumer broke
- Options: narrow the condition further, add a coercion at the consumer, or revert

### How @sizeOf/@alignOf/@ptrToInt are protected

| Fold type | `node.child_0` matches `intcast_name_id`? | Resolved type | Outcome |
|-----------|-------------------------------------------|---------------|---------|
| `@intCast(i64, N)` | YES | TYPE_I64 | **Uses TYPE_I64** (narrow change) |
| `@intCast(usize, N)` | YES | TYPE_USIZE | guard skips → TYPE_USIZE (no change) |
| `@intCast(u32, N)` | YES | TYPE_U32 | **Uses TYPE_U32** (narrow change) |
| `@sizeOf(T)` | NO (`size_of_name_id`) | TYPE_INT_LIT | guard skips → TYPE_USIZE (no change) |
| `@alignOf(T)` | NO (`align_of_name_id`) | TYPE_INT_LIT | guard skips → TYPE_USIZE (no change) |
| `@ptrToInt(p)` | NO (returns at line 2252 before line 2262) | TYPE_USIZE | never reaches fold path |
| `@enumToInt(e)` | NO (`enumtoint_name_id`, handled at `:2272`) | (resolved type) | handled before fold path? Let me check... `enumtoint` is at line 2272, AFTER the fold check. If `enumToInt` is in `comptime_values`, it hits line 2262 first. But `enumtoint` is NOT in `semanticAnalyzerIsTypeValueCast` (line 124-131), so its resolved type is TYPE_USIZE (semantic_analyzer.zig:1088 branch). The `intcast_name_id` guard excludes it → TYPE_USIZE. SAFE. |

---

## 5. Reconciliation with Typed-Comptime-Values Plan

### The shared edit site

Both Task 10 (this) and the `typed-comptime-values` plan (`.opencode/plans/2026-07-09-typed-comptime-values.md`) Task 4 edit `sf/src/lower.zig:2262-2266`.

### Task 10 runs FIRST (timeline)

Task 10's proposed change at 2262-2266:

```zig
if (hash_mod.u32ToU32MapGet(self.ctx.comptime_values, node_idx)) |cv| {
    var fold_type: u32 = type_mod.TYPE_USIZE;
    if (node.child_0 == self.intcast_name_id) {
        var rt = resolved_mod.resolvedTypeTableGet(self.ctx.resolved_types, node_idx);
        if (rt) |t| {
            if (t != type_mod.TYPE_USIZE and t != type_mod.TYPE_UNDEFINED and t != type_mod.TYPE_INT_LIT) {
                fold_type = t;
            }
        }
    }
    var cres = nextTemp(self, fold_type);
    emitInst(self, LirInst{ .int_const = .{ .value = @intCast(u64, cv), .result = cres } });
    ...
}
```

### Typed-comptime-values Task 4's intent

That plan wants to type ALL comptime values by their actual target (signed/width-aware). When it runs, it will have a typed store (not just a `u32` value). The `comptime_values` map will carry type info. Its Task 4 will need to read the fold value AND its type from the store, and mint the temp accordingly.

### How they reconcile

**Task 10's change is a SUBSET of typed-comptime-values' goal.** Task 10 handles `@intCast` folds only. The typed-comptime-values plan needs to handle ALL folds (including `@intCast`, `@sizeOf`, `@alignOf`, binops, etc.) with their correct types.

When typed-comptime-values Task 2 reads Task 10's code, it will see:
1. A `fold_type` that's conditionally set from `resolvedTypeTableGet` for `@intCast`
2. The rest stays `TYPE_USIZE`

The typed-comptime-values Task 4 can then:
- **Extend** the logic: read the type from the new typed store instead of (or in addition to) `resolvedTypeTableGet`
- **Keep** the `@intCast` path as-is (it's already correct)
- **Add** handling for other fold types

**There is NO conflict.** Task 10's narrow change is a conservative, incremental improvement that typed-comptime-values can build on top of. The typed-comptime-values plan should re-read the region after Task 10 lands, and its Task 2 investigation should note the then-current state.

### Concrete recommendation

In the typed-comptime-values plan Task 4, after reading Task 10's code:
- The fold-type logic can be restructured: read the value's type from the new typed store directly, falling back to `resolvedTypeTableGet` for backward compat during migration.
- Or, the new typed store already carries the correct type for ALL folds, making the `resolvedTypeTableGet` lookup unnecessary (it becomes subsumed).
- Either way: **no conflict, just a natural extension.**

---

## 6. Exact Proposed Edit (for Operator Approval)

### Change at `sf/src/lower.zig:2262-2266` (the fold typing)

**BEFORE:**
```zig
            if (hash_mod.u32ToU32MapGet(self.ctx.comptime_values, node_idx)) |cv| {
                var cres = nextTemp(self, type_mod.TYPE_USIZE);
                emitInst(self, LirInst{ .int_const = .{ .value = @intCast(u64, cv), .result = cres } });
                var cm: []const u8 = "CEV\n"; pal.markerWrite(cm);
                return cres;
            }
```

**AFTER:**
```zig
            if (hash_mod.u32ToU32MapGet(self.ctx.comptime_values, node_idx)) |cv| {
                var fold_type: u32 = type_mod.TYPE_USIZE;
                if (node.child_0 == self.intcast_name_id) {
                    var rt = resolved_mod.resolvedTypeTableGet(self.ctx.resolved_types, node_idx);
                    if (rt) |t| {
                        if (t != type_mod.TYPE_USIZE and t != type_mod.TYPE_UNDEFINED and t != type_mod.TYPE_INT_LIT) {
                            fold_type = t;
                        }
                    }
                }
                var cres = nextTemp(self, fold_type);
                emitInst(self, LirInst{ .int_const = .{ .value = @intCast(u64, cv), .result = cres } });
                var cm: []const u8 = "CEV\n"; pal.markerWrite(cm);
                return cres;
            }
```

### Deletion at `sf/src/lower.zig:2627-2629` (the retype patch)

**DELETE these three lines:**
```zig
                                if (val_temp != @intCast(u32, 0) and @intCast(usize, val_temp) < self.hoisted_temps.len) {
                                    self.hoisted_temps.items[@intCast(usize, val_temp)].type_id = self.ctx.registry.fe_items[fs + fj].type_id;
                                }
```

**Surrounding context after deletion:**
```zig
                            if (self.ctx.registry.fe_items[fs + fj].type_id != type_mod.TYPE_VOID) {
                                emitInst(self, LirInst{ .assign_field = .{ .name_id = @intCast(u32, 0), .base = base_temp, .field_id = type_mod.TU_FIELD_PAYLOAD, .src = val_temp } });
                            }
```

---

## 7. Surprises / Contradictions

**None found.** The evidence chain is clean:

1. ✅ The bug is confirmed real and masked by the Task 3 retype patch (Step 1 evidence)
2. ✅ The mechanism (`resolvedTypeTableGet` for @intCast nodes) is verified: semantic analyzer stores the target type (line 1218), pipeline order ensures availability
3. ✅ All consumers are safe: @sizeOf/@alignOf/@ptrToInt/@enumToInt folds are excluded by the `intcast_name_id` guard
4. ✅ `@intCast(usize, N)` folds stay TYPE_USIZE (guard `t != TYPE_USIZE`)
5. ✅ The typed-comptime-values plan can build on top of this change without conflict
6. ✅ The patch removal is clean: after the root fix, the patch becomes a no-op

**One cautionary note:** `@intCast(u32, N)` folds will change from TYPE_USIZE to TYPE_U32. On a 32-bit target (this compiler's target), both are 32-bit unsigned — the C emission is `unsigned int` in both cases (TYPE_USIZE is `typedef unsigned int ...` and TYPE_U32 is the same). So byte-identical and behavior-identical. However, if any consumer checks `type_id` for equality against `TYPE_USIZE` (rather than checking bit-width), a mismatch could occur. The corpus gate will detect any such case.

---

## STOP CHECKPOINT

This is the MANDATORY STOP as specified in Task 10 Step 2. Awaiting operator approval before Step 3 implementation.

**Summary for operator:**
1. **Narrow condition:** `resolvedTypeTableGet` for `@intCast` nodes with non-usize, non-undefined, non-int-lit target type
2. **Consumer verdict:** All SAFE — the `intcast_name_id` guard protects @sizeOf/@alignOf/@ptrToInt; the `t != TYPE_USIZE` guard protects @intCast(usize,...)
3. **Proposed edit:** change 3 lines at 2262-2266 + delete 3 lines at 2627-2629
4. **Reconciliation:** Task 10 runs first, typed-comptime-values extends it — no conflict
5. **Regression plan:** corpus 117/14/1/0 gate + man/gol byte-identical; STOP on any regression
6. **No surprises**

---

## 8. Reconciliation Note — 2026-07-09 (tagged-union-slice-payload fix)

Task 10 §2.1's conclusion that the `lower.zig:2627-2629` retype patch was "redundant" held **only** for comptime-folded `@intCast` payloads (whose value type already matched the field type after the fold typing fix). It **overlooked** non-folded payloads whose value type differs from the field type — specifically slice payloads suffering the `semantic_analyzer.zig:1602` const-loss bug (Fault A). When the retype patch was removed at commit `cce4b70f`, slice-payload construction `Token{ .Symbol = sym }` (base `[]const u8`, typed as `[]u8` due to the hardcoded `is_const=false`) broke variant selection in `c89_emit.zig` — the emitter could not match `[]u8` against the union field's `[]const u8`, producing bare `.payload = sym` and gcc errors.

The correct fix is at the semantic analyzer layer (const propagation, commit `0284d7a4` at `semantic_analyzer.zig:1602`), superseding the removed mask. This is the right layer for the fix: slice-expr semantics define `is_const` from the base, not from emitter convenience. Fix A alone sufficed; backend-agnostic Option L was not needed. The lisp interpreter now compiles and runs correctly for literal expressions; a separate pre-existing eval/apply bug (`(+ 1 2)` → `Eval error: Other`) remains out of scope.

**Lesson:** §2.1's "retype patch redundant" claim was insufficiently guarded — it presumed all payloads were comptime-folded integers. Non-folded payloads with differing value↔field types still depended on the retype patch as a correct-type bridge. The proper approach is to fix type derivation at the semantic layer so that the value type always matches the field type.
