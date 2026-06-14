# Milestone Lisp — Compiler Gaps for Lisp Interpreter Bootstrap

## 1. Executive Summary

The lisp interpreter (`examples/lisp_interpreter_curr/`, 10 files, 1009 lines) does not compile. 16 gaps across 5 subsystems prevent end-to-end compilation. The interpreter uses `try` (73x), `@ptrCast` (17x), `catch` (4x), `@ptrToInt` (2x), `@intToPtr` (2x), `continue`, `break`, `unreachable`, optional `?` types, and error unions. C89 emission is the bottleneck: 10 LIR instructions silently emit nothing (`else => {}` at c89_emit.zig:2834).

**Reference docs:** `sf/docs/milestone0.md` (pipeline + task format), `sf/docs/zig0_bootstrap_manual.md` (quirks §9, §6, §7, §8).

## 2. Gap Inventory

| # | Subsystem | File | Gap | Severity |
|---|-----------|------|-----|----------|
| A1 | Import | `import_resolver.zig:66` | moduleRegistryResolveImports segfault — corrupted shared_store.nodes.items at module 7 | Critical |
| B1 | Sema | `semantic_analyzer.zig:838` | @ptrCast builtin_call → no name dispatch | High |
| B2 | Sema | `semantic_analyzer.zig:853` | catch |err| capture not registered | High |
| C1 | Lowerer | `lower.zig:1576` | @ptrCast builtin_call → no name dispatch | High |
| C2 | Lowerer | `lower.zig:1622` | catch |err| addLocalDecl missing | High |
| P0 | Parser | `parser.zig:239` | catch_capture ISOLATED in Parser field, not stored in catch_expr AST node | High |
| D1 | c89_emit | `c89_emit.zig:2834` | check_error LIR → no C code | Critical |
| D2 | c89_emit | `c89_emit.zig:2834` | unwrap_error_payload LIR → no C code | Critical |
| D3 | c89_emit | `c89_emit.zig:2834` | unwrap_error_code LIR → no C code | Medium |
| D4 | c89_emit | `c89_emit.zig:2834` | check_optional LIR → no C code | Medium |
| D5 | c89_emit | `c89_emit.zig:2834` | unwrap_optional LIR → no C code | Medium |
| D6 | c89_emit | `c89_emit.zig:2834` | wrap_error_ok LIR → no C code | High |
| D7 | c89_emit | `c89_emit.zig:2834` | wrap_error_err LIR → no C code | High |
| D8 | c89_emit | `c89_emit.zig:2834` | ptr_cast LIR → no C code | High |
| D9 | c89_emit | `c89_emit.zig:2834` | ptr_to_int LIR → no C code | Medium |
| D10 | c89_emit | `c89_emit.zig:2834` | int_to_ptr LIR → no C code | Medium |

## 3. Task Details

---

### T1: Fix Import Resolution Segfault

**File:** `sf/src/import_resolver.zig` (moduleRegistryResolveImports)

**Root cause (verified 2026-06-14):** GDB shows SIGSEGV at `import_resolver.c:626` — `shared_store->nodes.items[(usize)decls.ptr[di2]]` during phase_SymbolRegistration for module 7 (builtins.zig, 4848 bytes source, 1208 declarations). Crash is in `moduleRegistryResolveImports`, called from `phase_ImportResolution`. 0 lines C output produced. mud_server works (1505 lines).

The `p_arena_buf` is 4096 bytes per import, reset each iteration. Not an arena size issue.

**Possible causes:**
1. `decls.ptr[di2=67]` contains an out-of-bounds node index → `nodes.items[bad_index]` segfaults
2. `shared_store.nodes.items` pointer corrupted by prior module parsing using same shared store
3. Multi-module shared AST store state leak between import iterations

**Plan:**
1. GDB break at `import_resolver.c:626` → print `decls.ptr[67]` value + `shared_store->nodes` state
2. Check if `decls.ptr[67]` is a valid node index (< nodes.len)
3. If valid: trace which prior module corrupted `nodes.items` pointer
4. If invalid: trace how bad node index got into extra_children

**Reference:** sf/docs/memory_audit_m0.md (shared store pattern), sf/docs/zig0_bootstrap_manual.md §13 (import patterns)

**Status:** ❌

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

**Design reference:** `c89_emit.zig:2705-2719` — `.wrap_optional` emits two-field assignment pattern. Follow this EXACTLY.

**Lowerer flow** (`applyCoercion`, lower.zig:2979-2986):
- `wrap_error_success` → emits `wrap_error_ok{value, result, type_id}`
- `wrap_error_err` → emits `wrap_error_err{value, result, type_id}`

**Plan D6 — `.wrap_error_ok` handler:**
```zig
.wrap_error_ok => |w| {
    var dst = resolveTempName(emitter, w.result);
    var src = resolveTempName(emitter, w.value);
    bufferedWriterWriteIndent(&emitter.writer, emitter.indent);
    bufferedWriterWrite(&emitter.writer, dst);
    var l1: []const u8 = ".data.payload = ";
    bufferedWriterWrite(&emitter.writer, l1);
    bufferedWriterWrite(&emitter.writer, src);
    var semi1: []const u8 = ";\n";
    bufferedWriterWrite(&emitter.writer, semi1);
    bufferedWriterWriteIndent(&emitter.writer, emitter.indent);
    bufferedWriterWrite(&emitter.writer, dst);
    var l2: []const u8 = ".is_error = 0;\n";
    bufferedWriterWrite(&emitter.writer, l2);
},
```
**C output:**
```
zT_N.data.payload = zT_M;
zT_N.is_error = 0;
```

**Plan D7 — `.wrap_error_err` handler:**
```zig
.wrap_error_err => |w| {
    var dst = resolveTempName(emitter, w.result);
    var src = resolveTempName(emitter, w.value);
    bufferedWriterWriteIndent(&emitter.writer, emitter.indent);
    bufferedWriterWrite(&emitter.writer, dst);
    var l1: []const u8 = ".data.err = ";
    bufferedWriterWrite(&emitter.writer, l1);
    bufferedWriterWrite(&emitter.writer, src);
    var semi1: []const u8 = ";\n";
    bufferedWriterWrite(&emitter.writer, semi1);
    bufferedWriterWriteIndent(&emitter.writer, emitter.indent);
    bufferedWriterWrite(&emitter.writer, dst);
    var l2: []const u8 = ".is_error = 1;\n";
    bufferedWriterWrite(&emitter.writer, l2);
},
```
**C output:**
```
zT_N.data.err = zT_M;
zT_N.is_error = 1;
```

**Zig0 constraints for T4:**
- Same two-line pattern as `.wrap_optional` at line 2705 (proven working)
- All strings in named variables (quirk §9.3)
- Indent must be explicitly written per line (not auto-indented by bufferedWriter)

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

### T6: Int/Ptr Casts (D9, D10)

**File:** `sf/src/c89_emit.zig`

**Design reference:** `.int_cast` at line 2720 — uses `getCTypeName` + `(ctype)src`.

**Plan D9 — `.ptr_to_int` handler:**
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

**Plan D10 — `.int_to_ptr` handler:**
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
    // Register as local_decl with error set type
    if (self.local_decl_count >= self.local_decl_cap) { semanticAnalyzerGrowLocalDecls(self); }
    self.local_decl_name_map.put(capture_node.payload, self.local_decl_count); // use nameMap if hash-based
    self.local_decl_names[self.local_decl_count] = capture_node.payload;
    self.local_decl_types[self.local_decl_count] = TYPE_U32; // error code is u32
    self.local_decl_count += 1;
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
| T1 | Parser scratch arena 64→256 | `parser.zig` | ✅ |
| T2 | @ptrCast end-to-end | `sema.zig`, `lower.zig`, `c89_emit.zig` | ❌ |
| T3 | check_error + unwrap_error_payload + unwrap_error_code | `c89_emit.zig` | ❌ |
| T4 | wrap_error_ok + wrap_error_err | `c89_emit.zig` | ❌ |
| T5 | check_optional + unwrap_optional | `c89_emit.zig` | ❌ |
| T6 | ptr_to_int + int_to_ptr | `c89_emit.zig` | ❌ |
| T7 | catch |err| capture | `parser.zig`, `sema.zig`, `lower.zig` | ❌ |
| T8 | Integration test (lisp + mud/man/gol regression) | All | ❌ |

**Legend**: ✅ Done | ⚠️ Partial | ❌ Missing
