# LIR Lowering Layer [updated: 2026-08-13 — Defect C FIXED (task F4, operator ruling m0872 — Option a): `lowerLValueAddr` (lower.zig:739) now has a `field_access` branch — computes the address of the field within the base's address (pointer base → `&base->f_N`; struct/union value base → recursive `&base` then `&addr->f_N`), emitting a new LIR inst `addr_of_field` (lir.zig:44) via the `addr_of`-adjacent C emitter form (c89_emit.zig, `result = &base->field;`). `lowerFieldStore` (lower.zig:844) routes nested field_access/deref/paren bases through it (`base_temp = lowerLValueAddr(child_0, ptr_type)`; ptr-typed bases keep `lowerExpr`) so the outer `store_field` stores through the pointer (proven ptr-base emitter c89_emit.zig:4183-4202 emits `ptr->field = v;`). Fixes BOTH: nested field-store write-back drop (repros `nested_field_store_xmod`→`4243`, `nested_field_store_xmod2`→`78`) and `&o.inner` ICE error[3043] (throwaway `&field` tests pass, incl. 3-level chains, union members, cross-module). Single-level stores unchanged; index-access bases unchanged; lisp_interpreter `v.data.Cons.car = car` now writes through `&v->data` / `&->Cons` and no longer SEGFAULTS at run; 4 MD5 gates byte-identical; corpus OK=237 FAIL=3 ICE=0 CRASH=0 GREEN=4 (no new FAIL).; prior 2026-08-13 — Defect-C investigation (task I2): documented the lvalue/address path gap — `lowerLValueAddr` (lower.zig:739) has NO `field_access` branch; 2+ level field-access lvalues (`o.inner.a = v`) lower the inner base as an rvalue COPY (`lowerFieldStore` lower.zig:860 → `lowerExpr`) and drop the write-back, and `&o.inner` ICEs error[3043]. Fix recommendation + blast radius in §Plain Assignment / §Field Store / §Address-Of; 0 of 4 MD5 gates affected; corrected stale lowerLValueAddr/lowerAssignLValue refs (655→739, 709→793).; prior 2026-08-13 — F2 module-scope coercion recording: new pub sema fn `semanticAnalyzerResolveModuleVarDecl` records the init coercion (wrap_optional_null for module-scope `var g: ?T = null`) → `set_optional_null` instead of `int` null_const (Defect B FIXED; side effect `int_literal_coerce` on `g_used: usize = 0` → gol/lisp/json MD5 gates re-baselined m0809); prior 2026-08-13 — F6 networking builtins: 11 `builtin_socket_*` LIR variants (lir.zig:89-99) + lowering (lower.zig:2880-2977) + 07 §Builtin calls / F6 paragraph; prior 2026-08-08 — F4 std-lib migration COMPLETE: all 6 example-facing `__bootstrap_*` I/O wrappers removed from zig_runtime.c/.h; the 19 `@intCast` cast helpers repointed `__bootstrap_panic(...)` → `std_panic(msg)` (m0564); 21 z98 examples migrated to `std.io` (see §Bootstrap-to-Builtin Mapping below); prior 2026-08-08 — 4 console builtins lowered to `builtin_console_clear`/`builtin_console_gotoxy`/`builtin_console_set_color` LIR (63→66 variants) + comptime branch folding for `if`/`if-expr` on comptime-known conditions (`@isWindows`); prior 2026-08-08 — 6 core I/O builtins lowered to `builtin_put_char`/`builtin_stdout_write`/`builtin_stderr_write`/`builtin_get_char`/`builtin_exit`/`builtin_sleep_ms` LIR (57→63 variants); prior I-RT bootstrap inventory: `__bootstrap_*` → builtin mapping + surviving zig_runtime.c function list (see §Bootstrap-to-Builtin Mapping below); prior 2026-08-07 null_src null construction skips the dead `null_const` temp (Option B); prior null-payload temp typed `null_type`→`int` (correct for `?*T`, wrong for `?[]T`); prior labeled_stmt unwrap + current_label propagation to loop_stack; prior varargs `va_start`/`va_arg`/`va_end` LIR + `@intCast` is_checked; prior F4/F5 comptime_values guards + INT_LIT→I32 remap; stale lower.zig line refs corrected post-F2 +30 insert (lowerStmt :3592, lowerFn :4788, applyCoercion :4469, expandDefers :4392, pushDefer :4384, hoistTemps :4420, applyNoneCoercion :4456, set_optional_null var-decl :4214); F7 line-ref pass: core I/O builtin dispatch :2777-2814 → :2821-2858, console :2816-2837 → :2860-2878 (socket arms shifted the block)]

## Summary

The lowering phase transforms the typed AST (AstStore) into a low-level intermediate representation (LIR) suitable for direct code generation. It handles control flow flattening, temporary hoisting, defer/errdefer expansion, and type coercion application.

Two key files:
- `sf/src/lir.zig` — LIR data types (LirInst, LirFunction, BasicBlock, etc.)
- `sf/src/lower.zig` — LirLowerer struct that walks the AST and emits LIR

## Data Flow

```
AstStore (fn_decl) → lowerFn() → LirFunction → appended to function list → codegen
```

`lowererInit()` creates a `LirLowerer` with empty stacks. `lowerFn()` is called per function, producing one `LirFunction` per call. The result list is managed externally.

---

## lir.zig — LIR Data Types `sf/src/lir.zig`

### Core Types

| Type | Fields | Purpose |
|------|--------|---------|
| `SwitchCase` | `value: u64`, `target_bb: u32` | Case value mapping to target basic block |
| `LirParam` | `name_id: u32`, `type_id: TypeId`, `temp_id: u32` | Function parameter declaration |
| `TempDecl` | `temp_id: u32`, `type_id: TypeId` | Hoisted temporary declaration |
| `BasicBlock` | `id: u32`, `insts: LirInstArrayList`, `is_terminated: u8` | Basic block with instruction list |
| `LirFunction` | `name_id`, `module_id`, `return_type`, `params`, `blocks`, `hoisted_temps`, `switch_cases`, `temp_variant_sub_field`, `is_extern`, `is_pub`, `is_variadic` | Compiled function unit |

### LirFunction Fields `sf/src/lir.zig:326`

| Field | Type | Description |
|-------|------|-------------|
| `name_id` | `u32` | Interned function name |
| `module_id` | `u32` | Defining module |
| `return_type` | `TypeId` | Resolved return type |
| `params` | `LirParamArrayList` | Parameter list |
| `blocks` | `BasicBlockArrayList` | All basic blocks (entry at index 0) |
| `hoisted_temps` | `TempDeclArrayList` | All temps hoisted to function entry |
| `switch_cases` | `SwitchCaseArrayList` | Switch case value→block map |
| `temp_variant_sub_field` | `U32ToU32Map` | Maps temps to variant sub-field indices |
| `is_extern` | `u8` | External linkage flag |
| `is_pub` | `u8` | Public visibility flag |
| `is_variadic` | `u8` | Variadic parameter flag |

### All 66 LirInst Variants `sf/src/lir.zig:22`

#### Declarations
| Variant | Fields | Purpose |
|---------|--------|---------|
| `decl_temp` | `temp, type_id` | Hoisted temp declaration at function entry |
| `decl_local` | `name_id, type_id, temp` | Scoped local variable declaration |

#### Data Movement
| Variant | Fields | Purpose |
|---------|--------|---------|
| `assign` | `dst, src, name_id` | Copy src to dst temp |
| `assign_field` | `base, field_id, src, name_id` | Write struct/union/slice field |
| `assign_index` | `base, index, src, name_id` | Write array element |
| `load` | `ptr, result` | Load value through pointer (deref) |
| `store` | `ptr, value` | Store value through pointer |
| `addr_of` | `operand, result` | Take address of local |
| `load_field` | `base, field_id, result, name_id` | Read struct/union/slice field |
| `store_field` | `base, field_id, value, name_id` | Write struct/union/slice field |
| `load_index` | `base, index, result, name_id` | Read array element |
| `load_local` | `name_id, result` | Load named local variable |
| `store_local` | `name_id, value` | Write named local variable |
| `load_global` | `name_id, result` | Load named global |
| `store_global` | `name_id, value` | Write named global |

#### Control Flow
| Variant | Fields | Purpose |
|---------|--------|---------|
| `jump` | `u32` (target block) | Unconditional branch |
| `branch` | `cond, then_bb, else_bb` | Conditional branch on bool/optional |
| `switch_br` | `cond, cases_start, cases_count, else_bb` | Multi-way branch (lookup in func.switch_cases) |
| `loop_header` | `u32` (label/block ID) | Loop entry marker |
| `ret` | `u32` (value) | Return with value |
| `ret_void` | `void` | Return without value |
| `label` | `u32` | Label marker for jumping |

#### Arithmetic & Logic
| Variant | Fields | Purpose |
|---------|--------|---------|
| `binary` | `op, lhs, rhs, result` | Binary arithmetic (add/sub/mul/div/mod/and/or/xor/shl/shr/eq/ne/lt/le/gt/ge) |
| `unary` | `op, operand, result` | Unary arithmetic (neg/not/bnot) |

#### Constants
| Variant | Fields | Purpose |
|---------|--------|---------|
| `int_const` | `value, result` | Integer literal |
| `float_const` | `value, result` | Float literal |
| `string_const` | `string_id, result` | String literal pointer |
| `bool_const` | `value, result` | Boolean literal |
| `null_const` | `result` | Null literal — result temp is typed `null_type` (lower.zig:1184), whose C name is `"int"` (`getCTypeName`, c89_emit.zig:605). **Option B [updated: 2026-08-07]:** when a null literal feeds a `?T` coercion (null_src), the null_literal branch (lower.zig:1183) now emits `set_optional_null` directly on an `Opt_`-typed temp instead of `null_const` — no dead `int zT_N; zT_N = NULL;` store. `null_const` remains only for uncoerced null / non-optional (pointer/fn) targets. See the `materializeInto` null-construction note below. |
| `set_optional_null` | `result, type_id` | Set optional to null (typed null) — emitted by the null_literal branch (lower.zig:1183, Option B) for null_src coercions, by `materializeInto` (lower.zig:977-978) for other null_src paths, and directly by the var-decl path (lower.zig:4214) and `applyNoneCoercion` (lower.zig:4456) for `var x: ?T = null`. Only `.has_value = 0;` is set; the payload field is left untouched. |
| `undefined_const` | `result, type_id` | Undefined literal |
| `enum_const` | `value, result, type_id, member_name_id` | Enum literal with member name |

#### Function Calls
| Variant | Fields | Purpose |
|---------|--------|---------|
| `call` | `callee, args_start, args_count, result` | Indirect function call |
| `call_direct` | `name_id, module_id, args_start, args_count, result, return_type, is_extern` | Direct named function call |
| `func_ref` | `name_id, module_id, result` | Function pointer reference |

#### Variadic (va_*) — `sf/src/lir.zig:46-48` [added: 2026-08-06]
| Variant | Fields | Purpose |
|---------|--------|---------|
| `va_start` | `va_list_temp, last_param_temp` | `va_start(vl, last_param)` — init a `va_list` after the last named param |
| `va_arg` | `va_list_temp, type_id, result` | `result = va_arg(vl, TYPE)` — read the next variadic argument |
| `va_end` | `va_list_temp` | `va_end(vl)` — cleanup |

These are emitted by the `@cVaStart`/`@cVaArg`/`@cVaEnd` builtin handler
(`lower.zig:2721-2772`, dispatched before the `ec.len>=2` cast block); the
`va_list_temp` operand is resolved via `vaListArgTemp` (`lower.zig:1002`, unwraps
`&ident`/`ident` to a local temp). `@cVaStart` in a non-variadic function emits
`error[3012]` (`ERR_3012_VARARGS_INVALID`); the same error is emitted for a
variadic fn with ZERO fixed params (`fn f(...)`, `lower.zig:4726-4730`).
`LirFunction.is_variadic` (`lir.zig:341`) is set by `lowerFn` from
`FnPayload.flags_packed` bit0 (`lower.zig:4715-4725`); the legacy `child_0==0`
anytype-marker branch was **deactivated in F5b (AMENDMENT 5)** — `is_variadic`
now comes solely from the flag-bit path (mud/gol `print(fmt, ...)` signatures
are unchanged because they migrated to true `...`).

#### Builtin I/O — `sf/src/lir.zig:80-85` [added: 2026-08-08]
| Variant | Fields | Purpose |
|---------|--------|---------|
| `builtin_put_char` | `value` | Emit `putchar(value)` to stdout (libc stdio) |
| `builtin_stdout_write` | `ptr, len` | Emit `fwrite(ptr, 1, len, stdout)` |
| `builtin_stderr_write` | `ptr, len` | Emit `fwrite(ptr, 1, len, stderr)` |
| `builtin_get_char` | `result` | `result = getchar()` (result temp typed `TYPE_U8`) |
| `builtin_exit` | `value` | Emit `exit(value)`; sets `block_terminated = 1` (noreturn) |
| `builtin_sleep_ms` | `value` | Emit `#ifdef _WIN32` `Sleep(value)` `#else` `usleep(value * 1000)` `#endif` |

Emitted by the core-I/O builtin handler (`lower.zig:2777-2814`, dispatched before
the `ec.len>=2` cast block, mirroring the `va_*` handlers). Each value arg is
lowered via `lowerExpr`; `@exit` marks the current block terminated so the
function's trailing `emitValuelessReturn` (lower.zig:4906) is skipped. See §Builtin
I/O lowering below.

#### Builtin Console — `sf/src/lir.zig:86-88` [added: 2026-08-08]
| Variant | Fields | Purpose |
|---------|--------|---------|
| `builtin_console_clear` | — | Emit console clear (Win32 `FillConsoleOutput*`+home / ANSI `\x1b[2J\x1b[H`) |
| `builtin_console_gotoxy` | `x, y` | Emit cursor move (Win32 `SetConsoleCursorPosition(COORD)` / ANSI `\x1b[%d;%dH` (y+1, x+1)) |
| `builtin_console_set_color` | `fg, bg` | Emit color set (Win32 `SetConsoleTextAttribute` / ANSI `\x1b[%s;%sm` fg/bg tables) |

Emitted by the console builtin handler (`lower.zig:2816-2837`). Each arg is lowered
via `lowerExpr`. Emission is `#ifdef _WIN32 / #elif defined(__WATCOMC__) / #else`
guarded (see 08 §Builtin console emission). `@isWindows()` never produces LIR — it
folds in sema/comptime (see §Comptime branch folding below).

#### Optional Handling
| Variant | Fields | Purpose |
|---------|--------|---------|
| `wrap_optional` | `value, result, type_id` | Wrap value in optional type |
| `unwrap_optional` | `value, result` | Extract payload from optional |
| `unwrap_optional_abi` | `value, result` | Extract payload from optional (ABI-stable) |
| `check_optional` | `value, result` | Test if optional has value |

#### Error Union Handling
| Variant | Fields | Purpose |
|---------|--------|---------|
| `wrap_error_ok` | `value, result, type_id` | Wrap success value in error union |
| `wrap_error_err` | `value, result, type_id` | Wrap error code in error union |
| `unwrap_error_payload` | `value, result` | Extract success payload from error union |
| `unwrap_error_code` | `value, result` | Extract error code from error union |
| `check_error` | `value, result` | Test if error union has error |

#### Slice Operations
| Variant | Fields | Purpose |
|---------|--------|---------|
| `make_slice` | `ptr, len, result, type_id` | Construct slice from pointer and length |

#### Type Conversions
| Variant | Fields | Purpose |
|---------|--------|---------|
| `int_cast` | `value, target, result, is_checked` | Integer type conversion (widening/narrowing) |
| `float_cast` | `value, target, result` | Float type conversion |
| `ptr_cast` | `value, target, result` | Pointer type conversion |
| `int_to_float` | `value, target, result` | Integer to float conversion |
| `ptr_to_int` | `value, result` | Pointer to integer |
| `int_to_ptr` | `value, target, result` | Integer to pointer |

#### Debug/Print
| Variant | Fields | Purpose |
|---------|--------|---------|
| `print_str` | `string_id` | Print string literal |
| `print_val` | `value, type_id, fmt` | Print typed value with format |

#### Other
| Variant | Fields | Purpose |
|---------|--------|---------|
| `nop` | `void` | No operation (placeholder) |

---

## lower.zig — LIR Lowerer `sf/src/lower.zig`

### LirLowerer Struct `sf/src/lower.zig:218`

| Field | Type | Description |
|-------|------|-------------|
| `ctx` | `*SemanticContext` | Shared compilation context (store, type registry, symbols, diagnostics) |
| `func` | `*LirFunction` | Currently constructing LirFunction |
| `current_bb` | `u32` | Active basic block index |
| `temp_counter` | `u32` | Next temporary ID to allocate |
| `defer_stack` | `DeferActionArrayList` | Stack of deferred action descriptors |
| `loop_stack` | `LoopInfoArrayList` | Stack of enclosing loop descriptors |
| `switch_stack` | `SwitchInfoArrayList` | Stack of enclosing switch descriptors |
| `hoisted_temps` | `TempDeclArrayList` | Accumulated temporary declarations for function entry |
| `alloc` | `*Sand` | Allocator for dynamic data structures |
| `scope_depth` | `u32` | Current lexical scope depth |
| `block_terminated` | `u8` | Whether current block has a terminating instruction |
| `module_id` | `u32` | Current module ID |
| `module_reg` | `*ModuleRegistry` | Module registry reference |
| `intcast_name_id` | `u32` | Interned "@intCast" |
| `inttofloat_name_id` | `u32` | Interned "@intToFloat" |
| `print_fn_id` | `u32` | Interned "print" |
| `ptrcast_name_id` | `u32` | Interned "@ptrCast" |
| `ptrtoint_name_id` | `u32` | Interned "@ptrToInt" |
| `inttoptr_name_id` | `u32` | Interned "@intToPtr" |
| `enumtoint_name_id` | `u32` | Interned "@enumToInt" |
| `size_of_name_id` | `u32` | Interned "@sizeOf" |
| `align_of_name_id` | `u32` | Interned "@alignOf" |
| `local_decl_names/temps/types/kinds/scopes` | `[64]u32/u8` | Fixed-slot array of local declarations (max 64) |
| `local_decl_name_map` | `U32ToU32Map` | Maps temp ID → name_id for debug info |
| `local_decl_count` | `usize` | Number of tracked local declarations |
| `_fn_ret_type` | `u32` | Cached function return type |
| `_ctx_node_idx` | `u32` | Context node index (for diagnostics) |
| `_ctx_node_kind` | `u32` | Context node kind (for diagnostics) |
| `capture_shadow` | `U32ToU32Map` | Maps captured names to disambiguated synthetic names |
| `synth_name_counter` | `u32` | Counter for synthetic name generation |
| `current_label` | `u32` | **[F1, 2026-08-07] Currently active label name ID** (0=unlabeled). Set from a `labeled_stmt` node's payload around its `child_0` recursion (lower.zig:257, init 0 at lower.zig:324); read by all 3 loop-push sites to stamp `LoopInfo.label_id`. |

### Supporting Types

| Type | Fields | Purpose |
|------|--------|---------|
| `DeferAction` | `kind, ast_node, scope_depth` | Descriptor for deferred statement execution (`kind`: 0=defer, 1=errdefer) |
| `LoopInfo` | `header_bb, exit_bb, scope_depth, label_id` | Loop context for break/continue resolution. `label_id` is the active label name ID from `current_label` at push time (0=unlabeled). |
| `SwitchInfo` | `exit_bb, scope_depth` | Switch context |
| `SrcIntent` | enum `value`, `null_src`, `error_src` | Classifies source expression for coercion. `null_src` (from a `null_literal` or `wrap_optional_null` coercion) makes the null_literal branch emit `set_optional_null` directly on an `Opt_`-typed temp (Option B, 2026-08-07); `materializeInto` then short-circuits or wraps outer EU layers. No dead `null_const` temp [updated: 2026-08-07] |

### Key Functions

| Function | Signature | Description |
|----------|-----------|-------------|
| `lowererInit` | `(ctx, alloc) → LirLowerer` `sf/src/lower.zig:271` | Creates LirLowerer with empty stacks, pre-caches builtin name IDs (incl. the 10 I/O + console builtins, F1/F2) |
| `emitInst` | `(self, LirInst)` `sf/src/lower.zig:336` | Appends instruction into current basic block |
| `nextTemp` | `(self, type_id) → u32` `sf/src/lower.zig:340` | Allocates temp ID, records in hoisted_temps |
| `createBlock` | `(self) → u32` `sf/src/lower.zig:379` | Creates new BasicBlock, appends to func.blocks |
| `lowerExpr` | `(self, node_idx) → u32` `sf/src/lower.zig:461` | Lower AST expression to LIR temp; applies coercion wrapper |
| `lowerExprImpl` | `(self, node_idx) → u32` `sf/src/lower.zig:1122` | Core expression lowering dispatch |
| `lowerStmt` | `(self, node_idx)` `sf/src/lower.zig:3592` | Lower AST statement to LIR |
| `lowerFn` | `(self, fn_node) → LirFunction` `sf/src/lower.zig:4788` | Lower entire function to LIR |
| `applyCoercion` | `(self, src_temp, coercion) → u32` `sf/src/lower.zig:4469` | Apply type coercion (widen, wrap, cast) |
| `expandDefers` | `(self, target_depth, is_error_path)` `sf/src/lower.zig:4392` | Emit deferred statements at scope exit |
| `pushDefer` | `(self, kind, ast_node)` `sf/src/lower.zig:4384` | Push a defer/errdefer action onto stack |
| `hoistTemps` | `(self)` `sf/src/lower.zig:4420` | Prepend decl_temp instrs to entry block |
| `materializeInto` | `(self, src_temp, expected, intent) → u32` `sf/src/lower.zig:906` | Layer type wrappers (optional/error-union) to match expected type |
| `addLocalDecl` | `(self, name_id, type_id, temp, depth)` `sf/src/lower.zig:485` | Register a local variable |
| `findLocalTemp` | `(self, name_id) → ?u32` `sf/src/lower.zig:994` | Look up local temp by name |
| `lowerLValueAddr` | `(self, lv_node_idx, result_type) → u32` `sf/src/lower.zig:739` | Compute address of l-value. Handles `index_access`, `ident_expr`, `deref`, `paren_expr`, and — **FIXED (F4, 2026-08-13)** — `field_access` (address of field within base's address; emits `addr_of_field` LIR). See §Address-Of / §Field Store. |
| `lowerAssignLValue` | `(self, lv_node_idx, value_temp, diag_node_idx)` `sf/src/lower.zig:793` | Emit store to l-value target |

---

## AST → LIR Lowering Patterns

### Literals

| AstKind | LIR Output | Description |
|---------|-----------|-------------|
| `int_literal` | `int_const` → temp(TYPE_INT_LIT) | Integer constant value |
| `float_literal` | `float_const` → temp(TYPE_F64) | Float constant |
| `string_literal` | `string_const` → temp(ptr) | String pointer constant |
| `char_literal` | `int_const` → temp(TYPE_U8) | Character as u8 |
| `bool_literal` | `bool_const` → temp(TYPE_BOOL) | Boolean 0/1 |
| `null_literal` | `null_const` → temp(TYPE_NULL) | Untyped null. **FIXED [2026-08-07, Option B]:** when the node's coercion routes to `SrcIntent.null_src` (`wrap_optional_null`/`wrap_optional`/`wrap_error_success`) AND the coercion target chain contains an optional layer, the null_literal branch (lower.zig:1183) instead emits `set_optional_null` directly on a temp typed as the optional layer — the dead `int zT_N; zT_N = NULL;` (gcc `-Wint-conversion`) is eliminated. The generic `null_const` path remains for uncoerced null / non-optional targets (pointer/fn). |
| `undefined_literal` | `undefined_const` → temp(TYPE_UNDEFINED) | Undefined value |
| `enum_literal` | `enum_const` or `int_const` or tagged-union init | Enum member; for TU emits `int_const` tag + `assign_field` tag |
| `error_literal` | `int_const` → temp(TYPE_I32) | Error value as integer |

### Arithmetic & Logic

All binary operations follow the same pattern (with a comptime fold guard first):
```
if comptime_values[node_idx] → nextTemp(ftype); emitInst(.int_const{ cv }); return ctid   ← F4/F5 guard
lowerExpr(lhs) → tid_lhs
lowerExpr(rhs) → tid_rhs
nextTemp(resolved_type) → tid_result
emitInst(.binary{ op, tid_lhs, tid_rhs, tid_result })
return tid_result
```

**[updated: 2026-08-06] Comptime fold guards (F4/F5, commits `ec71f9ad`/`5ed90251`):** the 10
binary op handlers (add/sub/mul/div/mod_op/bit_and/bit_or/bit_xor/shl/shr, lower.zig:1218-1306)
and the 2 unary handlers (`negate`/`bit_not`, lower.zig:1426-1439) now consult
`ctx.comptime_values` **before** lowering operands — mirroring the `builtin_call` handler
(lower.zig:2456). When a folded value is present, the temp type is taken from
`resolvedTypeTableGet(node_idx)` with an **INT_LIT→I32 remap** (`ft = TYPE_I32` when the resolved
type is `TYPE_INT_LIT` or `TYPE_UNDEFINED`), and an `int_const` LIR inst is emitted instead of a
`binary`/`unary` inst. The remap keeps bare const inits (which resolve TYPE_INT_LIT) typed `int`
in C; annotated consts (e.g. `const X: u64 = …`, threaded by the F7 sema fix) keep their declared
width so u64 folds >2^32 are not masked to 32 bits. `bool_not` has no guard (never folds).

| AstKind | LIR Op |
|---------|--------|
| `add` | `BIN_ADD` |
| `sub` | `BIN_SUB` |
| `mul` | `BIN_MUL` |
| `div` | `BIN_DIV` |
| `mod_op` | `BIN_MOD` |
| `bit_and` | `BIN_AND` |
| `bit_or` | `BIN_OR` |
| `bit_xor` | `BIN_XOR` |
| `shl` | `BIN_SHL` |
| `shr` | `BIN_SHR` |
| `cmp_eq` | `BIN_EQ` (or `check_optional`+`unary.not` for `== null`) |
| `cmp_ne` | `BIN_NE` (or `check_optional` for `!= null`) |
| `cmp_lt` | `BIN_LT` |
| `cmp_le` | `BIN_LE` |
| `cmp_gt` | `BIN_GT` |
| `cmp_ge` | `BIN_GE` |

**Short-circuit `bool_or`** (`sf/src/lower.zig:1322`): Produces 3 blocks (rhs_bb, true_bb, done_bb). If lhs is true → true_bb emits `bool_const(1)` → done_bb. If lhs is false → rhs_bb evaluates rhs → assign result → done_bb.

**Short-circuit `bool_and`** (`sf/src/lower.zig:1345`): Produces 3 blocks (rhs_bb, false_bb, done_bb). If lhs is true → rhs_bb evaluates rhs → assign. If lhs is false → false_bb emits `bool_const(0)` → done_bb.

### Unary Operations

| AstKind | Pattern |
|---------|---------|
| `negate` | `.unary{ UN_NEG }` — **F5 guard**: folds to `int_const` when `comptime_values[node_idx]` present |
| `bool_not` | `.unary{ UN_NOT }` |
| `bit_not` | `.unary{ UN_BNOT }` — **F5 guard**: folds to `int_const` when `comptime_values[node_idx]` present |

### Variables

| AstKind | Pattern |
|---------|---------|
| `ident_expr` | Lookup via `findLocalTemp()` or symbol table → `load_local` or `load_global`. For fn types, `func_ref`. For modules, diagnostic warning. For type aliases, emits temp. `sf/src/lower.zig:1489` |
| `var_decl` | `nextTemp(decl_type)` → `decl_local` → optionally `store_local` + `assign` from init expression. Arrays init'd via `array_init` lowering. `sf/src/lower.zig:3687` |

### Compound Assignments

All `*_assign` variants follow this pattern (`sf/src/lower.zig:3038-3147`):
```
lowerExpr(lhs) → lhs_val
lowerExpr(rhs) → rhs_val
nextTemp(result_type) → op_r
emitInst(.binary{ op, lhs_val, rhs_val, op_r })
lowerCompoundLValueStore(self, node_idx, lhs_val, op_r)
```

This covers: `add_assign`, `sub_assign`, `mul_assign`, `div_assign`, `mod_assign`, `shl_assign`, `shr_assign`, `and_assign`, `xor_assign`, `or_assign`.

### Plain Assignment `sf/src/lower.zig:1389`
```
lowerExpr(rhs) → src
lowerAssignLValue(lhs, src)
```
`lowerAssignLValue` handles: `ident_expr`→`store_local`+`assign`, `index_access`→`assign_index`, `field_access`→`lowerFieldStore`, `deref`→`store`, `paren_expr`→recurse.

**Defect-C — FIXED (2026-08-13, task F4, operator ruling m0872 — Option a).** Previously: for a
2+ level field-access lvalue (`o.inner.a = v`), `field_access` dispatch reached `lowerFieldStore`
(lower.zig:844). For a NON-index base (child_0 is itself `field_access`), lowerFieldStore lowered
the base with `base_temp = lowerExpr(fa_node.child_0)` (lower.zig:860) — an **rvalue COPY**
(inner `field_access` → `.load_field` into a fresh temp). The outer `store_field`
(lower.zig:884) then mutated that throwaway local; the write-back to `o` was DROPPED (emitted C
`zT_5 = o.inner; zT_5.a = v;`, repros `nested_field_store_xmod`/`_xmod2` printed garbage).
**Now:** `lowerFieldStore`'s nested-base case routes field_access/deref/paren bases through
`lowerLValueAddr(child_0, ptr_type)` (pointer-typed bases keep `lowerExpr`), producing a pointer
to the inner field; the outer `store_field` stores through it (emitted C
`zT_5 = &o; zT_6 = &zT_5->inner; zT_6->a = v;`). Repro `nested_field_store_xmod` prints `4243`,
`nested_field_store_xmod2` prints `78`. Single-level stores unaffected (ident base stays on the
`lowerExpr` path, which returns the local's own temp, lower.zig:2000). See §Field Store /
§Address-Of.

### Field Access `sf/src/lower.zig:1740`

Two modes:
1. **Compile-time resolved**: `TypeAlias.field` → `emitTaggedUnionInit` (for TU) or `enum_const` (for enum) or error set member
2. **Runtime**: `lowerExpr(base)` → resolve base type → if struct/union/TU → `.load_field{ field_id }`. Slice `.len` → `SLICE_FIELD_LEN`, slice `.ptr` → `SLICE_FIELD_PTR`.

### Field Store `sf/src/lower.zig:844` (`lowerFieldStore`)

Dispatched from `lowerAssignLValue` for `field_access` lvalues. Base handling:
- **Index base** (`arr[i].field = v`, lower.zig:850-858): computes a POINTER base
  (`ptr_temp + idx_temp` via `BIN_ADD`, typed `*elem`) and emits `store_field{ base = ptr, field_id }`
  → C emitter (c89_emit.zig:4183-4202) emits `ptr->field = v;`. Correct.
- **Nested lvalue base** (`o.inner.a = v`; base is `field_access`/`deref`/`paren_expr`,
  lower.zig:859-873, **FIXED F4 2026-08-13**): routes through
  `base_temp = lowerLValueAddr(child_0, *BaseTy)` (or `lowerExpr` when the base is itself
  pointer-typed, keeping its existing pointer value) → `resolved_base = *BaseTy`, so the struct/
  union dispatch unwraps the pointer and `store_field` emits `ptr->field = v;`. Emitted C:
  `zT_5 = &o; zT_6 = &zT_5->inner; zT_6->a = v;`. Previously `base_temp = lowerExpr(child_0)`
  produced an rvalue COPY and dropped the write-back (**Defect C**).
- **Ident / pointer-var base** (`o.tag = 1`, `ptr.x = v`): unchanged — `base_temp = lowerExpr(child_0)`;
  for an aggregate local this is the local's own temp (correct), for a pointer var it is the
  pointer value (emitter emits `ptr->x`).

**Implementation (task F4, operator ruling m0872 — Option a):** extended `lowerLValueAddr`
(lower.zig:739) with a `field_access` branch — compute the address of the field within the base's
address: if the base's resolved type is a pointer, `base_addr = lowerExpr(base)` (the pointer
value); else `base_addr = lowerLValueAddr(base, *BaseTy)` (recursion handles nested chains and
ident/index/deref/paren cases); then emit a new `addr_of_field` LIR inst
(`{ base = base_addr, field_id, result }`, lir.zig:44) which the C emitter renders as
`result = &base->f_N;` (resolving the field name via the base temp's hoisted ptr-to-struct/union
type, mirroring the `store_field` ptr-base emitter c89_emit.zig:4183-4202). This completes the
universal lvalue→address primitive and is strictly more general than patching only the consumer:
it also un-ICEs `&o.inner` / `&v.data.Int` (see §Address-Of). Blast radius verified 2026-08-13:
repros `dup_val_field_emit`, `tu_field_store_ptr`, `tu_ptrcast_copy`,
`xmod_amp_arena_union_store`, `struct_field_store_subscript` now emit the `->` store form
(compile-only, same gate status); 0 of the 4 MD5 gates (mud/gol/lisp_curr/json) use nested
field-store, so no gate re-baselined (all 4 byte-identical). `examples/z98/lisp_interpreter`
`v.data.Cons.car = car` (value.zig:38-39) now emits `zT_9 = &v->data; zT_10 = &zT_9->Cons;
zT_10->car = car;` and the example no longer SEGFAULTS at run.

### Index Access `sf/src/lower.zig:1430`
```
lowerExpr(base) → base_temp
maybeExtractSlicePtr() → ptr_temp (extracts `.ptr` field from slice)
lowerExpr(index) → idx_temp
nextTemp(elem_type) → tid
emitInst(.load_index{ ptr_temp, idx_temp, tid })
```
Coercion context: `applyCoercion` after expression (`sf/src/lower.zig:476`).

### Dereference `sf/src/lower.zig:1416`
```
lowerExpr(ptr) → ptr_temp
nextTemp(pointee_type) → tid
emitInst(.load{ ptr_temp, tid })
```

### Address-Of `sf/src/lower.zig:1425`
```
lowerLValueAddr(lvalue) → tid
```
Dispatches by l-value kind: ident → `.addr_of`, index_access → ptr+idx via `BIN_ADD`, deref → reuses inner expr, paren → recurse, **field_access → `addr_of_field` (FIXED F4 2026-08-13)**.
**FIXED (task F4, 2026-08-13, operator ruling m0872 — Option a):** `&o.inner` (and any 2+ level
field-access address-of) previously fell through to `iceAddrOfLValueUnsupported` (lower.zig:777)
→ ICE `error[3043] "internal: unsupported address-of l-value"`. The new `field_access` branch
projects the field within the base's address: pointer-typed base → use the base's pointer value;
struct/union-value base → recurse `lowerLValueAddr(base, *BaseTy)`; then emit `addr_of_field`
(lir.zig:44) rendered as `result = &base->f_N;`. `&o.inner` now emits `zT_5 = &o;
zT_6 = &zT_5->inner;` (verified: throwaway tests for struct/union members, 3-level chains, and
cross-module `&o.inner` all compile and run). This same primitive also unblocks the nested store
via `lowerFieldStore` (see §Field Store).

### Array Init `sf/src/lower.zig:2664`
```
nextTemp(array_type) → base_temp
for each element:
  lowerExpr(element) → val_temp
  emitInst(.int_const{ ei }) → ix_temp
  emitInst(.assign_index{ base_temp, ix_temp, val_temp })
return base_temp
```

### Struct Init `sf/src/lower.zig:3283-3423`
```
nextTemp(struct_type) → base_temp
for each field init:
  lowerExpr(val) → val_temp
  find field index by name
  if TU: emit `.int_const(tag_index)` + `.assign_field(TU_FIELD_TAG, tag)` + optionally `.assign_field(TU_FIELD_PAYLOAD, val)`
  if struct: emit `.assign_field(field_index, val)`
  if union: emit `.assign_field(field_index, val)` (FIXED 2026-08-13, F1) — see note below
```

**FIXED — bare `union_type` struct-literal target (2026-08-13, F1):** the
field loop now has a `union_type` branch (lower.zig:3420-3432, after the
`struct_type` branch) scanning `un_items[payload_idx].fields_start/
fields_count`, finding the member by `name_id`, and emitting
`.assign_field(union_field_index, val)` — mirroring the `struct_type` branch
(including the `is_undef_arr_field` skip). Previously a bare-union struct
literal (`Inner{ .Int = v }`) never matched, so its member construction was
DROPPED and the outer struct-literal field assigned an unconstructed temp
(`zT_1.data = zT_3;` with `zT_3` never declared → gcc `'zT_3' undeclared`).
With sema's union branch (05 §semanticAnalyzerResolveStructInit),
`init_type` now resolves to the union type, so `base_temp` gets the union
type and the member assign emits. Emitted C: `zT_3.Int = v; zT_1.data = zT_3;`.
Reproduction: `repro/mi_matrix/union_literal_nested_xmod` prints `42`. Same
shape as `examples/z98/lisp_interpreter` `token.zig`. [updated: 2026-08-13]

[updated: 2026-08-07] **`undefined` array-typed fields are skipped (F2, commit ba89a6e0):** a
pre-scan (`lower.zig:3006-3038`) computes `is_undef_arr_field` — true iff the field init is
`undefined_literal` AND the matching field (by `name_id`) in the struct-init type has a declared
type of kind `array_type` (scans `struct_type` `st_items`/`fe_items` and `tagged_union_type`
`tu_items`/`fe_items`). When true, the field's `lowerExpr` is skipped (`lower.zig:3041`, no dead
`undefined_const` temp) and the `assign_field` is NOT emitted (`lower.zig:3082` TU payload branch,
`lower.zig:3097` struct branch; the TU tag assign is still emitted). Matches the zig0 oracle, which
emits nothing for `undefined` array fields. Fixes `undef_arr_struct_literal` (previously the
emitter's `emitFieldAssign` zero-fill hardcoded `base.fld[_j] = 0;` for the whole array regardless
of element type, emitting `int` assigns on struct elements → gcc `incompatible types`).

### Tuple Literal `sf/src/lower.zig:2793`
Single-element tuples forward to `lowerExpr(ec[0])`. Empty tuples return `TYPE_VOID`.

### Function Calls `sf/src/lower.zig:1954`

**Direct call** (callee resolves to fn symbol):
```
Reserve args_start temps
for each arg: lowerExpr(arg) → applyCoercion → .assign to args slot
nextTemp(return_type) → result
emitInst(.call_direct{ name_id, module_id, args_start, args_count, result, return_type, is_extern })
```

**Indirect call** (callee is pointer-to-fn):
```
lowerExpr(callee) → callee_temp
Reserve args
for each arg: lowerExpr → .assign
emitInst(.call{ callee_temp, args_start, args_count, result })
```

**Cross-module call** (field access on module): Resolves symbol, emits `call_direct` with target `module_id`.

[updated: 2026-08-07] **Cross-module `pub const` literal fold (F3, commit 317f3a82):** in the
cross-module `SymbolKind.global` module-field-access branch (`lower.zig:2005-2024`), when the
target's `ts.flags` bit0 is 0 (const) and its `decl_node.child_1` init is an `int_literal` /
`char_literal` / `float_literal`, the lowerer emits the folded `int_const` / `float_const` directly
at the ref site, typed at the DECLARED type (`gbl_tid` from `resolvedTypeTableGet(ts.decl_node)`,
`lower.zig:2007`) — mirroring the same-module literal fold (`lower.zig:1681-1704`). The
`load_global` fallback is kept for non-literal consts. Previously a cross-module `pub const` with a
literal init registered as `SymbolKind.global` but got NO F-7 storage slot (main.zig:623-630 skips
int/float/char-literal-init consts; bit0=mutable only), so the consumer's `load_global` referenced
an undeclared `zG_...` name (gcc `'zG_...' undeclared`). Fixes `xmod_pub_const_global`.

**print() builtin** (`sf/src/lower.zig:375`): Special-cased. Emits `print_str` for the format string, `print_val` per argument.

**Builtin calls** (`sf/src/lower.zig:2395`): `@ptrCast`, `@intCast`, `@intToFloat`, `@ptrToInt`, `@intToPtr` emit corresponding LIR instructions. `@sizeOf`/`@alignOf` resolved via comptime values table or ICE. `@enumToInt` forwards the value as-is. **Variadic builtins** (`lower.zig:2721-2772`): `@cVaStart`/`@cVaArg`/`@cVaEnd` emit the `va_start`/`va_arg`/`va_end` LIR (see the Variadic table above). **[updated: 2026-08-08] Core I/O builtins** (`lower.zig:2821-2858`, F1): `@putChar`/`@stdoutWrite`/`@stderrWrite`/`@getChar`/`@exit`/`@sleepMs` emit the 6 `builtin_*` LIR (see the Builtin I/O table above). `@exit` sets `block_terminated=1` (noreturn). **[updated: 2026-08-08] Console builtins** (`lower.zig:2860-2878`, F2): `@consoleClear`/`@consoleGotoxy`/`@consoleSetColor` emit the 3 `builtin_console_*` LIR (see the Builtin Console table above). `@isWindows()` folds via the comptime-values path (`lower.zig:2703-2724`, emits `int_const` typed `TYPE_BOOL`) and never produces a runtime LIR inst. **[updated: 2026-08-13] Socket builtins** (`lower.zig:2880-2977`, F6): `@socketCreate`/`@socketBindListen`/`@socketAccept`/`@socketConnect`/`@socketSend`/`@socketRecv`/`@socketSelect`/`@socketFdZero`/`@socketFdSet`/`@socketFdIsset`/`@socketClose` emit the 11 `builtin_socket_*` LIR (lir.zig:89-99, the F6 phase-2 variants).

**`@intCast` range-check (F1, 2026-08-06):** the explicit `@intCast` builtin handler
(`lower.zig:2686-2703`) now computes `is_checked` from the source/target widths
(`intCastTypeBits`) and signedness (`intCastTypeIsSigned`): `chk=1` when
`src_bits > dst_bits` (narrowing) OR `src_bits == dst_bits` with differing
signedness (same-width reinterpret); widening and same-signedness same-width are
left unchecked. The checked arm emits `int_cast{ is_checked=1 }`, which c89_emit
renders as the range-checked `__bootstrap_<DST>_from_<SRC>` helper call. Coercion
sites (`lower.zig:955`, `:4379`, `:4387`) keep `is_checked=0`.

### Bootstrap-to-Builtin Mapping — I-RT inventory [updated: 2026-08-08]

Per the std-lib migration plan (`.superpowers/plans/2026-07-31-std-lib-migration-plan.md`, I-RT
task), the example-facing `__bootstrap_*` I/O wrappers in `sf/src/include/zig_runtime.c` become
compiler builtins; the compiler-internal cast helpers and the `std_print*`/`std_panic` general
runtime STAY. Full inventory: `.superpowers/sdd/I-RT-report.md`.

**The lowerer's two print paths.** The Z98 `print()` builtin (`lower.zig:375`) lowers to
`print_str`/`print_val` LIR, which c89_emit renders as direct `std_print(...)` /
`std_print_<type>(...)` calls (`getPrintFnName`, c89_emit.zig:3015) — NOT the `__bootstrap_*`
wrappers. The `__bootstrap_print*` aliases are resolved only at LINK time for example-facing
`extern fn` declarations. So builtin migration removes the *example extern → zig_runtime.c alias*
path; the `print_str`/`print_val` → `std_print*` path is untouched.

| `__bootstrap_*` (zig_runtime.c:line) | Signature (C) | Consumers | Disposition |
|---|---|---|---|
| `__bootstrap_print` :67 | `void (const char* s)` | 20+ z98 examples (hello, quicksort, sort_strings, json_parser, mud/gol/lisp std_debug.zig, rogue_mud…) | → `std.io.print` (std_io.zig `@stdoutWrite` walk) — **REMOVED (F4)** |
| `__bootstrap_print_int` :68 | `void (int n)` | 15+ z98 examples (printInt wrappers, lisp `.Int`, rogue_mud HP/pos) | → `std.io.printInt` (std_io.zig itoa) — **REMOVED (F4)** |
| `__bootstrap_print_char` :69 | `void (int c)` | rogue_mud ui.zig:161 (unused decl) | → `std.io.writeByte` — **REMOVED (F4)** |
| `__bootstrap_panic` :70 | `void (const char*, const char*, int)` | cast helpers (this file + zig_runtime.h static copies) | **REMOVED (F4)** — cast helpers repointed to `std_panic(msg)` directly (operator ruling m0564) |
| `__bootstrap_write` :71 | `void (const char*, unsigned int)` | json_parser, rogue_mud `__bootstrap_print_bytes` | → `std.io.write` — **REMOVED (F4)** |
| `__bootstrap_sleep_ms` :72 | `void (unsigned int)` | game_of_life (sleep 100), oracle examples | → `std.io.sleepMs` (`@sleepMs`) — **REMOVED (F4)** |
| 19× `__bootstrap_<DST>_from_<SRC>` :121-208 | per-pair `DST (SRC)` (see below) | zig1's c89_emit checked `int_cast` arm (isBootstrapHelperDefined, c89_emit.zig:2973-3013); also zig0-emitted compiler binary | **STAY** (compiler `@intCast` runtime; now panic via `std_panic`) |

**F4 (2026-08-08) — std-lib migration COMPLETE.** All 6 example-facing wrappers are removed from
`sf/src/include/zig_runtime.c`/`.h`; the 21 z98 examples were migrated to `std.io`
(`std.zig`/`std_io.zig` root package; per-example local copies resolved via `@import("std.zig")`,
the F3 std_arena precedent — bare `@import("std")` needs a resolver search-path feature, out of
scope). `__bootstrap_panic` was removed AFTER the 19 cast helpers (both `zig_runtime.c` defs and
`zig_runtime.h` static copies) were repointed to `std_panic("integer cast overflow in @intCast")`
(m0564). Verified: all 21 examples dump rc=0; 19/21 link+run (lisp_interpreter gcc `zT_N`
defect + rogue_mud D4 plat-stub link block are pre-existing); 4 MD5 gates re-baselined with
runtime-proof (AMENDMENT B).

**Builtin signatures (plan catalog, Option B):** `@putChar(c: u8) void`,
`@stderrWrite(buf: [*]const u8, len: usize) void`, `@getChar() u8`, `@exit(code: u8) noreturn`,
`@sleepMs(ms: u32) void`, `@stdoutWrite(buf: [*]const u8, len: usize) void` (added by operator
ruling m0564 — the I-RT concern-3 flag), `@isWindows() bool` (comptime), `@consoleClear() void`,
`@consoleGotoxy(x: i32, y: i32) void`, `@consoleSetColor(fg: i32, bg: i32) void`, then 11
`@socket*` in Phase 2. **F1 (2026-08-08) IMPLEMENTED the first 6:** `@putChar`/`@stdoutWrite`/`@stderrWrite`/`@getChar`/`@exit`/`@sleepMs` are live in sema (`semantic_analyzer.zig:1383-1398`),
lower (`lower.zig:2821-2858`, the 6 `builtin_*` LIR), and c89_emit (`emitBuiltinIncludes` +
`emitFwriteCall` + the 6 emission arms). `@putChar`/`@stdoutWrite`/`@stderrWrite`/`@getChar`/
`@exit` are portable (stdio/libc); `@sleepMs` uses `#ifdef _WIN32` `Sleep(ms)` / `#else`
`usleep(ms*1000)` (preprocessor-guarded C emission, never comptime), matching the zig0-oracle
runtime body. Guarded repro: `repro/mi_matrix/io_builtin_test`.

**F2 (2026-08-08) IMPLEMENTED the 3 console builtins + `@isWindows`:** `@consoleClear`/
`@consoleGotoxy`/`@consoleSetColor` are live in sema (`semantic_analyzer.zig:1401-1408`),
lower (`lower.zig:2860-2878`, the 3 `builtin_console_*` LIR), and c89_emit (see 08 §Builtin
console emission) with `#ifdef _WIN32 / #elif defined(__WATCOMC__) / #else` guards. `@isWindows()`
folds in `comptime_eval.zig` (module const `host_is_windows`, currently `false`; 1-bit
`ComptimeVal` 0/1) → `phase_ComptimeEvaluation` populates `comptime_values` → the lowerer emits
`int_const` (`TYPE_BOOL`) and the comptime branch folding below drops the dead branch. Guarded
repro: `repro/mi_matrix/console_builtin_test`.

**F6 (2026-08-13) IMPLEMENTED the 11 socket builtins (`lir.zig:89-99`, `lower.zig:2880-2977`):**
`@socketCreate`/`@socketBindListen`/`@socketAccept`/`@socketConnect`/`@socketSend`/
`@socketRecv`/`@socketSelect`/`@socketFdZero`/`@socketFdSet`/`@socketFdIsset`/`@socketClose`
emit the 11 `builtin_socket_*` LIR (phase-2 variants), lowering each call's value args to
operand temps (fd = i32, port/backlog/len/timeout = u32; the select fd-sets are optional
`?[*]u8` operands). The C emission ports net_runtime.c 1:1 (see 08 §6.9). Guarded repro:
`repro/mi_matrix/net_builtin_test`.

#### Comptime branch folding (F2, 2026-08-08) — `[updated: 2026-08-08]`

`if` statements (`lower.zig:3768-3790`) and `if` expressions (`lower.zig:3069-3083`) now check
`comptime_values` for the condition node before lowering: a comptime-known condition (0 or
nonzero) lowers ONLY the active branch — no `branch` inst, no empty blocks, and for `if_stmt` no
then/else/join blocks at all. Guarded against `if_capture` (`node.payload != 0` falls back to the
runtime path). This is what makes `if (@isWindows()) {…} else {…}` emit only the active branch.
Caveat: the folding is generic — any comptime-known condition (e.g. `@sizeOf(u32)` in an `if`)
folds too (Zig-correct; corpus-verified no emitted-C change outside `console_builtin_test`).

**`@intCast` cast-helper table (all STAY):** `usize_from_i64` :121, `i32_from_u32` :126,
`u32_from_u64` :131, `u32_from_i32` :136, `usize_from_i32` :141, `i32_from_usize` :146,
`u8_from_usize` :151, `u8_from_bool` :156, `f32_from_f64` :160, `i32_from_u8` :164,
`u8_from_i32` :168, `u8_from_u32` :173, `u16_from_i32` :178, `u32_from_i64` :183,
`u64_from_i64` :188, `i8_from_i32` :193, `i16_from_i32` :198, `i32_from_i64` :203,
`c_char_from_u8` :208. Also defined `static` in `zig_runtime.h` (per-TU; message
`"integer cast overflow in @intCast"`). `getCheckedCastFnName` (c89_emit.zig:2940) and the 8
`std_checked_cast_*` (upper-bound-only, `zig_runtime.c:76-113`) are **dead** in the current
emitter — F1 (2026-08-06) switched checked casts to the per-pair helpers.

### Control Flow

#### If Statement `sf/src/lower.zig:3220`
```
lowerExpr(cond) → cond_temp
If optional type → .check_optional to extract has_val
If tagged union → .load_field(TU_FIELD_TAG) to get tag
createBlock(then_bb, else_bb?, join_bb)
emitInst(.branch{ cond_temp, then_bb, fallthrough_bb })
→ then_bb: bindOptionalCapture? → lowerStmtBody(then_body) → .jump(join_bb)
→ else_bb: lowerStmtBody(else_body) → .jump(join_bb)
→ join_bb
```

#### If Expression `sf/src/lower.zig:2636`
Same pattern as if-statement but with `result` temp that both branches assign into.

#### While Statement `sf/src/lower.zig:3302`
```
createBlock(cond_bb, body_bb, exit_bb, cont_bb)
push LoopInfo{ header=cont_bb, exit=exit_bb }
.jump(cond_bb)
→ cond_bb: lowerExpr(cond) → check_optional? → .branch{ cond, body_bb, exit_bb }
→ body_bb: bindCapture? → lowerStmtBody(body) → .jump(cont_bb) (if not terminated)
→ cont_bb: lowerStmtBody(incr) → .jump(cond_bb) (if not terminated)
→ exit_bb: pop loop_stack
```

#### For Statement `sf/src/lower.zig:3389`

**Range for** (`range_exclusive`/`range_inclusive`):
```
lowerExpr(start), lowerExpr(end)
createBlock(cond_bb, body_bb, exit_bb)
push LoopInfo
.jump(cond_bb)
→ cond_bb: .binary{ LE/LT, start, end } → .branch{ cmp, body_bb, exit_bb }
→ body_bb: lowerStmtBody(body) → nxt = start + 1; start = nxt → .jump(cond_bb)
→ exit_bb: pop loop_stack
```

**Iteration for** (slice/array):
```
lowerExpr(array/slice) → extract .ptr and .len
idx = 0
createBlock(cond_bb, body_bb, exit_bb)
push LoopInfo
.jump(cond_bb)
→ cond_bb: .binary{ LT, idx, len } → .branch{ cmp, body_bb, exit_bb }
→ body_bb: .load_index{ ptr, idx } → item_temp; decl_local for capture → lowerStmtBody(body) → idx += 1 → .jump(cond_bb)
→ exit_bb: pop loop_stack
```

#### Switch Expression `sf/src/lower.zig:3114` [updated: 2026-08-07]
```
lowerExpr(cond) → cond_temp
If TU → .load_field(TU_FIELD_TAG) to extract tag
nextTemp(result_type) → result_temp
Compute cases: for each prong, append SwitchCase{ value, target_bb }
emitInst(.switch_br{ cond_temp, cases_start, cases_count, else_bb })
for each prong:
  set current_bb = prong_bb
  handle capture (TU payload extraction via .load_field)
  lower body → .assign(result_temp, val) → .jump(exit_bb)
exit_bb
```

**Switch case-collection loops** (expr `lower.zig:3167-3188`; stmt twin
`lower.zig:3904-3926`; entry handlers `swt_ex` at `lower.zig:3114` expr / `:3872`
stmt): each non-else prong's `case_ec` children are walked and a
`SwitchCase{ value, target_bb }` is appended per case node. The case-value
extraction handles **4 literal kinds**:

- `int_literal` → `case_val = store.int_values.items[@intCast(usize, case_node.payload)]`
  (`lower.zig:3170-3171` / `:3909-3910`). The literal's u64 value lives in
  `AstStore.int_values` at the node's `payload` index — `astStoreAddIntLiteral`
  stores the value at the payload index (ast.zig:317-321).
- `char_literal` → **same `store.int_values` payload access pattern** —
  `astStoreAddCharLiteral` also stores the char's u64 code in `int_values` at the
  payload index (ast.zig:323-327), exactly like int_literal. **FIXED (F1,
  2026-08-07):** both loops now have a `char_literal` branch (`lower.zig:3172-3173`
  expr / `:3911-3912` stmt) reading `store.int_values.items[@intCast(usize,
  case_node.payload)]`, mirroring `int_literal` (Option A per the I1 ruling in
  `.superpowers/sdd/I-char-switch-report.md`). Before F1, neither loop had it — a
  char case node fell to `else { continue; }` at `lower.zig:3185` / `:3924` and
  was silently dropped — `switch_br.cases_count` came out short and the C emitter
  rendered only `default:` (symptom: `switch (c) { default: … }`, no `case 'a':`
  label; runtime every input took the else prong). 12 `switch_char_*` repros in
  `repro/mi_matrix/` gate it (all 12 now print their post-fix outputs).
- `enum_literal` → `enum_value_table[case_node]` ordinal via `u32ToU32MapGet`,
  falling back to the raw `payload` (`lower.zig:3174-3178` / `:3913-3917`).
- `error_literal` → `error_code_registry` dense code via
  `u32ToU32MapGetOrAddDense`, falling back to the `enum_value_table` ordinal
  (`lower.zig:3179-3183` / `:3918-3922`).

The `else` prong is identified by `flags` bit0 (`lower.zig:3163` / `:3899` skip;
`:3194-3200` / `:3930-3936` set `else_target`).

#### Return Statement `sf/src/lower.zig:3614`
```
expandDefers(0, 0)  // emit all pending defers
lowerExpr(value) → .ret(val) or .ret_void
```

#### Break Statement `sf/src/lower.zig:4010`
```
expandDefers(exit_scope, 0) → .jump(exit_target)
```

#### Continue Statement `sf/src/lower.zig:4036`
```
expandDefers(cont_scope, 0) → .jump(header_target)
```

**Labeled break/continue — ACTIVE (F1, 2026-08-07, lower.zig:4012-4053):** `break :label` /
`continue :label` read `node.payload` as `label_id` (0=unlabeled). The unlabeled path keeps the
top-of-stack jump; the labeled path scans `loop_stack` top-down for `LoopInfo.label_id ==
label_id` and jumps to that loop's exit/header. `LoopInfo.label_id` is now stamped from
`self.current_label` at all 3 loop-push sites (lower.zig:3630 while, :3729 for-range, :3783
for-slice), and `current_label` is set from a `labeled_stmt` node's payload in `lowerStmt`
(lower.zig:3518-3524) with save/restore around the `child_0` recursion. Before F1, `label_id`
was hardcoded 0 so `break :label` never matched → the labeled loop HUNG. Scope limit (matches
plan): `break :label` out of a labeled **non-loop** block remains unsupported — the break
handler searches only `loop_stack`.

### Optional Unwrapping `sf/src/lower.zig:998`

`bindOptionalCapture`: Takes an optional value, emits `unwrap_optional` to get payload, then `decl_local` to bind capture name.

### Error Union Handling

#### Try Expression `sf/src/lower.zig:2469`
```
lowerExpr(inner) → inner_temp
.check_error(inner_temp) → is_err
.branch{ is_err, err_bb, ok_bb }
→ err_bb: expandDefers(0, 1) → .ret(inner_temp) or rewrap → .ret(rewrapped)
→ ok_bb: .unwrap_error_payload(inner_temp) → payload → .jump(join_bb)
→ join_bb: return payload
```

#### Catch Expression `sf/src/lower.zig:2524`
```
lowerExpr(lhs) → lhs_temp
.check_error → .branch{ is_err, err_bb, ok_bb }
→ err_bb: .unwrap_error_code → bind capture → lowerExpr(handler) → materializeInto → .assign(join_temp) → .jump(join_bb)
→ ok_bb: .unwrap_error_payload → .assign(join_temp) → .jump(join_bb)
→ join_bb: return join_temp
```

#### OrElse Expression `sf/src/lower.zig:2590`
Same structure as catch but for `?T`:
```
lowerExpr(lhs) → lhs_temp
.check_optional → .branch{ has_val, ok_bb, null_bb }
→ null_bb: lowerExpr(default) → materializeInto → .assign(join_temp) → .jump(join_bb)
→ ok_bb: .unwrap_optional → .assign(join_temp) → .jump(join_bb)
→ join_bb
```

### Slice Expression `sf/src/lower.zig:2965`
```
lowerExpr(base) → base_temp
Extract ptr/len from array or slice: .load_field(SLICE_FIELD_PTR/LEN) or .ptr_cast(array→manyptr) + int_const(len)
If start: .binary(ADD, ptr, start) → offset_ptr
If end: .binary(SUB, end, start) → new_len
emitInst(.make_slice{ ptr, len, result, type_id })
```

### Block Expression `sf/src/lower.zig:3148`
```
nextTemp(TYPE_VOID)
lowerStmtBody(node)  // recurses into block children
```

---

## Defer/Errdefer Expansion `sf/src/lower.zig:3922`

**Push**: `pushDefer(kind, ast_node)` appends a `DeferAction{ kind(0=defer, 1=errdefer), ast_node, scope_depth }` to `defer_stack`.

**Expand**: `expandDefers(target_depth, is_error_path)` iterates stack from top:
- For `defer` (kind=0): always emits the body
- For `errdefer` (kind=1): only emits when `is_error_path != 0`

**Fixed (F2, 2026-07-31):** `expandDefers` now takes a `pop` parameter. At scope-termination exits (`lowerStmtBody` block exit, `lowerStmt` block exit, `lowerFn` end), `pop=1` removes the action after emitting — preserving scope-lifetime semantics (a defer never re-emits after its scope closes). At internal exits (`return_stmt`, `break_stmt`, `continue_stmt`, try-error path), `pop=0` leaves the action on the stack — ensuring the defer/errdefer body is inlined at **every** runtime exit while the scope is live. This is the hybrid "pop at block-exit only" fix (Option B from I2 research), matching the design doc's intent at `docs/sf/AST_LIR_Lowering_p2.md:406-421` while closing its scope-termination blind spot.` [updated: 2026-07-31]

Called at:
- Scope exit in `lowerStmtBody` (target_depth = self.scope_depth, is_error_path = 0)
- `return_stmt` (target_depth = 0, is_error_path = 0)
- `break_stmt`/`continue_stmt` (target_depth = targeted scope + 1, is_error_path = 0)
- `try_expr` error path (target_depth = 0, is_error_path = 1)

---

## Temp Hoisting `sf/src/lower.zig:3942`

`hoistTemps()` runs at the end of `lowerFn()`. It:
1. Creates a new `LirInstArrayList`
2. Appends a `decl_temp` for each temp in `hoisted_temps` (skipping TYPE_VOID)
3. Appends all existing entry-block instructions
4. Replaces entry block's instruction list

This means all temporaries are declared at function entry, before any control flow — the ISA does not support SSA phi nodes, so every temp is effectively a `alloca`.

---

## TCO (Tail Call Optimization) Pattern — [updated: 2026-08-03]

The lowerer implements **tail-call elimination for self-recursion** and a **`tail_call` LIR variant**
for same-type cross-function tails. TCO feature commits: df412714 (F-S1, variant), 4702e9c8 + b0a53387
(F-S2, detection + try-CFG elimination), fa3cee16 (F-S3, C89 emission), 6dcf112e (F-S2 AMENDMENT 11,
same-type-only cross guard).

### `loop_header` injection at entry block — `sf/src/lower.zig:4349-4350`

Every function gets `loop_header(0)` as the first entry-block instruction. In `lowerFn`, immediately
after `self.current_bb = createBlock(self);` (:4349) the lowerer emits
`emitInst(self, LirInst{ .loop_header = @intCast(u32, 0) });` (:4350). The entry block id is always 0
(nothing allocates a block before lowerFn's entry createBlock). `hoistTemps` (:4362) prepends
`decl_temp` instructions to block 0, so the final entry-block order is
`decl_temp*, loop_header, body` — the C89 emitter's `.loop_header` arm emits `z_bb_0:` at that point,
landing the label after every temp/local declaration (see 08_c89_emission.md §1.8/§1.9).

### `findTailCall` — `sf/src/lower.zig:4138-4193`

Bounded **5-hop def-use walk** from the return temp (`hops < 5`, :4141). Each hop scans all blocks /
instructions for the inst whose `.result == cur`:
- `.call_direct` → `CallInfo{ is_self = (name_id == self.func.name_id and module_id == self.func.module_id) (:4153), is_indirect=0, is_extern = inst.call_direct.is_extern, callee, module_id, args_start, args_count, result, return_type, call_block_idx, call_inst_idx }` (:4156).
- `.call` (indirect) → `CallInfo{ is_self=0, is_indirect=1, is_extern=0, callee = inst.callee, module_id=0, return_type = TYPE_UNDEFINED, … }` (:4160).
- `.unwrap_error_payload` / `.unwrap_error_code` / `.wrap_error_ok` / `.wrap_error_err` with `.result == cur` → follow `.value` (:4162-4185) — this is what lets `return try self(...)` (ok-path payload) and `return <coerced>` (wrap chain) resolve back to the underlying call.

A hop that finds no defining inst returns `null` (:4190). `CallInfo` struct at `sf/src/lower.zig:4124-4136`.

### `return_stmt` TCO — `sf/src/lower.zig:3614-3673`

After `expandDefers` (:3615) and `lowerExpr` (:3618), guarded by `self.func.is_extern == 0` (:3629):
- `var tci = findTailCall(self, val);` (:3630). `null` → unchanged plain `ret` (:3666-3668).
- **Self-recursion** (`ci.is_self == 1 and ci.args_count == params.len`, :3632): `zeroCallCFG` first (:3633), then param-rebind assigns `param_temp_i = args_start + i` for every param (:3638-3641), then `emitInst(LirInst{ .jump = 0 })` back to the entry `loop_header` (:3642), then `block_terminated = 1` (:3644) — the old `ret` is suppressed by the `if (block_terminated == 0)` guard (:3666).
- **Cross-function** (`ci.is_self == 0 and ci.return_type == self.func.return_type`, :3645 — AMENDMENT 11): `zeroCallCFG` (:3646), then emit `tail_call` LIR with all 8 fields from CallInfo (:3651-3660), `block_terminated = 1` (:3662). The type-equality guard means type-changing coercions fall back to the plain `ret` path; indirect calls (`.call`, `return_type == TYPE_UNDEFINED`) never cross-TCO.
- Params mismatch (`args_count != params.len`) or `is_extern` fn → normal `ret` (defensive).

### try-CFG elimination — `sf/src/lower.zig:4195-4263` (AMENDMENT 7)

When the tail resolves through a try, the dead call CFG is zeroed out of the emitted blocks:
- `zeroCallCFG` (:4243): nops the defining call at `blocks[call_block_idx].insts[call_inst_idx]` (:4245), the following `check_error`/`check_optional` if present (:4246-4253), and the following `branch` if present (:4254-4261).
- `zeroChainInsts` (:4195): mirrors findTailCall's 5-hop walk, nop-ing the intermediate `unwrap_error_payload`/`unwrap_error_code`/`wrap_error_ok`/`wrap_error_err` insts that read the nop'd call result (:4207-4235).
- Rebind assigns / `tail_call` are emitted into the **CALL block** (`self.current_bb = ci.call_block_idx` when it differs from the current block, :3634-3637 / :3647-3650), then the original current block is restored. `block_terminated = 1` also suppresses the join-block `ret` (the `if (block_terminated == 0)` guard at :3666).

### Statement-form if/switch

Per-branch `return_stmt` sites inside `if_stmt`/`switch_stmt` bodies reach this same `return_stmt` handler and get TCO automatically. Expression-form `return if/switch (...)` (join-temp results) is out of scope (AMENDMENT 3) — the walk starts at the return temp and cannot resolve a join temp to one call without full dataflow, so those fall back to plain `ret`.

### Defer-after-TCO ordering — `sf/src/lower.zig:3618-3694` [updated: 2026-08-03]

`expandDefers(self, 0, 0, 0)` is called **once at the top of `return_stmt`** (:3618), before any TCO decision. The self-TCO branch then **nops the freshly-emitted defer instructions** when the defer stayed in the same block (`defer_bb_unchanged` guard, :3641-3645). `cross`/non-TCO branches preserve the defer instructions.

| Branch | expandDefers call | Defer behavior |
|--------|-------------------|----------------|
| Self-TCO | :3618 (emit) → :3641-3645 (nop) | Defer body nop'd per-iteration. Fires once at terminal exit via `expandDefers(self, 0, 0, 1)` at `lowerFn:4457`. |
| Cross TCO | :3618 (emit, preserved) | Defer fires once before `tail_call` emission. |
| No TCO (fallback ret) | :3618 (emit, preserved) | Existing behavior — defer fires before `ret`. |

The try-expr err-path (:2489) and terminal-exit (:4457) `expandDefers` calls are untouched. `pop=1` at :4457 ensures the defer is removed after the terminal re-emit, matching the hybrid pop semantics (see §Defer/Errdefer Expansion).

### `hasOtherConsumers` single-consumer guard — `sf/src/lower.zig:4265-4340` [updated: 2026-08-03]

Defensive guard called **before `zeroCallCFG`** in both self (:3647) and cross (:3664) TCO branches. **Scans ALL blocks** for any instruction referencing `call_result` that is NOT a recognized chain consumer:

- **Skipped (chain consumers):** `call_direct`, `call`, `unwrap_error_payload`, `unwrap_error_code`, `wrap_error_ok`, `wrap_error_err`, `check_error`, `ret` (for `ret_temp` only), `nop`.
- **Checked (all other variants):** every input field is compared against `call_result` — `.value`, `.src`, `.operand`, `.ptr`, `.base`, `.cond`, `.lhs`, `.rhs`, `.index`, `.callee` (for `tail_call`).
- **Returns `true`** → TCO is **skipped entirely** (falls through to normal `ret` path at :3688-3690).
- **Returns `false`** → `zeroCallCFG` + TCO emission proceeds normally.

This guard is **purely defensive** — no valid Z98 pattern triggers it today. It future-proofs against instrumentation/debug/optimization passes that might create secondary consumers of the call result temp after the recognized chain. The full false-return path (all recognized consumers, no false positive) is exercised by the existing tco_factorial and tco_return_try examples.

---

## Type Coercions `sf/src/lower.zig:4469`

`applyCoercion` dispatches to `materializeInto` and specific cast instructions:

| CoercionKind | LIR Pattern |
|-------------|-------------|
| `none` | `applyNoneCoercion` (lower.zig:4456) — handles null→optional null ptr via `set_optional_null`/`int_const(0)` |
| `wrap_optional_null` | `materializeInto(src, target, null_src)` → `set_optional_null` — src is the `?T`-typed temp already produced by the null_literal branch (Option B, 2026-08-07); `materializeInto` short-circuits on `src_ty == expected` (lower.zig:911) or wraps into outer EU layers. No dead `int zT_N; zT_N = NULL;` in the stream |
| `wrap_optional` | `materializeInto(src, target, intent)` → `wrap_optional` |
| `wrap_error_success` | `materializeInto(src, target, intent)` → `wrap_error_ok` |
| `wrap_error_err` | `materializeInto(src, target, error_src)` → `wrap_error_err` |
| `int_widen` | `int_cast{ is_checked=0 }` |
| `float_widen` | `float_cast` |
| `int_literal_coerce` | `int_cast{ is_checked=0 }` |
| `ptr_to_optional_ptr` | `materializeInto(src, target, intent)` → `wrap_optional` |
| `array_to_slice` | `int_const(len)` + `make_slice{ ptr, len }` |
| `array_to_many_ptr` | `ptr_cast` |
| `slice_to_many_ptr` | `ptr_cast` |
| `string_to_slice` | `int_const(len)` + `make_slice{ ptr, len }` |
| `string_to_many_ptr` | `ptr_cast` |
| `string_to_ptr` | `ptr_cast` |
| `const_qualify` | No-op (identity) |
| `unwrap_optional` | No-op (identity) |

`materializeInto` (`sf/src/lower.zig:906`) is the general mechanism: given a source temp and an expected type, it walks the type hierarchy (optional layers, error union layers) and emits wrapping instructions (`wrap_optional`, `wrap_error_ok`, `wrap_error_err`, `set_optional_null`) to match the expected type shape.

**Null-construction path (FIXED, Option B, [updated: 2026-08-07]):** for a `null_literal` whose coercion routes to `SrcIntent.null_src` (`wrap_optional_null`/`wrap_optional`/`wrap_error_success`) with an optional layer in the target chain, the null_literal branch (lower.zig:1183) walks the coercion target chain (`optional_type` → layer; `error_union_type` → payload, max 8) to find the optional layer and emits `set_optional_null` directly on a temp typed as that optional layer — instead of emitting the old dead `null_const` temp (`int zT_N; zT_N = NULL;`, typed `null_type`→`int` via `nextTemp(TYPE_NULL)` lower.zig:1184 → `getCTypeName(null_type)` = `"int"` c89_emit.zig:605). `materializeInto` then short-circuits on `src_ty == expected` (lower.zig:911) for a plain `?T`, or wraps the `?T` temp into outer error-union layers (`eul == src_ty` match at lower.zig:945 → `wrap_error_ok`) for `E!?T`. Result: no `int zT_N;`, no `zT_N = NULL;` — fixes the gcc `-Wint-conversion` warning for both `?*T` and `?[]T` null construction. Emitted C is now `Opt_... zT; zT.has_value = 0;` (or `EU`-wrapped). Non-optional-target null (pointer/fn, no optional layer) still uses the `null_const` path unchanged.

**FIXED — module-scope global `= null` init (Defect B, [updated: 2026-08-13, F2]):**
the module-scope `var_decl` global-init path (`main.zig` `phase_ComptimeEvaluation`
loop, :400-441) previously hand-rolled `pushExpectedType`/`semanticAnalyzerResolveExpr`/
`popExpectedType` and **never recorded a coercion** — unlike the function-body
`var_decl` path (sema `classifyCoercion` + `coercionTableAdd(decl.child_1, ck, decl_type)`).
A module-scope `var g: ?*Node = null;` had no `wrap_optional_null` entry, so the
null_literal branch's `coercionTableGet` (lower.zig:1268) returned null and the
fallback emitted `null_const` with a `TYPE_NULL` temp (:1298-1301), which the
emitter typed `"int"` (`getCTypeName(null_type)`, c89_emit.zig:605) →
`int zT_0; zT_0 = NULL;` → `store_global` assigned `int` to an `Opt_`-typed
global → gcc `incompatible types ... from type 'int'`.
**Fix (F2, operator ruling m0792 — Option 2):** the coercion record lives in
sema. New **pub** fn `semanticAnalyzerResolveModuleVarDecl(self, decl_idx) u32`
(`sf/src/semantic_analyzer.zig`, after `semanticAnalyzerResolveStmt`) owns the
resolve + coercion record: reads the declared type from `rtt_mod.resolvedTypeTableGet`
(`decl.child_0`), `pushExpectedType`/`semanticAnalyzerResolveExpr`/`popExpectedType`,
then `classifyCoercion(errLitSrcType(decl.child_1, decl_type, it), decl_type)` →
if non-`none` `coercionTableAdd(coercion_table, decl.child_1, ck, decl_type)` —
mirroring the function-body `var_decl` block (sema :1890-1895); returns the
resolved init type. `main.zig`'s global-init loop calls it
(`var init_type = sa_mod.semanticAnalyzerResolveModuleVarDecl(&sa, decls[di]);`)
instead of hand-rolling push/resolve/pop; module-scope symbol registration
(ident_expr nameCachePut, INT_LIT re-resolution, resolvedTypeTableSet) stays in
main.zig. The lowerer/emitter paths already handle `wrap_optional_null`, so the
null_literal branch now emits `set_optional_null` on an `Opt_`-typed temp:
`zT_AEEBC7B3_Opt_26 zT_0; zT_0.has_value = 0; zG_E20C2606_g = zT_0;`. Reproduction
`repro/mi_matrix/global_null_init_xmod`: dump/gcc/link/run rc=0, prints `1`.
Unblocks the exact lisp shape (`examples/z98/lisp_interpreter` `parser.zig:12`
`var global_symbol_list: ?*SymbolNode = null;`).
**Side effect (operator re-baseline m0809, [updated: 2026-08-13]):** the fn
records ALL non-`none` coercions, so the shared module-scope scalar
`std_arena.zig:8 var g_used: usize = 0;` (game_of_life / lisp_interpreter_curr /
json_parser) now records `int_literal_coerce` and the lowerer emits one cast on
the global init (`zT_1 = (unsigned int)zT_0; zG_099B6C9A_g_used = zT_1;`) —
matching function-body behavior for `var x: usize = 0`; runtime byte-identical
(AMENDMENT B). gol/lisp/json MD5 gates **re-baselined** to
`ff47d18d…`/`c1cb748b…`/`376fd681…`; mud `fd0fdaa4…` byte-identical.

---

## Control Flow Graph Construction

Blocks are created lazily via `createBlock()`. Every branch/switch terminator sets `is_terminated = 1` on the source block. The CFG is implicit in the block indices stored in jump/branch instructions. No explicit edge lists or dominator trees are built at the LIR level.

---

## Experimental Evidence (P7 Deep-Dive, 2026-07-31) — [updated: 2026-08-01]

Verified on the 4 working examples (`examples/z98/{mud_server,game_of_life,lisp_interpreter_curr,json_parser}/main.zig`) with two independent methods:

- `[markers]` — the P0 traces `/tmp/dd/*.mrk` (`zig1 --markers --dump-c89`). The LIR-phase region runs from the `L\n` marker (`main.zig:508`) through the per-module `M<idx>:<ast_root>:R<decls>:<kinds>` markers (`main.zig:537`), the per-fn `FNL:<name_id>` markers (`lower.zig:4116`) and `D3HT:` temp dumps (`lower.zig:4183`), up to `A0 <kinds>` (`main.zig:586`) and the closing `C\n` (`main.zig:605`).
- `[fprintf]` — a debug build of zig1 (`zig0` bootstrap into a fresh dir, `gcc -g -O0`) with `emitInst`, `expandDefers`, `pushDefer`, `applyCoercion`, `materializeInto` and the `@ptrCast` builtin site instrumented in the generated `lower.c` (`fprintf` to stderr). Instrumentation does **not** perturb codegen: `--dump-c89` output is byte-identical to the P0 baselines (md5 mud `87954d75…`, gol `9cc38ab9…`, lisp `6a8ca449…`, json `9492e3b3…`).

Phase-scope summary `[markers]`:

| Example | `nodes=`/`extra=` | modules | fn_decls lowered (`FNL`) | fns with bodies (emitted C) | `A0` (module-0 decl kinds) |
|---------|------------------|---------|--------------------------|------------------------------|----------------------------|
| mud_server | 944 / 343 | 4 (`M0:843:R28` `M1:926:R1` `M2:923:R2` `M3:943:R3`) | 20 | 7 | `1 1 96 96 2 2 2 2 2 2 2 2 1 2 2 2 2 1 1 1 1 1 1 2 1 2 2 2` |
| game_of_life | 807 / 382 | 3 (`M0:774:R14` `M1:777:R1` `M2:806:R5`) | 11 | 7 | `1 96 96 2 2 1 1 1 1 2 2 2 2 2` |
| lisp_interpreter_curr | 3854 / 1307 | 10 (`M0:810:R21` … `M9:908:R4`) | 48 | 45 | `1 1 1 1 1 1 1 1 1 96 96 2 …` |
| json_parser | 1568 / 534 | 3 (`M0:292:R13` `M1:1567:R16` `M2:1375:R20`) | 32 | 19 | `1 1 96 96 96 2 2 1 2 2 2 2 2` |

(Per-module `M` counts sum to the `FNL` totals; the fn_decl count matches the P6 static-analyzer count on the same traces.)

### 1. LirInst variant distribution

Total instructions **emitted via `emitInst`** per example `[fprintf]` (note: `decl_temp` is prepended by `hoistTemps` directly into the entry block — `lower.zig:3953` — so it never passes through `emitInst`; add the `D3HT` temp totals below to get the full instruction count):

| Example | insts via emitInst | + hoisted `decl_temp` | total |
|---------|--------------------|------------------------|-------|
| mud_server | 686 | 454 | 1140 |
| game_of_life | 698 | 462 | 1160 |
| lisp_interpreter_curr | 3634 | 2256 | 5890 |
| json_parser | 1452 | 945 | 2397 |

Top variants per example `[fprintf]`:

| Example | top LirInst variants (count) |
|---------|------------------------------|
| mud_server | assign 116, int_const 81, load_field 56, jump 55, binary 53, branch 41, store_local 41 |
| game_of_life | int_const 157, assign 138, jump 56, assign_field 56, binary 54, int_cast 45, store_local 36 |
| lisp_interpreter_curr | assign 703, jump 318, load_field 304, int_const 263, decl_local 219, ret 203, branch 199 |
| json_parser | assign 254, int_const 144, jump 143, call_direct 127, load_field 124, binary 123, branch 102 |

Dominant shape: **`assign` + `int_const` + `jump` + `branch` dominate in every example** — a straight-line, alloca-based, jump-heavy IR. json_parser is the most call-heavy (127 `call_direct`, its parser is deeply recursive), lisp the most branch/switch-heavy (21 `switch_br` in `eval` alone). Per-function detail `[fprintf]` (top function per example): mud `main` 427 insts (assign 84, int_const 43, binary 41, jump 40); gol `main` 496 (int_const 133, assign 99, assign_field 54); lisp `eval` 826 (assign 182, load_field 75, jump 74); json `parseObject` 214 (assign 46, call_direct 24, jump 19). 44 of the 57 variants fire via `emitInst`; the 13 that never fire in these examples are `decl_temp` (only via `hoistTemps`, `lower.zig:3953`), `loop_header`, `label`, `float_cast`, `int_to_float`, `int_to_ptr`, `float_const`, `enum_const`, `load_global`, `store_global`, `va_start`, `va_arg`, `va_end` — and `unary` is rare (13 total across all 4). The `va_start`/`va_arg`/`va_end` variants (added 2026-08-06) do not fire in these 4 examples (none use `@cVa*`). `[updated: 2026-08-03]` Since the TCO feature (F-S2, `lowerFn` at `lower.zig:4350`) the `loop_header` variant now fires **once per function** (first entry-block inst) in every example; it was 0 in the 2026-07-31 P7 capture. The `tail_call` variant fires for every cross-function same-type tail (eval.zig:169 `return try apply(...)`, json extern `file.strtod`, etc.).

### 2. Temp counts per function / hoisting

`D3HT:<tid,type>|…` is emitted once per lowered fn (`lower.zig:4183`); its entry count = total temporaries for that function (params included — each param gets a `nextTemp`, `lower.zig:4135`, then its type is patched in `hoisted_temps`, `lower.zig:4145`). `[markers]`:

| Example | fns | total temps | avg | max temp count |
|---------|-----|-------------|-----|----------------|
| mud_server | 20 | 454 | 22.7 | 264 (`main`) |
| game_of_life | 11 | 462 | 42.0 | 339 (`main`) |
| lisp_interpreter_curr | 48 | 2256 | 47.0 | 462 (`eval`) |
| json_parser | 32 | 945 | 29.5 | 126 (`parseObject`) |

Temp hoisting does create many temporaries: every intermediate (each literal, field load, call result, wrapper) gets its own temp, and `hoistTemps` (lower.zig:3942) prepends a `decl_temp` for **all** of them (skipping `TYPE_VOID`, lower.zig:3949) to the entry block. Consequence visible in emitted C: `eval` declares 461 `zT_` temps at function top (lisp_interpreter_curr.c:3915-4438); `readFile` declares 79 `zT_` temps (json_parser.c:704-788; its D3HT count of 81 includes the 2 params). All temps are effectively `alloca` slots — the IR has no SSA/phi discipline.

### 3. Defer/errdefer expansion trace (json_parser `fclose`)

Only **one** `defer` exists across all 4 examples: `readFile` in `examples/z98/json_parser/file.zig:30` (`defer { _ = fclose(f); }`). No `errdefer` anywhere. `[fprintf]` trace of `readFile` (FNL:74, 111 insts, 81 temps):

```
P7PD:0,1491              <- pushDefer(kind=0 defer, ast_node=1491)
P7XD:0,0                 <- first return site (fseek(END)!=0): expands the defer
   P7CD:139,32           <- fclose() call inlined at this return
P7XD:3,0 ... P7XD:0,0    <- subsequent return sites (size<0, fseek(SET)!=0,
P7XD:0,0 ... P7XD:0,0       bytes_read!=size, ferror!=0, success): NO fclose
```

`expandDefers` counts `[fprintf]`: pushDefer 0/0/0/1, expandDefers calls 86/55/593/195 for mud/gol/lisp/json. **Fixed (F2, 2026-07-31):** The single-use defer issue has been resolved via the hybrid-pop fix (Option B from I2 research). `expandDefers` now takes a `pop` parameter: at scope-termination exits (block exit, fn-end) `pop=1` removes the action; at internal exits (return, break, continue, try-error) `pop=0` leaves it for re-expansion at subsequent exits. After the fix, `readFile`'s emitted C contains `fclose` at all 6 return paths (pre-fix: only 1), closing the FILE* leak.` [updated: 2026-07-31]

### 4. `@ptrCast` lowering: scalar vs tagged-union vs fn-pointer

The builtin path (`lower.zig:2381-2466`) emits `.ptr_cast{ value, target, result }` **uniformly** — the source expression is lowered without any source-kind check (`val_temp = lowerExpr(ec[1])`, lower.zig:2424), so pointer-to-pointer, pointer-to-many-ptr and fn-pointer casts all produce the same LirInst. The only differentiation is **target type resolution** (`lower.zig:2425-2445`):

- If the type argument is a `fn(...)` type: `resolveTypeExprFull` + `typeRegistryMarkFnPtrUsed` (lower.zig:2435-2438), emitting the `FNT:t` marker (lower.zig:2439) and registering the fn-ptr type so the C emitter can emit the `typedef`.
- Otherwise: plain `resolveTypeExprFull` (lower.zig:2442-2444); a `CASTDFLT` marker fires if the target defaults to `TYPE_U32` (lower.zig:2446).

`[fprintf]` per-site evidence (value-type kind → target-type kind, both `ptr_type`(17) / `many_ptr_type`(18)):

| Example | site | source kind → target kind |
|---------|------|---------------------------|
| lisp `apply` (eval.zig:264, fn-pointer) | `*void` → ptr-to-fn | 17 → 17, `FNT:t` fired (the only FNT:t in all 4 examples) |
| lisp `main` (main.zig:107-108) | `*[1048576]u64` → `[*]u8` | 17 → 18 |
| lisp `main` (main.zig:116-126, 11 sites) | ptr-to-fn → `*void` | 17 → 17 |
| json `readFile` (file.zig:28-29,38) | `*[2]c_char` / `*void` → `[*]u8` | 17 → 18, 17 → 18, 17 → 18 |
| json `parseObject`/`parseArray`/`parseJson` | `*void` → `[*]T` / `*T` | 17 → 18 / 17 → 17 |

There is **no scalar (non-pointer) or tagged-union `@ptrCast`** anywhere in the 4 examples, so those two cases are not exercised; from the code the only distinguishing mechanism is the fn-type target path above. (The `@ptrCast([*]const c_char, "rb")` string case is likewise a uniform `ptr_cast` — file.zig:28.)

### 5. TCO assessment (lisp `eval` loop) — [updated: 2026-08-03]

**TCO is now detectable — implemented** (F-S1/F-S2/F-S3, see §TCO above). The 2026-07-31 "no TCO"
findings below were the pre-TCO state; each item is re-assessed:

- `loop_header` (lir.zig:31) is **now emitted once per function** — `lowerFn` injects
  `LirInst{ .loop_header = 0 }` as the first entry-block inst (`lower.zig:4350`). `while_stmt`
  lowering (lower.zig:3302-3388) still builds the plain 5-block CFG (entry → cond → body → exit →
  cont, back-edge cont → cond) with `jump`/`branch` only; the entry `loop_header` is the self-TCO
  jump target, not a loop-marking inst.
- `eval`'s manual `while (true)` trampoline (eval.zig:12) still lowers to: `jump cond` (entry),
  `bool_const(1)` + `branch` (cond block BB1), body with the expr-type `switch_br` (21 of them), and
  a back-edge `jump` to BB1. The source-level `continue`s (eval.zig:56,61,222) remain plain
  `goto`/`jump` to the loop header — loop branches, not tail calls.
- The tail-position `return try apply(fun, args, …)` (eval.zig:169, `.Builtin` prong) is a **direct
  cross-function call with matching return type** → `findTailCall` resolves it, `zeroCallCFG` +
  `zeroChainInsts` nop the `call_direct`/`check_error`/`branch`/unwrap chain, and a `tail_call` LIR
  inst is emitted in the call block. The C89 emitter's `.tail_call` arm produces
  `zT_N = zF_24BC4A3B_apply(zT_…,…); return zT_N;` — a call+ret (not a jump; see the C89 cross-function
  limitation in 08_c89_emission.md). This replaced the old full try-CFG trace
  (previously `lisp_interpreter_curr.c:5480-5509`).
- `apply`'s tail-position `return try f(args, temp_sand)` (eval.zig:265) is an **indirect fn-pointer
  call** → `findTailCall` carries `return_type = TYPE_UNDEFINED` for `.call`, and the AMENDMENT-11
  same-type guard (`lower.zig:3645`) disables cross TCO → falls back to the normal ret path, which
  re-emits the full `check_error`/unwrap/`.is_error = 0` re-wrap. Indirect cross-TCO is conservatively
  disabled even when the fn-pointer callee shares the enclosing fn's return type (a missed
  optimization, accepted by ruling).
- `eval`'s 4 plain recursive `zF_08D22E0F_eval(...)` calls (lisp_interpreter_curr.c:4636, :4753,
  :4990, :5440) are non-tail (mid-loop / argument positions) and remain frame-preserving calls — the
  self-recursion trampoline only benefits from TCO at direct tail sites.

**Byte-identity note:** the `z_bb_0:` label emitted in every function (AMENDMENT 8) and the
try-CFG collapse to `zT = f(args); return zT;` are accepted baseline changes — the lisp stdout md5
was re-baselined from `0ad02040…` to `10d09c99f77c68e680f6ccce33eb81ed` (see QUICK_REF.md).

### 6. Coercion application: `applyCoercion` vs `materializeInto`

`applyCoercion` (lower.zig:4469) dispatches exactly as the §Type Coercions table describes: the 5 wrapper kinds (`wrap_optional_null`, `wrap_optional`, `wrap_error_success`, `wrap_error_err`, `ptr_to_optional_ptr`) and `none`-with-null delegate to `materializeInto` (lower.zig:906), which walks up to 8 optional/error-union layers (lower.zig:913-949) and emits `set_optional_null`/`wrap_optional`/`wrap_error_ok`/`wrap_error_err`, optionally preceded by an inner `int_cast`/`float_cast` (lower.zig:952-964). `[fprintf]` call counts:

| Example | applyCoercion calls | materializeInto calls | dominant kinds |
|---------|---------------------|------------------------|----------------|
| mud_server | 51 | 8 | int_literal_coerce 20, none 14, string_to_slice 12 |
| game_of_life | 99 | 10 | none 52, int_literal_coerce 39, const_qualify 8 |
| lisp_interpreter_curr | 595 | 135 | none 329, wrap_error_success 60, string_to_slice 53, wrap_error_err 53, int_literal_coerce 48 |
| json_parser | 159 | 34 | none 95, int_literal_coerce 27, wrap_error_success 15, wrap_error_err 14 |

Cross-check `[markers]`: the `CEM`/`CEP` markers are emitted **per `lowerExpr`** call (lower.zig:446-468) — `CEP:n…k<kind>` when a coercion entry exists (→ `applyCoercion`), `CEM:n…` when missing. `[markers]` CEP counts (mud 36, gol 43, lisp 261, json 63) and the CEP-kind distribution (int_literal_coerce / string_to_slice / wrap_error_* / unwrap_optional / wrap_optional_null, exactly the table's kinds) agree with the `[fprintf]` `applyCoercion` kinds. The `[fprintf]` totals are higher because `applyCoercion` also fires at non-`lowerExpr` sites (call args `lower.zig:2022, :2092, :2176, :2269`, return values, compound-assign sites `lower.zig:1391`); the `none` kind (52 in gol) comes from `applyNoneCoercion` (lower.zig:4456), which rewrites `null` → optional-null / `int_const(0)` pointer.

---

## Debugging — [updated: 2026-08-01]

The lowerer emits verbose marker output prefixed with `"L"` (for LIR lowering). **The `--dump-lir` flag is DEAD**: its flag string is declared (`main.zig:775`) but never matched in `parseArgs`, so `cli.dump_lir` stays `false` and nothing reads it anywhere in the pipeline. Marker output is instead gated on the `--markers` flag via `pal.markerWrite()`/`markerWriteInt()`, which check `g_markers_enabled` (`sf/src/pal.zig:96-103`). Run `zig1 --markers --dump-c89 <file>` and capture stderr to see the per-node tracing below.

| Marker | Meaning |
|--------|---------|
| `LEX:n<idx>k<kind>` | Entering lowerExpr (node + kind) |
| `CT:t<type>r<tid>` | Creating temp with type_id (nextTemp) |
| `NXT:i<idx>k<kind>t<tid>` | nextTemp warning for void/undefined type |
| `GBL` | Global lowering context |
| `BB` | Struct init entry |
| `ILR` | Int literal |
| `STK` | Statement kind |
| `BLC` | Block child processing |
| `FNL:<name_id>` | Function lowering — one per lowered fn_decl (`lower.zig:4116`) |
| `D3HT:<tid,type>\|...` | Hoisted temps dump — one per fn, entry count = total temp count (`lower.zig:4183`) |
| `CEM:n<idx>` | Coercion check — coercion missing (per lowerExpr, `lower.zig:463`) |
| `CEP:n<idx>k<kind>` | Coercion check — coercion present, kind emitted (`lower.zig:456`) |
| `COE/CO2` | Compound-assign coercion sites (`lower.zig:1391`) |
| `XD:<depth>,<err>` / `PD:<kind>,<node>` | expandDefers / pushDefer tracing (instrumented builds; see P7 evidence above) |

All markers use `pal.markerWrite()` which outputs to stderr when `--markers` is enabled.


