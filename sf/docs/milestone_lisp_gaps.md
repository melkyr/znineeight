# Milestone Lisp — Compiler Gaps for Lisp Interpreter Bootstrap

## 1. Executive Summary

The lisp interpreter (`examples/lisp_interpreter_curr/`, 10 files, 1009 lines) does not compile. 16 gaps across 5 subsystems prevent end-to-end compilation. The interpreter uses `try` (73x), `@ptrCast` (17x), `catch` (4x), `@ptrToInt` (2x), `@intToPtr` (2x), `continue`, `break`, `unreachable`, optional `?` types, and error unions. C89 emission is the bottleneck: 10 LIR instructions silently emit nothing (`else => {}` at c89_emit.zig:2834).

**Reference docs:** `sf/docs/milestone0.md` (pipeline + task format), `sf/docs/zig0_bootstrap_manual.md` (quirks §9, §6, §7, §8).

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
| G19 | c89_emit | `c89_emit.zig:1264` | Multi-module output duplication — functions emitted 2-3× (T9 regression) | Critical | ❌ |
| G20 | Lowerer | `lower.zig:3117` | Lowerer `func.return_type` still TYPE_VOID despite RTT having error union TypeId | Critical | ❌ |

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

**Status:** ❌

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
| T15 | Coercion chain for error union patterns (G18) | `sema.zig` | ❌ |
| T16 | Integration test (lisp compiles + runs + mud/man/gol regression) | All | ❌ |
| T17 | Multi-module output duplication — functions emitted 2-3× (G19, T9 regression) | `c89_emit.zig` | ❌ |
| T18 | Lowerer `func.return_type` still TYPE_VOID despite RTT having error union TypeId (G20) | `lower.zig` | ❌ |

**Legend**: ✅ Done | ⚠️ Partial | ❌ Missing
