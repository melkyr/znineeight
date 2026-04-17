# AST → LIR Lowering Design Specification

**Version:** 1.0  
**Component:** LIR lowering, control‑flow lifting, defer expansion, temporary hoisting  
**Parent Document:** `DESIGN.md v3.0` (Sections 6, 8), `TYPE_SYSTEM.md` (Section 5), `AST_PARSER.md`  
**Supersedes:** Bootstrap ad‑hoc lifting during codegen

---

## 0. Scope & Relationship to Pipeline

This document specifies the **AST → LIR Lowering** pass (Pipeline Step 6). It transforms the immutable, index‑based AST into a Linear Intermediate Representation (LIR) consisting of basic blocks and three‑address instructions. Lowering consumes semantic side‑tables and produces a CFG‑ready structure for optional optimization and deterministic C89 emission.

| Input | Source |
|---|---|
| `AstStore` | Parser output (immutable) |
| `ResolvedTypeTable` | Semantic analysis side‑table (`u32 node_idx → TypeId`) |
| `CoercionTable` | Semantic analysis side‑table (`u32 node_idx → CoercionEntry`) |
| `SymbolTable` | Scoped variable/function/module resolution |
| `TypeRegistry` | Fully resolved type layouts & payloads |

| Output | Consumer |
|---|---|
| `ArrayList(LirFunction)` | LIR Optimizer (Step 7), C89 Emitter (Step 8) |
| Global constant/temp pools | Emitter (static data section) |
| `DiagnosticCollector` | CLI error reporting (invalid patterns, OOM) |

**Key Invariant:** The AST is **never mutated**. Lowering is purely a translation pass that reads node indices, resolves types via side‑tables, applies coercions explicitly, and emits LIR instructions.

---

## 1. Lowering Context & State Management

The lowering pass is encapsulated in a stateful struct that tracks per‑function progression, control‑flow targets, and temporary generation.

```zig
pub const LirLowerer = struct {
    ctx: *SemanticContext,
    func: *LirFunction,
    current_bb: u32,                // currently emitting basic block
    temp_counter: u32,              // monotonically increasing for __tmp_N
    defer_stack: ArrayList(DeferAction),
    loop_stack: ArrayList(LoopInfo),
    switch_stack: ArrayList(SwitchInfo),
    hoisted_temps: ArrayList(TempDecl),
    alloc: *Allocator,
};

pub const DeferAction = struct {
    kind: u8,           // 0=defer, 1=errdefer
    ast_node: u32,      // deferred statement node index
    scope_depth: u32,   // nesting depth at declaration
};

pub const LoopInfo = struct {
    header_bb: u32,     // jump target for `continue`
    exit_bb: u32,       // jump target for `break`
    scope_depth: u32,
    label_id: u32,      // interned label name (0 = unlabeled)
};

pub const SwitchInfo = struct {
    exit_bb: u32,       // jump target after switch completes
    scope_depth: u32,
};
```

**Memory Strategy:**  
- `scratch` arena: `defer_stack`, `loop_stack`, `switch_stack`, per‑function temporaries. Reset after each function is lowered.
- `permanent` arena: `LirFunction` structs, global constant pools.
- No unbounded recursion: statement lowering uses an explicit worklist; expression lowering recurses at most O(AST depth) ≈ 50, bounded by parser limits.

---

## 2. Core Lowering Algorithm

Lowering processes one function at a time. The entry block is created, and statements are lowered iteratively. Expressions are lowered recursively but always return a `temp_id` that holds the result.

```zig
pub fn lowerFunction(self: *LirLowerer, fn_decl_idx: u32) !void {
    const fn_decl = self.ctx.store.nodes.items[fn_decl_idx];
    const proto = self.ctx.store.fn_protos.items[fn_decl.payload];
    
    // Initialize function & entry block
    self.func.name_id = proto.name_id;
    self.func.return_type = proto.return_type;
    self.addParametersToScope(proto);
    self.current_bb = self.createBlock();
    
    // Lower body statements
    const body = self.ctx.store.nodes.items[fn_decl.child_0];
    const stmts = self.ctx.store.getExtraChildren(body.payload);
    var i: usize = 0;
    while (i < stmts.len) : (i += 1) {
        try self.lowerStatement(stmts[i]);
    }
    
    // If function falls off end, inject implicit return
    if (!self.func.blocks.items[self.current_bb].is_terminated) {
        if (self.func.return_type == TYPE_VOID) {
            self.emitInst(.{ .ret_void = {} });
        } else {
            // Z98 requires explicit return for non‑void
            self.ctx.diag.append(.{ .level=0, .message="missing return" });
        }
    }
    
    // Hoist temporaries to top of entry block
    try self.hoistTemps();
}
```

---

## 3. Expression Lowering

Expressions evaluate to a temporary ID. The lowerer checks the `CoercionTable` after evaluation and injects explicit LIR cast/wrap instructions.

### 3.1 Per‑Kind Lowering Table

The following table defines the exact LIR sequence for every `AstKind` that can appear in expression position. All result temporaries are allocated via `nextTemp(result_type)`.

| `AstKind` | Lowering Sequence |
|---|---|
| `.int_literal` | `int_const(value, result)` |
| `.float_literal` | `float_const(value, result)` |
| `.string_literal` | `string_const(interned_id, result)` |
| `.char_literal` | `int_const(codepoint, result)` |
| `.bool_literal` | `bool_const(flag, result)` |
| `.null_literal` | `null_const(result)` |
| `.undefined_literal` | `undefined_const(result, type_id)` |
| `.unreachable_expr` | `unreachable` (no result; terminates block) |
| `.enum_literal` | `int_const(tag_value, result)` (folded from enum member) |
| `.error_literal` | `int_const(error_code, result)` |
| `.ident_expr` | `load_local(name_id, result)` or `load_global(name_id, result)` (based on `SymbolTable` lookup) |
| `.field_access` | For struct/union: `load_field(base_temp, field_id, result)`; for tuple: `load_index(base_temp, index_const, result)`; for slice `.ptr`/`.len`: `load_field(base_temp, field_id, result)` |
| `.index_access` | For array/slice/many‑ptr: `load_index(base_temp, index_temp, result)` |
| `.slice_expr` | Lower `base`, `start`, `end`. Emit `addr_of(base)` plus arithmetic for offset, then `make_slice(ptr, len, result, slice_type)` |
| `.deref` | `load(ptr_temp, result)` |
| `.address_of` | `addr_of(operand_temp, result)` |
| `.fn_call` | Lower callee → `__fn`. Lower args. Emit `call(__fn, arg_temps, result)` |
| `.builtin_call` | See Section 3.2 |
| `.add`, `.sub`, `.mul`, `.div`, `.mod_op` | `binary(op, lhs_temp, rhs_temp, result)` |
| `.bit_and`, `.bit_or`, `.bit_xor`, `.shl`, `.shr` | `binary(op, lhs_temp, rhs_temp, result)` |
| `.bool_and`, `.bool_or` | Lower as short‑circuit; generates temporary branches (see Section 4.1.3) |
| `.cmp_eq`, `.cmp_ne`, `.cmp_lt`, `.cmp_le`, `.cmp_gt`, `.cmp_ge` | `binary(cmp_op, lhs_temp, rhs_temp, result)` |
| `.assign` | `assign(dst_temp, src_temp)` |
| `.negate` | `unary(Negate, operand_temp, result)` |
| `.bool_not` | `unary(Not, operand_temp, result)` |
| `.bit_not` | `unary(BitNot, operand_temp, result)` |
| `.try_expr` | Lower inner expr → `__eu`. Emit `check_error(__eu, __is_err)`. Branch: if `__is_err` goto propagate; else `unwrap_error_payload(__eu, result)` |
| `.catch_expr` | Lower LHS → `__eu`. Emit `check_error(__eu, __is_err)`. Branch: if error, lower fallback (with optional capture); else unwrap payload. Result assigned in join. |
| `.orelse_expr` | Lower LHS → `__opt`. Emit `check_optional(__opt, __has_val)`. Branch: if `__has_val`, unwrap; else lower fallback. Result assigned in join. |
| `.if_expr` | Lower condition → `__cond`. `branch(__cond, then_bb, else_bb)`. Each branch evaluates sub‑expr, assigns to result temp, jumps to join. |
| `.switch_expr` | Lower condition → `__tag`. Emit `switch_br(__tag, cases, else_bb)`. Each case block assigns result temp and jumps to exit. |
| `.tuple_literal` | Emit `decl_temp(tuple_type, result)`. For each element at index `i`, `assign_index(result, i, elem_temp)`. |
| `.struct_init` | For typed init: `decl_temp(struct_type, result)`. For each field init, `assign_field(result, field_id, value_temp)`. Anonymous init with expected type: same. |
| `.field_init` | Not lowered directly; part of `.struct_init`. |
| `.import_expr` | Already resolved to module symbol; returns `TYPE_MODULE`. |
| `.paren_expr` | Lower inner expr directly. |

### 3.2 Builtin Call Lowering

| Builtin | Lowering |
|---|---|
| `@sizeOf`, `@alignOf` | Constant‑folded by comptime evaluation; lowered as `int_const`. |
| `@intCast` | `int_cast(value, target, result, is_checked=true)` |
| `@floatCast` | `float_cast(value, target, result)` |
| `@ptrCast` | `ptr_cast(value, target, result)` |
| `@intToPtr` | `int_to_ptr(value, target, result)` |
| `@ptrToInt` | `ptr_to_int(value, result)` |
| `@intToFloat` | `int_to_float(value, target, result)` |
| `@enumToInt` | No‑op; enum is already an integer. |
| `@intToEnum` | `int_cast` (or no‑op if same backing type). |
| `@import` | Resolved during symbol registration; does not appear in lowering. |

### 3.3 `std.debug.print` Decomposition

The semantic pass decomposes `std.debug.print` into a sequence of `print_str` and `print_val` instructions. Lowering simply emits them in order.

```zig
// Original: std.debug.print("x={d}\n", .{x});
// Lowered:
print_str("x=");
print_val(x_temp, TYPE_I32, 'd');
print_str("\n");
```

---

## 4. Control‑Flow Lifting

Control flow converts nested AST trees into flat basic blocks with explicit jumps.

### 4.1 `if` Statement & Expression

#### 4.1.1 `if` without `else` (Statement)

```
AST: if (cond) { A }
LIR:
  %cond = <lower cond>
  branch %cond, bb_A, bb_join
bb_A:
  <lower A>
  jump bb_join
bb_join:
```

#### 4.1.2 `if` with `else` (Statement)

```
AST: if (cond) { A } else { B }
LIR:
  %cond = <lower cond>
  branch %cond, bb_A, bb_B
bb_A:
  <lower A>
  jump bb_join
bb_B:
  <lower B>
  jump bb_join
bb_join:
```

#### 4.1.3 `if` Expression

```
AST: var x = if (cond) a else b;
LIR:
  %cond = <lower cond>
  branch %cond, bb_then, bb_else
bb_then:
  %val_a = <lower a>
  assign %result, %val_a
  jump bb_join
bb_else:
  %val_b = <lower b>
  assign %result, %val_b
  jump bb_join
bb_join:
  store_local(x, %result)
```

#### 4.1.4 Short‑Circuit `and` / `or`

Logical operators are lowered as explicit branches:

```
AST: a and b
LIR:
  %a = <lower a>
  branch %a, bb_rhs, bb_false
bb_rhs:
  %b = <lower b>
  assign %result, %b
  jump bb_done
bb_false:
  assign %result, false_const
  jump bb_done
bb_done:
```

### 4.2 `while` Loop

```
AST: while (cond) { body }
LIR:
  jump bb_cond
bb_cond:
  %cond = <lower cond>
  branch %cond, bb_body, bb_exit
bb_body:
  <lower body>
  jump bb_cond
bb_exit:
```

### 4.3 `for` Loop

#### 4.3.1 Range `for (0..n) |i| { body }`

```
LIR:
  %i = int_const 0
  %end = <lower n>
  jump bb_cond
bb_cond:
  %cmp = binary lt, %i, %end
  branch %cmp, bb_body, bb_exit
bb_body:
  ; i is bound as %i
  <lower body>
  %i = binary add, %i, 1
  jump bb_cond
bb_exit:
```

#### 4.3.2 Slice `for (slice) |item, idx| { body }`

```
LIR:
  %ptr = load_field %slice, .ptr
  %len = load_field %slice, .len
  %idx = int_const 0
  jump bb_cond
bb_cond:
  %cmp = binary lt, %idx, %len
  branch %cmp, bb_body, bb_exit
bb_body:
  %item = load_index %ptr, %idx
  ; idx is bound as %idx
  <lower body>
  %idx = binary add, %idx, 1
  jump bb_cond
bb_exit:
```

### 4.4 `switch` Statement & Expression

#### 4.4.1 Enum Switch

```
AST: switch (e) { .A => a, .B => b }
LIR:
  %tag = <lower e>
  switch_br %tag, [ (0, bb_A), (1, bb_B) ], else_bb
bb_A:
  %val_a = <lower a>
  assign %result, %val_a
  jump bb_exit
bb_B:
  %val_b = <lower b>
  assign %result, %val_b
  jump bb_exit
bb_exit:
```

#### 4.4.2 Tagged Union Switch with Payload Capture

```
AST: switch (u.*) { .Cons => |data| { ... }, .Nil => {} }
LIR:
  %tag = load_field %u, .tag
  switch_br %tag, [ (Cons_tag, bb_Cons), (Nil_tag, bb_Nil) ], else_bb
bb_Cons:
  %payload = load_field %u, .payload_Cons
  decl_local data_capture, ..., %payload   ; bind capture
  <lower Cons body>
  jump bb_exit
bb_Nil:
  <lower Nil body>
  jump bb_exit
else_bb:
  ; else / unreachable
```

### 4.5 `break` / `continue` / `return`

| AST | Lowering |
|---|---|
| `break` | Expand defers up to loop scope depth; `jump loop_stack.top().exit_bb` |
| `break :label` | Expand defers up to labeled loop scope; jump to labeled exit block |
| `continue` | Expand defers **inside current loop iteration**; `jump loop_stack.top().header_bb` |
| `continue :label` | Expand inner defers; jump to labeled loop header |
| `return expr` | Expand all defers in current function; `ret(temp)` |
| `return` (void) | Expand defers; `ret_void` |

---

## 5. Defer & Errdefer Expansion

### 5.1 Defer Stack Management

Defers are pushed onto a stack as they are parsed (in statement order). The `scope_depth` tracks the lexical nesting depth (0 = function top‑level).

```zig
fn pushDefer(self: *LirLowerer, kind: u8, ast_node: u32, scope_depth: u32) !void {
    try self.defer_stack.append(.{ .kind = kind, .ast_node = ast_node, .scope_depth = scope_depth });
}
```

### 5.2 Unwinding at Exit Points

At every control‑flow exit (`return`, `break`, `continue`, block end), the defer stack is unwound from top to the target scope depth.

```zig
fn expandDefers(self: *LirLowerer, target_depth: u32, is_error_path: bool) !void {
    var i = self.defer_stack.items.len;
    while (i > 0) {
        i -= 1;
        const action = self.defer_stack.items[i];
        if (action.scope_depth < target_depth) break;
        
        if (action.kind == 0) { // normal defer
            try self.lowerStatement(action.ast_node);
        } else if (action.kind == 1 and is_error_path) { // errdefer on error path only
            try self.lowerStatement(action.ast_node);
        }
    }
}
```

### 5.3 Tail‑Call Optimization (TCO) Pattern Handling

Z98 programs often implement TCO manually using `while (true)` + `continue`:

```zig
fn eval(...) !Value {
    defer { cleanup(); }
    while (true) {
        const expr = ...;
        switch (expr) {
            .Apply => { /* ... */ continue; },
            else => return result,
        }
    }
}
```

**Critical Rule:** On `continue`, only defers declared **inside the current iteration scope** are expanded. The outer `defer { cleanup(); }` (depth 0) is **not** expanded because the loop body has a higher scope depth (depth ≥1). The `LoopInfo.scope_depth` field tracks the scope at loop entry; `continue` expands down to `loop_info.scope_depth + 1`.

### 5.4 Error Path Detection

An exit is considered an **error path** if:
- It is a `return` of an error union value where the error payload is active.
- It is a `try` expression propagating an error.
- It is a `catch` fallback that does not resume normal execution.

The semantic pass annotates these exit points; lowering uses that information to conditionally expand `errdefer`.

---

## 6. Coercion Table Integration

The `CoercionTable` (from `TYPE_SYSTEM.md` Section 5.2) dictates explicit LIR transformations. Lowering applies them immediately after expression evaluation.

### 6.1 Coercion Mapping

| `CoercionKind` | LIR Instruction(s) Emitted |
|---|---|
| `none` | None |
| `wrap_optional` | `wrap_optional(value, result, target_type)` |
| `wrap_error_success` | `wrap_error_ok(value, result, target_type)` |
| `wrap_error_err` | `wrap_error_err(error_code, result, target_type)` |
| `array_to_slice` | `make_slice(addr_of(arr), len_const, result, slice_type)` |
| `array_to_many_ptr` | `addr_of(arr)` |
| `slice_to_many_ptr` | `load_field(slice, .ptr)` |
| `string_to_slice` | `make_slice(addr_of(lit), len_const, result, slice_type)` |
| `string_to_many_ptr` | `addr_of(lit)` (cast to `[*]const u8`) |
| `string_to_ptr` | `addr_of(lit)` (cast to `*const u8`) |
| `ptr_to_optional_ptr` | `wrap_optional(ptr, result, opt_type)` |
| `const_qualify_ptr` | No‑op in LIR (C89 emitter adds `const` qualifier) |
| `const_qualify_slice` | No‑op |
| `int_widen` | `int_cast(value, target, result, is_checked=false)` |
| `float_widen` | `float_cast(value, target, result)` |
| `int_literal_coerce` | `int_cast(value, target, result, is_checked=true)` |

### 6.2 Application Logic

```zig
fn applyCoercion(self: *LirLowerer, src_temp: u32, coercion: CoercionEntry) !u32 {
    const dst_temp = self.nextTemp(coercion.target_type);
    switch (coercion.kind) {
        .wrap_optional => self.emitInst(.{ .wrap_optional = .{ .value=src_temp, .result=dst_temp, .type_id=coercion.target_type } }),
        .int_widen => self.emitInst(.{ .int_cast = .{ .value=src_temp, .target=coercion.target_type, .result=dst_temp, .is_checked=false } }),
        // ... map all kinds
        else => return src_temp, // no‑op coercions
    }
    return dst_temp;
}
```

---

## 7. Temporary Hoisting & C89 Compliance

C89 requires all variable declarations at the top of their block. LIR collects temporaries during lowering, then hoists them before emission.

### 7.1 Temporary Generation

```zig
fn nextTemp(self: *LirLowerer, type_id: TypeId) u32 {
    self.temp_counter += 1;
    const temp_id = self.temp_counter;
    self.hoisted_temps.append(.{ .temp_id = temp_id, .type_id = type_id }) catch unreachable;
    return temp_id;
}
```

### 7.2 Hoisting Procedure

After the function body is lowered, all `decl_temp` instructions are inserted at the start of the entry block (before any other instructions).

```zig
fn hoistTemps(self: *LirLowerer) !void {
    const entry = &self.func.blocks.items[0];
    var hoisted_instructions = ArrayList(LirInst).init(self.alloc);
    
    var i: usize = 0;
    while (i < self.hoisted_temps.items.len) : (i += 1) {
        const t = self.hoisted_temps.items[i];
        if (t.type_id == TYPE_VOID) continue;
        try hoisted_instructions.append(.{ .decl_temp = .{ .temp = t.temp_id, .type_id = t.type_id } });
    }
    
    // Prepend to entry block
    var j: usize = 0;
    while (j < hoisted_instructions.items.len) : (j += 1) {
        try entry.insts.insert(j, hoisted_instructions.items[j]);
    }
}
```

### 7.3 C89 Restrictions Enforced

- No mixed declarations and code.
- All temporary variables are declared at block top.
- `void`‑typed temporaries are omitted.
- The emitter later assigns C names like `__tmp_N` for each temp.

---

## 8. Global Constant Pools

String literals and floating‑point constants are stored in global pools to avoid duplication and ensure C89 compatibility (no compound literals).

| Pool | Storage | LIR Access |
|---|---|---|
| String literals | `global_strings: ArrayList([]const u8)` | `string_const(pool_index, result)` |
| Float constants | `global_floats: ArrayList(f64)` | `float_const(pool_index, result)` |

The emitter outputs these as static arrays in the generated C file.

---

## 9. Memory Budget & Performance Analysis

For a typical 2000‑line Z98 module (e.g., one compiler pass):

| LIR Component | Per‑Item Size | Count | Total |
|---|---|---|---|
| `LirFunction` | ~200 bytes | ~50 | 10 KB |
| `BasicBlock` | ~40 bytes | ~300 | 12 KB |
| `LirInst` | 16–32 bytes | ~8,000 | 256 KB |
| `TempDecl` | 8 bytes | ~1,500 | 12 KB |
| **Total** | | | **~290 KB** |

For the entire self‑hosted compiler (~14,600 lines across ~17 modules), peak LIR memory is approximately **2–3 MB**, well within the 16 MB budget. The `scratch` arena is reset after each function, so peak usage is dominated by the largest function.

---

## 10. Z98 Constraints & Guarantees

| Constraint | Enforcement in Lowering |
|---|---|
| **Immutable AST** | Read‑only access; no node mutation; side‑tables drive all decisions |
| **No Unbounded Recursion** | Statement lowering uses iterative worklist; expression recursion bounded by parser depth |
| **C89 Declaration Hoisting** | All `decl_temp`/`decl_local` moved to block entry before emission |
| **Strict `@intCast` Semantics** | Coercion table injects `is_checked=true` where required; lowering respects bounds |
| **Deterministic Output** | Sequential BB IDs, sequential temp IDs, stable insertion order |
| **<16 MB Peak RAM** | `scratch` arena reset per function; LIR arrays pre‑allocated with reasonable capacity |
| **No Compound Literals** | Struct/array initializers decomposed to `assign_field`/`assign_index` sequences |
| **No Method Syntax** | Methods are desugared to free functions before lowering |
| **Explicit Error Propagation** | `try`/`catch` lowered to explicit branches and error‑union unwrapping |

---

## 11. Error Handling & Diagnostics

Lowering reports diagnostics for:

| Condition | Diagnostic |
|---|---|
| Missing `return` in non‑void function | Error: "function must return a value" |
| Unreachable code after `return`/`break`/`continue` | Warning: "unreachable code" (optional) |
| Exceeding temporary limit (>65535 per function) | Internal compiler error (ICE) |
| Switch non‑exhaustiveness | Already caught by semantic analysis; lowering may assert |
| Defer stack overflow | ICE (should not happen; bounded by scope depth) |

All diagnostics include file, line, and column information via `SourceManager`.

---

## 12. Extensibility Hooks

The architecture is designed for incremental post‑self‑hosting upgrades:

| Feature | Extension Point |
|---|---|
| `comptime` blocks | Parser marks `comptime` AST nodes; lowering skips them entirely, injecting pre‑computed constants |
| Generics (`anytype`) | Monomorphization occurs **before** lowering; each concrete copy is lowered independently |
| Method syntax | Desugar `obj.method()` → `Type.method(obj)` in semantic analysis; lowering treats as normal `fn_call` |
| LIR Optimizations | Pass 7 operates on `LirFunction`; lowering produces clean three‑address code ready for constant folding, DCE, copy propagation |
| New Backends | LIR is backend‑agnostic; C89 emitter walks blocks linearly. LLVM/x86 backend consumes identical structure |
| Inline Assembly | Add `asm` AstKind; lowering emits `asm` LIR instruction with string and operand list |

---

## 13. Testing Strategy

| Test Layer | Input | Verified Property |
|---|---|---|
| **Unit: Expression Lowering** | `.add`, `.mul`, `.int_cast` AST nodes | Correct `binary`/`cast` LIR, temp reuse |
| **Unit: Control Flow** | `if`, `while`, `switch` snippets | Correct `branch`/`switch_br`, join blocks, no dead code |
| **Unit: Defer Expansion** | Nested `defer`/`errdefer` + `return`/`break` | Defers emitted in reverse order, errdefers conditional |
| **Integration: `eval.zig`** | 7‑level tagged union switch + TCO | Correct `switch_br` nesting, `continue` skips outer defers |
| **Integration: `mud.zig`** | Struct init, slice creation, `@ptrCast` | Field‑by‑field assignment, `make_slice`, explicit casts |
| **Integration: `mandelbrot.zig`** | Float arithmetic, `extern` calls | Float constants, function call lowering |
| **Differential: `--dump-lir`** | All reference programs | Byte‑identical LIR across deterministic runs |
| **Memory Gate** | `zig1.zig` compilation | Peak `scratch` + `permanent` < 16 MB |

---

## Appendix A: LIR Instruction Set Reference

All instructions follow three‑address form where applicable. Types are explicitly carried to ensure C89 emitter correctness.

| Category | Instruction | Semantics |
|---|---|---|
| **Declarations** | `decl_temp(temp, type)` | Reserve stack storage for temporary |
| | `decl_local(name_id, type, temp)` | Bind named local to temp |
| **Assignments** | `assign(dst, src)` | `dst = src` |
| | `assign_field(base, field_id, src)` | `base.field = src` |
| | `assign_index(base, index, src)` | `base[index] = src` |
| **Control Flow** | `jump(bb)` | Unconditional jump |
| | `branch(cond, then_bb, else_bb)` | Conditional branch |
| | `switch_br(cond, cases, else_bb)` | Multi‑way branch |
| | `loop_header` | Marks loop entry (for continue target) |
| | `ret(value)` | Return value |
| | `ret_void` | Return from void function |
| **Arithmetic/Logic** | `binary(op, lhs, rhs, result)` | `result = lhs op rhs` |
| | `unary(op, operand, result)` | `result = op operand` |
| **Memory** | `load_field(base, field_id, result)` | Read struct/union field |
| | `store_field(base, field_id, value)` | Write struct/union field |
| | `load_index(base, index, result)` | Read array/slice element |
| | `load(ptr, result)` | Dereference pointer |
| | `store(ptr, value)` | Write through pointer |
| | `addr_of(operand, result)` | Take address |
| **Coercions** | `wrap_optional(value, result, type)` | Construct `?T` from `T` |
| | `unwrap_optional(value, result)` | Extract payload from `?T` |
| | `check_optional(value, result)` | `result = value.has_value` |
| | `wrap_error_ok(value, result, type)` | Construct `!T` success |
| | `wrap_error_err(err, result, type)` | Construct `!T` error |
| | `unwrap_error_payload(value, result)` | Extract payload from `!T` |
| | `unwrap_error_code(value, result)` | Extract error code from `!T` |
| | `check_error(value, result)` | `result = value.is_error` |
| | `make_slice(ptr, len, result, type)` | Construct `[]T` |
| | `int_cast(value, target, result, checked)` | Integer conversion |
| | `float_cast(value, target, result)` | Float conversion |
| | `ptr_cast(value, target, result)` | Pointer cast |
| | `int_to_float(value, target, result)` | Integer to float |
| | `ptr_to_int(value, result)` | Pointer to integer |
| | `int_to_ptr(value, target, result)` | Integer to pointer |
| **Literals** | `int_const(value, result)` | Integer constant |
| | `float_const(pool_idx, result)` | Float constant |
| | `string_const(pool_idx, result)` | String literal |
| | `null_const(result)` | `null` |
| | `bool_const(val, result)` | `true`/`false` |
| | `undefined_const(result, type)` | `undefined` |
| **Intrinsics** | `print_str(pool_idx)` | Emit `__bootstrap_print(str)` |
| | `print_val(value, type, fmt)` | Emit `__bootstrap_print_*(value)` |
| **No‑op** | `nop` | Placeholder |

---

## Appendix B: Lowering Edge Cases & Resolutions

| Scenario | Resolution |
|---|---|
| `switch` prong with payload capture + block body | Extract payload into named local, lower block, jump to exit |
| `try` inside `while` loop | `check_error` → branch to propagate block (expand errdefers) or continue |
| `orelse` on optional | `check_optional` → branch to fallback or unwrap |
| Anonymous tagged union init (`.{ .Tag = val }`) | Lowered as `assign_field(union, .tag, tag_const)` + `assign_field(union, .payload_Tag, val)` |
| `break`/`continue` with label | `loop_stack` stores label → temp mapping; jump uses labeled block ID |
| Void‑typed expressions (`@sizeOf`, `std.debug.print`) | Return `TYPE_VOID` temp; hoister filters it out; no storage allocated |
| Empty tuple `.{ }` | Emit `undefined_const` of size 1 (C89 dummy byte) |
| Extern function call with `null` argument | Emit `((T*)0)` cast to expected pointer type |
| `defer` inside `defer` | Nested defers are pushed in order; unwinding correctly handles nested scopes |

---

## Appendix C: Example Lowering Walkthrough (eval.zig TCO Case)

Consider the TCO pattern from `eval.zig`:

```zig
fn eval(expr: *Value, env: *Env, sand: *Sand) !*Value {
    defer sand.discard();           // depth 0
    var curr = expr;
    while (true) {                  // depth 1
        switch (curr.*) {
            .Apply => |data| {
                curr = data.fn_ptr(data.args, env, sand);
                continue;           // jumps to while header
            },
            else => return curr,
        }
    }
}
```

**Lowering Steps:**

1. **Function entry**: push `defer { sand.discard(); }` with `scope_depth=0`.
2. **While loop**: record `LoopInfo { header_bb=bb_cond, exit_bb=bb_exit, scope_depth=1 }`.
3. **Switch**: emit `switch_br` on `curr.*.tag`.
4. **Case `.Apply`**:
   - Extract payload, bind `data`.
   - Lower `curr = data.fn_ptr(...)`.
   - On `continue`:
     - Expand defers down to `scope_depth=1` (none).
     - Emit `jump bb_cond`.
5. **Case `else`**:
   - On `return`:
     - Expand defers down to `scope_depth=0` → emit `sand.discard()`.
     - Emit `ret(curr)`.

This ensures the outer `defer` is **not** called on each `continue`, preserving TCO semantics.
