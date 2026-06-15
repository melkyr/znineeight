# Milestone Lisp — Compiler Gaps for Lisp Interpreter Bootstrap

## 1. Executive Summary

The lisp interpreter (`examples/lisp_interpreter_curr/`, 10 files, 1009 lines) does not compile. 16 gaps across 5 subsystems prevent end-to-end compilation. The interpreter uses `try` (73x), `@ptrCast` (17x), `catch` (4x), `@ptrToInt` (2x), `@intToPtr` (2x), `continue`, `break`, `unreachable`, optional `?` types, and error unions. C89 emission is the bottleneck: 10 LIR instructions silently emit nothing (`else => {}` at c89_emit.zig:2834).

**Reference docs:** `sf/docs/milestone0.md` (pipeline + task format), `sf/docs/zig0_bootstrap_manual.md` (quirks §9, §6, §7, §8).

## 2. Gap Inventory

| # | Subsystem | File | Gap | Severity | Status |
|---|-----------|------|-----|----------|--------|
| A1 | Import/Parser | `parser.zig:1100` | decl_buf[64] overflow → AST shared_store corruption | Critical | ✅ |
| P1 | Parser | `main.zig:29` | Parse error cascade (256), root: `.*` deref → dot_star token gap | Critical | ✅ |
| T1.5 | Parser | `parser.zig:297-301` | dot_star token not handled in postfix chain → `x.*` universal failure | Critical | ✅ |
| B1 | Sema | `semantic_analyzer.zig:838` | @ptrCast builtin_call → name dispatch + type resolution | High | ✅ |
| B2 | Sema | `semantic_analyzer.zig:853` | catch \|err\| capture not registered | High | ❌ |
| C1 | Lowerer | `lower.zig:1576` | @ptrCast builtin_call → name dispatch + ptr_cast LIR + ptr_type resolution | High | ✅ |
| C2 | Lowerer | `lower.zig:1622` | catch \|err\| addLocalDecl missing | High | ❌ |
| C3 | Parser | `parser.zig:381` | catch_capture not save/restored → nested catch corruption | Medium | ❌ |
| P0 | Parser | `parser.zig:239` | catch_capture ISOLATED in Parser field, not stored in catch_expr AST node | High | ❌ |
| P2 | Parser | `parser.zig:1221` | `!T` error union as fn return type (fn foo() !void {) | High | ❌ |
| D1 | c89_emit | `c89_emit.zig:2834` | check_error LIR → no C code | Critical | ✅ |
| D2 | c89_emit | `c89_emit.zig:2834` | unwrap_error_payload LIR → no C code | Critical | ✅ |
| D3 | c89_emit | `c89_emit.zig:2834` | unwrap_error_code LIR → no C code | Medium | ✅ |
| D4 | c89_emit | `c89_emit.zig:2834` | check_optional LIR → no C code | Medium | ✅ |
| D5 | c89_emit | `c89_emit.zig:2834` | unwrap_optional LIR → no C code | Medium | ✅ |
| D6 | c89_emit | `c89_emit.zig:2834` | wrap_error_ok LIR → no C code | High | ✅ |
| D7 | c89_emit | `c89_emit.zig:2834` | wrap_error_err LIR → no C code | High | ✅ |
| D8 | c89_emit | `c89_emit.zig:2834` | ptr_cast LIR → no C code | High | ✅ |
| D9 | c89_emit/sema/lowerer | `c89_emit.zig:2834` | ptr_to_int LIR — missing 3-layer pipeline (sema+lowerer+c89) | Medium | ✅ |
| D10 | c89_emit/sema/lowerer | `c89_emit.zig:2834` | int_to_ptr LIR — missing 3-layer pipeline (sema+lowerer+c89) | Medium | ✅ |
| E1 | c89_emit | `c89_emit.zig:1264-1278` | Single-file --dump-c89 output duplication (module emitted 2×) | High | ❌ |

## 3. Task Details

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

**File:** `examples/lisp_interpreter_curr/eval.zig`

**Current state (2026-06-14):** After T1 fix, lisp produces 256 diagnostic errors (cap). The very first error is at `main.zig:29:13: error[2000]: bad tok` — parser cannot handle `fn print_value(v: *value_mod.Value) void {`. 9 of 10 lisp files share this failure pattern (only `print_str` with simple `[]const u8` parameter succeeds). No code reaches sema, lowerer, or c89_emit. T2-T8 are blocked until parser succeeds.

**Plan:**
1. Read `eval.zig` at line 69 → identify what token/syntax causes "unexpected token"
2. Check if the syntax is valid Z98 (e.g., `const`, `try`, `switch`, `@ptrCast`) or lisp-specific (e.g., custom tagged union patterns)
3. If valid Z98 but parser rejects: fix parser gap
4. If not in Z98 subset: document as lisp source issue
5. Repeat for next error until parser produces 0 syntax errors (or meaningful sema errors)
6. Once parse succeeds, T2-T8 validation can begin

**Likely offenders (by frequency in lisp source):**
| Syntax | Count | In Z98 subset? | Parser handling |
|--------|-------|-----------------|-----------------|
| `const` | 143x | YES (from b71 parser audit) | `parserParseStatement` routes to `parserParseVarDecl` |
| `try` | 73x | YES (from b71) | `parserParsePrimary` → `parserParseTryExpr` |
| `@ptrCast` | 17x | YES (from b71) | `parserParsePrimary` → builtin_call |
| `switch` | 56x | YES (from b71) | `parserParseSwitchExpr` |
| `?T` optional type | — | YES (from b71) | `parserParseOptionalType` |
| `!T` error union type | — | YES | `parserParseType` |

**Priority:** Critical — blocks all downstream tasks.

**Status:** ❌ (New)

---

### T1.5: Diagnose + Fix `*Module.Type` Parser Gap

**File:** `sf/src/parser.zig` (parserParseFnDecl, parserParseType, parserParseTypeName)

**Root cause (hypothesis, 2026-06-14):** After T1 fix, all 10 lisp files produce 256 parse errors. First error at `main.zig:29:13` — `fn print_value(v: *value_mod.Value) void {`. The parser successfully handles:
- `fn print_str(s: []const u8) void {` — simple slice type (line 17, works)
- `const value_mod = @import("value.zig")` — module imports (line 2, works)

But fails at `*value_mod.Value` — pointer-to-module-qualified-name as parameter type. The `parserParseType` chain (`*` → `parserParsePtrType` → `parserParseType` → `parserParseTypeName` → `value_mod`+`.Value` field access) and `parserParseFnDecl` param loop look correct in source. Suspicion: either a subtle interaction between `child_buf` save/restore and nested type parsing, or the `parserParseType`→`parserParseTypeName`→`dot`→`field_access` chain drops a token at the wrong position causing `parserParseFnDecl` line 1232 `parserExpect(rparen)` to see wrong token.

**Cross-reference:** The `switch (v.*)` at line 29 body uses `.*` deref. The dot-star fix (parser.zig:315 `@intCast(u32, @enumToInt(tok.kind)) == ...`) is already applied but rarely tested with `switch` expressions — could be a separate latent gap.

**Objectives:**
1. GDB at `parserParseFnDecl` line 1221 → verify `parserPeek(self).kind` before/after `parserParseType` on `*value_mod.Value`
2. Trace parser position through `parserParsePtrType` → `parserParseTypeName` → back to while loop
3. Identify the exact token that fails at line 1230/1231 (comma skip or rparen exit)
4. Fix: if in `parserParseType` chain, correct token consumption; if in `parserParseFnDecl` loop, correct exit condition

**Zig0/GDB constraints:**
- Build: `gcc -m32 -g -O0 -std=c89 -Wno-long-long -Iinclude out_release/*.c -o out_release/zig1_dbg`
- Break method: `break parser.c:LINENO` (find generated C lines via grep)
- Print token: `p self->pos`, `p tok.kind`, `p self->source_ptr[self->pos]`
- Minimal reproduction: `fn foo(x: *mod.Type) void {}` (single file, 0 imports)

**Test plan:**
```bash
# Build debug
rm -rf out_release && mkdir -p out_release
./sf/build/zig0 --header-priority-include -o out_release/zig1.c sf/src/main.zig
gcc -m32 -g -O0 -std=c89 -Wno-long-long -Iinclude out_release/*.c -o out_release/zig1_dbg

# Test: Create minimal file with only the failing pattern
echo 'const m = @import("module"); fn f(x: *m.T) void {}' > /tmp/t15.zig
./out_release/zig1 --dump-c89 /tmp/t15.zig 2>&1 | head -20
# Expected: 0 errors or single parse error on the correct token

# Full lisp test after fix
./out_release/zig1 --dump-c89 examples/lisp_interpreter_curr/main.zig 2>/tmp/lisp_err.txt
grep -c "error\[2000\]" /tmp/lisp_err.txt
# Expected: < 256 (fewer, ideally 0, parse errors)

# Regression
./out_release/zig1 --dump-c89 examples/mud_server/main.zig > /tmp/mud.c
gcc -m32 -std=c89 ... 2>&1 | grep -c "error:"  # expect 0
```

**Status:** ❌ (New)

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

**Status:** ❌ (New)

### T7: catch |err| Capture

**Files:** `sf/src/parser.zig`, `sf/src/semantic_analyzer.zig`, `sf/src/lower.zig`

**Root cause:** Parser stores `payload_capture` node in `self.catch_capture` (parser field, line 49) but NEVER copies it into the `catch_expr` AST node. parserAddBinary (line 239) creates catch_expr with `child_0=lhs, child_1=rhs, child_2=0`. The capture is isolated in the parser struct and overwritten by next catch.

**Plan T7a — Parser fix (parser.zig parserAddBinary line 228-239):**
```zig
// In parserAddBinary, for catch_expr case:
TokenKind.kw_catch => { kind = AstKind.catch_expr; found = 1; },
// ...
// At line 239, instead of hardcoded 0 for child_2:
if (kind == AstKind.catch_expr) {
    return ast_mod.astStoreAddNode(self.store, kind, 0, tok.span_start, end, lhs, rhs, self.catch_capture, 0);
} else {
    return ast_mod.astStoreAddNode(self.store, kind, 0, tok.span_start, end, lhs, rhs, 0, 0);
}
```
This stores `child_2 = payload_capture_node` (0 if no `|err|` syntax).

**Plan T7b — Sema fix (sema.zig catch_expr handler line 853):**
```zig
// resolveExpr catch_expr handler (line 853), after resolving child_0:
result = semanticAnalyzerResolveExpr(self, node.child_0);
// NEW: check for capture
if (node.child_2 != 0) {
    var capture_node = self.store.nodes.items[@intCast(usize, node.child_2)];
    // capture_node.payload = name_id
    // Register as local_decl — error codes are u32 in Z98 subset
    if (self.local_decl_count >= self.local_decl_cap) { semanticAnalyzerGrowLocalDecls(self); }
    self.local_decl_names[self.local_decl_count] = capture_node.payload;
    self.local_decl_types[self.local_decl_count] = type_mod.TYPE_U32;
    self.local_decl_count += @intCast(usize, 1);
}
```

**Plan T7c — Lowerer fix (lower.zig catch_expr handler line 1622):**
```zig
// After lhs_temp = lowerExpr(child_0), before check_error:
if (node.child_2 != 0) {
    var capture_node = self.ctx.store.nodes.items[@intCast(usize, node.child_2)];
    // Register capture in lowerer locals (same as for/switch capture)
    addLocalDecl(self, capture_node.payload, TYPE_U32, 0, 0); // error code type = u32
}
```

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

### T8: Integration Test

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
| T1.5 | Dot-star parser gap → `switch(v.*)` and `.*` deref universal failure | `parser.zig` | ✅ |
| T2 | @ptrCast end-to-end (sema dispatch + lowerer LIR + c89_emit codegen) | `sema.zig`, `lower.zig`, `c89_emit.zig` | ✅ |
| T3 | check_error + unwrap_error_payload + unwrap_error_code handlers | `c89_emit.zig` | ✅ |
| T4 | wrap_error_ok + wrap_error_err | `c89_emit.zig` | ❌ |
| T5 | check_optional + unwrap_optional | `c89_emit.zig` | ❌ |
| T6 | @ptrToInt/@intToPtr end-to-end (sema+lowerer+c89) | `sema.zig`, `lower.zig`, `c89_emit.zig` | ✅ |
| T7 | catch \|err\| capture + nested save/restore | `parser.zig`, `sema.zig`, `lower.zig` | ❌ |
| T7.5 | Fix single-file --dump-c89 output duplication | `c89_emit.zig` | ❌ |
| T8 | Integration test (lisp + mud/man/gol regression) | All | ❌ |

**Legend**: ✅ Done | ⚠️ Partial | ❌ Missing
