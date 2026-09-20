# 07 — LIR Lowering [updated: 2026-09-20 — refreshed against the current 82-variant `LirInst` set, `lir_opt_pass`/`lir_stream`/`spill_store` coverage, packed bitfields, arbitrary-width int ops, `-fsafe` checks, `volatile`, calling convention, and async lowering; line references and dated evidence removed]

> Covers: `lower.zig`, `lir.zig`, `lir_opt_pass.zig`, `lir_stream.zig`, `spill_store.zig`

## Summary

The lowering phase transforms the typed AST (AstStore) into a low-level intermediate representation (LIR) suitable for direct code generation. It handles control-flow flattening, temporary hoisting, defer/errdefer expansion, packed bitfield access, `-fsafe` checks, and type-coercion application.

Five files:
- `sf/src/lir.zig` — LIR data types (`LirInst`, `LirFunction`, `BasicBlock`, side tables, array lists)
- `sf/src/lower.zig` — `LirLowerer` struct that walks the AST and emits LIR
- `sf/src/lir_opt_pass.zig` — per-function optimization pass (copy propagation, local const-fold, arg/join copy coalescing, expression-nesting metadata)
- `sf/src/lir_stream.zig` — serializes/deserializes each `LirFunction` through the spill store
- `sf/src/spill_store.zig` — offset-addressed byte spill with Disk/Ram backends

## Data Flow

```
AstStore (fn_decl) → lowerFn() → LirFunction → lirStreamAppend() ── spill ──▶
  phase_C89Emission: lirStreamReadFunction() → lirOptRun() → c89_emit
```

`lowererInit()` creates a `LirLowerer` with empty stacks. `lowerFn()` is called per `fn_decl`, producing one `LirFunction`; `lowerModuleInit()` synthesizes one `__module_init` per module with runtime globals. The function's LIR is serialized through `lir_stream.zig` into `spill_store.zig` (`spillBackendFor(SpillId.s_lir)`); during emission each function is faulted back in, optimized by `lirOptRun`, and then emitted.

**Streaming LIR (current).** `phase_LIRLowering` opens the LIR spill stream and calls `lirStreamAppend` for every non-suspending function plus each module's `__module_init`; suspending functions are retained in scratch for the two-phase async transform and streamed by the transform. Each append returns a `LirSlot { module_id, disk_offset, byte_len }` recorded in `ctx.lir_slots`. `phase_C89Emission` reopens the stream for reading and faults each slot in before emission. All LIR payloads are scalar ids, so the raw byte dump is byte-preserving in both the Disk and Ram backends.

---

## lir.zig — LIR Data Types `sf/src/lir.zig`

### Core Types

| Type | Fields | Purpose |
|------|--------|---------|
| `SwitchCase` | `value: u64`, `target_bb: u32` | Case value mapping to a target basic block |
| `LirParam` | `name_id: u32`, `type_id: TypeId`, `temp_id: u32` | Function parameter declaration |
| `TempDecl` | `temp_id: u32`, `type_id: TypeId` | Hoisted temporary declaration |
| `BasicBlock` | `id: u32`, `insts: LirInstArrayList`, `is_terminated: u8` | Basic block with instruction list |
| `LirFunction` | `name_id`, `module_id`, `return_type`, `params`, `blocks`, `hoisted_temps`, `switch_cases`, `side_table`, `temp_variant_sub_field`, `is_extern`, `is_pub`, `is_variadic`, `call_conv`, `poison_uninit`, `is_export` | Compiled function unit |
| `LirSlot` | `module_id: u32`, `disk_offset: u32`, `byte_len: u32` | Spill-stream location of one serialized function |
| `ModuleGlobalDecl` | `name_id`, `module_id`, `type_id`, `has_runtime_init` | Module-scope global declaration |
| `CallDirectData` | `name_id, module_id, args_start, args_count, result, return_type, is_extern, call_conv` | Operands of a `call_direct` (side table) |
| `TailCallData` | `callee, module_id, args_start, args_count, result, return_type, is_indirect, is_extern, call_conv` | Operands of a `tail_call` (side table) |
| `LirSideEntry` | union `{ call_direct, tail_call }` | Side-table payload union |

`LirInst` carries the tag plus a `u32` slot for the two wide variants `call_direct`/`tail_call`; their operands live in the per-function `side_table` (`LirSideEntryArrayList`) and are serialized with the function. The largest inline payload is `enum_const` (20 B, padded to 24 B), so the Z98-folded `@sizeOf(LirInst)` that `lir_stream` writes stays 32 B. `CallDirectData`/`TailCallData` carry a `call_conv` flag (0 or `FN_FLAG_STDCALL`).

`CHECK_OP_*` discriminators (`u8`): `CHECK_OP_ADD = 0`, `CHECK_OP_SUB = 1`, `CHECK_OP_MUL = 2`, `CHECK_OP_SHL = 3`, `CHECK_OP_NEG = 4` — used by `overflow_flag`.

### LirFunction Fields

| Field | Type | Description |
|-------|------|-------------|
| `name_id` | `u32` | Interned function name |
| `module_id` | `u32` | Defining module |
| `return_type` | `TypeId` | Resolved return type |
| `params` | `LirParamArrayList` | Parameter list |
| `blocks` | `BasicBlockArrayList` | All basic blocks (entry at index 0) |
| `hoisted_temps` | `TempDeclArrayList` | All temps hoisted to function entry |
| `switch_cases` | `SwitchCaseArrayList` | Switch case value→block map |
| `side_table` | `LirSideEntryArrayList` | `call_direct`/`tail_call` operand storage |
| `temp_variant_sub_field` | `U32ToU32Map` | Maps temps to variant sub-field indices |
| `is_extern` | `u8` | External linkage flag |
| `is_pub` | `u8` | Public visibility flag |
| `is_variadic` | `u8` | Variadic parameter flag |
| `call_conv` | `u8` | Calling convention (0 or `FN_FLAG_STDCALL`) |
| `poison_uninit` | `u8` | `-fsafe` `undefined` poison-net decision transported to the emitter |
| `is_export` | `u8` | `export fn` flag (a suspending `export fn` is a synchronous-driver target) |

### All 82 LirInst Variants `sf/src/lir.zig`

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
| `addr_of` | `operand, result` | Take the address of a local/global |
| `addr_of_field` | `base, field_id, result` | Address of a field within a base address |
| `load_field` | `base, field_id, result, name_id` | Read struct/union/slice field |
| `store_field` | `base, field_id, value, name_id` | Write struct/union/slice field |
| `load_index` | `base, index, result, name_id, decay` | Read array element (`decay=1`: pointer-to-array element address) |
| `load_local` | `name_id, result` | Load named local variable |
| `store_local` | `name_id, value` | Write named local variable |
| `load_global` | `name_id, module_id, result` | Load named global |
| `store_global` | `name_id, module_id, value` | Write named global |
| `load_bitfield` | `base, result, name_id, bit_offset, bit_width` | Read a packed-struct/union bitfield |
| `store_bitfield` | `base, value, bit_offset, bit_width` | Write a packed-struct/union bitfield |

#### Control Flow
| Variant | Fields | Purpose |
|---------|--------|---------|
| `jump` | `u32` (target block) | Unconditional branch |
| `branch` | `cond, then_bb, else_bb` | Conditional branch on bool/optional |
| `switch_br` | `cond, cases_start, cases_count, else_bb` | Multi-way branch (lookup in `func.switch_cases`) |
| `loop_header` | `u32` (label/block ID) | Loop entry marker / self-TCO jump target |
| `ret` | `u32` (value) | Return with value |
| `ret_void` | `void` | Return without value |
| `label` | `u32` | Label marker for jumping |
| `trap` | `void` | Emit a live trap (`pal_trap`) |

#### Arithmetic & Logic
| Variant | Fields | Purpose |
|---------|--------|---------|
| `binary` | `op, lhs, rhs, result` | Binary arithmetic (add/sub/mul/div/mod/and/or/xor/shl/shr/eq/ne/lt/le/gt/ge, plus wrapping/saturating ops) |
| `unary` | `op, operand, result` | Unary arithmetic (neg/not/bnot) |
| `add_with_overflow` | `lhs, rhs, result, result_type, width, is_signed` | `-fsafe` wrapping add (value half) |
| `sub_with_overflow` | `lhs, rhs, result, result_type, width, is_signed` | `-fsafe` wrapping sub (value half) |
| `mul_with_overflow` | `lhs, rhs, result, result_type, width, is_signed` | `-fsafe` wrapping mul (value half) |
| `shl_with_overflow` | `lhs, rhs, result, result_type, width, is_signed` | `-fsafe` wrapping shl (value half) |
| `neg_with_overflow` | `value, result, result_type, width, is_signed` | `-fsafe` wrapping negate (value half) |
| `overflow_flag` | `lhs, rhs, result, result_type, op, width, is_signed` | Boolean overflow predicate for the matching `*_with_overflow` op |

#### Constants
| Variant | Fields | Purpose |
|---------|--------|---------|
| `int_const` | `value, result` | Integer literal |
| `float_const` | `value, result` | Float literal |
| `string_const` | `string_id, result` | String literal pointer |
| `bool_const` | `value, result` | Boolean literal |
| `null_const` | `result` | Null literal (uncoerced / non-optional target) |
| `set_optional_null` | `result, type_id` | Set an optional to null (typed null); sets only `.has_value = 0` |
| `undefined_const` | `result, type_id` | Undefined literal |
| `enum_const` | `value, result, type_id, member_name_id` | Enum literal with member name |

#### Function Calls
| Variant | Fields | Purpose |
|---------|--------|---------|
| `call` | `callee, args_start, args_count, result` | Indirect function call |
| `call_direct` | `u32` (side-table slot) | Direct named function call; operands in `CallDirectData` |
| `tail_call` | `u32` (side-table slot) | Cross-function same-type tail; operands in `TailCallData` |
| `func_ref` | `name_id, module_id, result` | Function pointer reference |

#### Variadic (va_*)
| Variant | Fields | Purpose |
|---------|--------|---------|
| `va_start` | `va_list_temp, last_param_temp` | `va_start(vl, last_param)` |
| `va_arg` | `va_list_temp, type_id, result` | `result = va_arg(vl, TYPE)` |
| `va_end` | `va_list_temp` | `va_end(vl)` |

Emitted by the `@cVaStart`/`@cVaArg`/`@cVaEnd` builtin handler; the `va_list_temp` operand is resolved via `vaListArgTemp` (unwraps `&ident`/`ident` to a local temp). `@cVaStart` in a non-variadic function emits `error[3012]` (`ERR_3012_VARARGS_INVALID`), as does a variadic fn with zero fixed params. `LirFunction.is_variadic` is set by `lowerFn` from the `FnProto` fn-type `flags_packed` bit0.

#### Builtin I/O
| Variant | Fields | Purpose |
|---------|--------|---------|
| `builtin_put_char` | `value` | Emit `putchar(value)` to stdout |
| `builtin_stdout_write` | `ptr, len` | Emit `fwrite(ptr, 1, len, stdout)` |
| `builtin_stderr_write` | `ptr, len` | Emit `fwrite(ptr, 1, len, stderr)` |
| `builtin_get_char` | `result` | `result = getchar()` (result temp typed `TYPE_U8`) |
| `builtin_exit` | `value` | Emit `exit(value)`; sets `block_terminated = 1` (noreturn) |
| `builtin_sleep_ms` | `value` | Emit `#ifdef _WIN32` `Sleep(value)` `#else` `usleep(value * 1000)` `#endif` |

#### Builtin Console
| Variant | Fields | Purpose |
|---------|--------|---------|
| `builtin_console_clear` | — | Emit console clear (Win32 `FillConsoleOutput*`+home / ANSI `\x1b[2J\x1b[H`) |
| `builtin_console_gotoxy` | `x, y` | Emit cursor move (Win32 `SetConsoleCursorPosition(COORD)` / ANSI `\x1b[%d;%dH`) |
| `builtin_console_set_color` | `fg, bg` | Emit color set (Win32 `SetConsoleTextAttribute` / ANSI `\x1b[%s;%sm`) |

Emission is `#ifdef _WIN32 / #elif defined(__WATCOMC__) / #else` guarded (see 08_c89_emission.md). `@isWindows()` never produces LIR — it folds in sema/comptime.

#### Optional Handling
| Variant | Fields | Purpose |
|---------|--------|---------|
| `wrap_optional` | `value, result, type_id` | Wrap value in optional type |
| `unwrap_optional` | `value, result` | Extract payload from optional |
| `unwrap_optional_abi` | `value, result` | Extract payload from optional (ABI-stable) |
| `unwrap_optional_checked` | `value, result` | `-fsafe` guarded payload read (`if (!has_value) pal_trap();`) |
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
| `make_slice` | `ptr, len, result, type_id` | Construct a slice from pointer and length |

#### Type Conversions
| Variant | Fields | Purpose |
|---------|--------|---------|
| `int_cast` | `value, target, result` | Integer type conversion (unchecked) |
| `int_cast_checked` | `value, target, result, src_signed, src_width, dst_signed, dst_width` | `-fsafe` checked narrowing/sign-change cast |
| `width_wrap` | `value, result, result_type, width, is_signed` | Arbitrary-width mask/sign-extend normalization |
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

#### Safety / Poison
| Variant | Fields | Purpose |
|---------|--------|---------|
| `check_trap` | `cond, kind` | `-fsafe` runtime guard; the emitter traps when `cond` is false. `kind`: 2 = div/mod (zero or `MIN/-1`), 3 = shift count ≥ width, 4 = null-unwrap, 5 = index OOB, 6 = integer overflow, 7 = `@asyncInit` buffer smaller than `@asyncFrameSize` |
| `poison_init` | `result` | `-fsafe` `undefined` poison fill (byte-exact 0xAA) of the result storage |

#### Other
| Variant | Fields | Purpose |
|---------|--------|---------|
| `nop` | `void` | No operation (placeholder/tombstone) |

---

## lower.zig — LIR Lowerer `sf/src/lower.zig`

### LirLowerer Struct

| Field | Type | Description |
|-------|------|-------------|
| `ctx` | `*SemanticContext` | Shared compilation context (store, type registry, symbols, resolved types, coercions, diagnostics, async maps) |
| `func` | `*LirFunction` | Currently constructing LirFunction |
| `current_bb` | `u32` | Active basic block index |
| `temp_counter` | `u32` | Next temporary ID to allocate |
| `defer_stack` | `DeferActionArrayList` | Stack of deferred action descriptors |
| `loop_stack` | `LoopInfoArrayList` | Stack of enclosing loop descriptors |
| `switch_stack` | `SwitchInfoArrayList` | Stack of enclosing switch descriptors |
| `hoisted_temps` | `TempDeclArrayList` | Accumulated temporary declarations for function entry |
| `alloc` | `*Sand` | Allocator for dynamic data structures |
| `scope_depth` | `u32` | Current lexical scope depth |
| `block_terminated` | `u8` | Whether the current block has a terminating instruction |
| `suppress_fnref_ban` | `u8` | Suppresses the bare-function-reference ban while lowering `@asyncFrameSize`/`@asyncInit` target args |
| `module_id` | `u32` | Current module ID |
| `module_reg` | `*ModuleRegistry` | Module registry reference |
| `*_name_id` | `u32` | Pre-interned builtin names: `@intCast`, `@intToFloat`, `print`, `@ptrCast`, `@volatileCast`, `@ptrToInt`, `@intToPtr`, `@intFromPtr`, `@ptrFromInt`, `@fieldParentPtr`, `@enumToInt`, `@intToEnum`, `@as`, `@bitCast`, `@sizeOf`, `@alignOf`, `@offsetOf`, `@bitSizeOf`, `@bitOffsetOf`, `@cVaStart`/`@cVaArg`/`@cVaEnd`, `@putChar`/`@stdoutWrite`/`@stderrWrite`/`@getChar`/`@exit`/`@panic`/`@sleepMs`, `@isWindows`, `@consoleClear`/`@consoleGotoxy`/`@consoleSetColor`, `@asyncFrameSize`/`@asyncInit`/`@asyncResume`/`@asyncSuspend` |
| `local_decl_names`/`_src_names`/`_types`/`_temps` | `[*]u32` | Parallel arrays of local declarations (grown by `growLocalDecls`) |
| `local_decl_kinds`/`_is_capture` | `[*]u8` | Declared type kind / capture flag per local |
| `local_decl_scopes`/`_scope_nodes`/`_fn` | `[*]u32` | Scope depth, scope-node id, and owning function sequence per local |
| `local_decl_cap` | `usize` | Current capacity of the parallel arrays |
| `local_decl_name_map` | `U32ToU32Map` | Maps temp ID → name_id for debug info |
| `local_decl_count` | `usize` | Number of tracked local declarations |
| `scope_nodes` | `ScopeNodeArrayList` | Scope-parent chain |
| `cur_scope` / `pending_scope` | `u32` | Active / pending scope-node ids |
| `fn_seq` | `u32` | Monotonic per-function sequence number |
| `_fn_ret_type` / `_ctx_node_idx` / `_ctx_node_kind` | `u32` | Cached return type and diagnostic context |
| `capture_shadow` | `U32ToU32Map` | Maps captured names to disambiguated synthetic names |
| `synth_name_counter` | `u32` | Counter for synthetic name generation |
| `current_label` | `u32` | Active label name ID (0 = unlabeled), set from a `labeled_stmt` payload around its `child_0` recursion |

### Supporting Types

| Type | Fields | Purpose |
|------|--------|---------|
| `SemanticContext` | store, registry, symbol_tables, resolved_types, coercions, diag, has_symbols, enum_value_table, error_code_registry, call_arg_types, comptime_values, source_file_id, safe_checks, suspending_fns, frame_sizes, state_widths | Read-only view of the compilation state passed to the lowerer |
| `DeferAction` | `kind, ast_node, scope_depth` | Descriptor for deferred statement execution (`kind`: 0=defer, 1=errdefer) |
| `LoopInfo` | `header_bb, exit_bb, scope_depth, label_id, is_loop` | Loop context for break/continue resolution. `label_id` is the active label name ID from `current_label` at push time (0=unlabeled) |
| `SwitchInfo` | `exit_bb, scope_depth` | Switch context |
| `SrcIntent` | enum `value`, `null_src`, `error_src` | Classifies a source expression for coercion. `null_src` makes the null_literal branch emit `set_optional_null` directly on an `Opt_`-typed temp |
| `LocalBinding` | `temp, kind, tid` | Resolved local-variable binding |
| `ScopeNode` | `parent` | Scope-parent chain node |
| `CallInfo` | is_self, is_indirect, is_extern, call_conv, callee, module_id, args_start, args_count, result, return_type, call_block_idx, call_inst_idx | Tail-call candidate resolved by `findTailCall` |

### Key Functions

| Function | Signature | Description |
|----------|-----------|-------------|
| `lowererInit` | `(ctx, alloc) → LirLowerer` | Creates a LirLowerer with empty stacks; pre-caches the builtin name IDs |
| `emitInst` | `(self, LirInst)` | Appends an instruction into the current basic block; emits `width_wrap` for arbitrary-width `binary`/`unary`/`int_cast`/`int_cast_checked` results |
| `nextTemp` | `(self, type_id) → u32` | Allocates a temp ID and records it in `hoisted_temps` |
| `createBlock` | `(self) → u32` | Creates a BasicBlock, appends to `func.blocks` |
| `lowerExpr` | `(self, node_idx) → u32` | Lowers an AST expression to a LIR temp; applies the coercion wrapper from `coercions` |
| `lowerExprImpl` | `(self, node_idx) → u32` | Core expression-lowering dispatch |
| `lowerStmt` / `lowerStmtBody` | `(self, node_idx)` | Lower an AST statement / statement body |
| `lowerFn` | `(self, fn_node) → LirFunction` | Lower an entire function to LIR (entry `loop_header`, params, body, defers, `hoistTemps`) |
| `lowerModuleInit` | `(self, root_idx, mod_id) → LirFunction` | Synthesize a module's `__module_init` |
| `applyCoercion` | `(self, src_temp, coercion) → u32` | Apply a type coercion (widen, wrap, cast) |
| `applyNoneCoercion` | `(self, src_temp, coercion) → u32` | Handle the `none` kind (`null` → optional-null / null pointer) |
| `materializeInto` | `(self, src_temp, expected, intent, src_node) → u32` | Layer optional/error-union wrappers to match the expected type |
| `expandDefers` | `(self, target_depth, is_error_path, pop)` | Emit deferred statements at scope exit |
| `pushDefer` | `(self, kind, ast_node)` | Push a defer/errdefer action onto the stack |
| `hoistTemps` | `(self)` | Prepend `decl_temp` instrs to the entry block |
| `addLocalDecl` / `growLocalDecls` | `(self, name_id, type_id, temp, depth, is_capture)` | Register a local variable / grow the parallel arrays |
| `findLocalTemp` | `(self, name_id) → ?u32` | Look up a local temp by name |
| `lowerLValueAddr` | `(self, lv_node_idx, result_type) → u32` | Compute the address of an l-value (`ident_expr`, `index_access`, `deref`, `paren_expr`, `field_access` → `addr_of_field`) |
| `lowerAssignLValue` | `(self, lv_node_idx, value_temp, diag_node_idx)` | Emit a store to an l-value target |
| `lowerFieldStore` | `(self, fa_node_idx, value_temp, diag_node_idx)` | Store to a struct/union/slice/TU field, or `store_bitfield` for packed fields |
| `lowerPackedChainAnalyze` | `(self, node_idx, ...) → u8` | Analyze a nested packed-field chain (holder, bit offset, width, depth) |
| `emitSafeCheckDivMod` / `emitSafeCheckShift` / `emitSafeCheckIndex` / `emitOverflowTrap` | `(self, ...)` | Emit backend-neutral `-fsafe` `check_trap` guards |
| `emitArith` / `emitArithNeg` | `(self, ...)` | Emit checked or plain integer arithmetic depending on `safe_checks` |
| `lowerAppendSwitchCaseItem` | `(self, item_idx, prong_bb_id, cond_ty_id)` | Append one `SwitchCase` (literal, range, enum, error, or field-access value) |
| `findTailCall` / `zeroCallCFG` / `zeroChainInsts` / `hasOtherConsumers` | `(self, ...)` | TCO detection and dead-call-CFG elimination |
| `lowerDeclCallConvFlag` | `(store, decl_node) → u8` | Read the calling-convention flag from an extern decl's `FnProto` |

---

## AST → LIR Lowering Patterns

### Literals

| AstKind | LIR Output | Description |
|---------|-----------|-------------|
| `int_literal` | `int_const` → temp(`TYPE_INT_LIT`) | Integer constant value |
| `float_literal` | `float_const` → temp(`TYPE_F64`) | Float constant |
| `string_literal` | `string_const` → temp(ptr) | String pointer constant |
| `char_literal` | `int_const` → temp(`TYPE_U8`) | Character as u8 |
| `bool_literal` | `bool_const` → temp(`TYPE_BOOL`) | Boolean 0/1 |
| `null_literal` | `null_const` or `set_optional_null` | Untyped null. When the node's coercion routes to `SrcIntent.null_src` and the target chain contains an optional layer, the branch emits `set_optional_null` on a temp typed as that layer; the generic `null_const` path remains for uncoerced null / non-optional targets (pointer/fn). |
| `undefined_literal` | `undefined_const` → temp(`TYPE_UNDEFINED`) | Undefined value |
| `enum_literal` | `enum_const` / `int_const` / tagged-union init | Enum member; for a TU emits `int_const` tag + `assign_field` tag |
| `error_literal` | `int_const` → temp(`TYPE_I32`) | Error value as integer |

### Arithmetic & Logic

All binary operations follow the same pattern (with a comptime fold guard first):
```
if comptime_values[node_idx] → nextTemp(ftype); emitInst(.int_const{ cv }); return ctid
lowerExpr(lhs) → tid_lhs
lowerExpr(rhs) → tid_rhs
nextTemp(resolved_type) → tid_result
emitInst(.binary{ op, tid_lhs, tid_rhs, tid_result })
return tid_result
```

**Comptime fold guards.** The 10 binary op handlers (add/sub/mul/div/mod_op/bit_and/bit_or/bit_xor/shl/shr) and the 2 unary handlers (`negate`/`bit_not`) consult `ctx.comptime_values` **before** lowering operands. When a folded value is present, the temp type is taken from `resolvedTypeTableGet(node_idx)` with an `INT_LIT`/`UNDEFINED` → `TYPE_I32` remap, and an `int_const` is emitted instead of `binary`/`unary`. `bool_not` has no guard (never folds).

Under `-fsafe`, integer `+ - * <<` and unary negate route through `emitArith`/`emitArithNeg`: they emit the corresponding `add_with_overflow`/`sub_with_overflow`/`mul_with_overflow`/`shl_with_overflow`/`neg_with_overflow` value op plus an `overflow_flag` predicate and a `check_trap{kind=6}`. Under `-ffast`, or for non-integer/zero-width results, the plain `binary`/`unary` op is emitted. Division and shift additionally get `emitSafeCheckDivMod` (`check_trap{kind=2}`, including the signed `MIN / -1` case) and `emitSafeCheckShift` (`check_trap{kind=3}`) under `-fsafe`; `materializeShiftLhs` first gives an integer-literal left operand a typed temp so the shift bound applies.

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
| `cmp_lt` / `cmp_le` / `cmp_gt` / `cmp_ge` | `BIN_LT` / `BIN_LE` / `BIN_GT` / `BIN_GE` |

The `BIN_*` constant set also includes the wrapping/saturating ops `BIN_WADD`, `BIN_WSUB`, `BIN_WMUL`, `BIN_SADD`, `BIN_SSUB`, `BIN_SMUL`, `BIN_SSHL`; the unary set includes `UN_WNEG`. Arbitrary-width results additionally get a `width_wrap` op from `emitInst` (`maybeEmitWidthWrap`).

**Short-circuit `bool_or`** produces 3 blocks (rhs_bb, true_bb, done_bb): if lhs is true → true_bb emits `bool_const(1)` → done_bb; if lhs is false → rhs_bb evaluates rhs → assign result → done_bb.

**Short-circuit `bool_and`** produces 3 blocks (rhs_bb, false_bb, done_bb): if lhs is true → rhs_bb evaluates rhs → assign; if lhs is false → false_bb emits `bool_const(0)` → done_bb.

### Unary Operations

| AstKind | Pattern |
|---------|---------|
| `negate` | `.unary{ UN_NEG }` (or `neg_with_overflow` under `-fsafe`) |
| `bool_not` | `.unary{ UN_NOT }` |
| `bit_not` | `.unary{ UN_BNOT }` |

### Variables

| AstKind | Pattern |
|---------|---------|
| `ident_expr` | Lookup via `findLocalTemp()` or the symbol table → `load_local` or `load_global`. For fn types, `func_ref`; for modules, a diagnostic warning; for type aliases, emits a temp. |
| `var_decl` | `nextTemp(decl_type)` → `decl_local` → optionally `store_local` + `assign` from the init expression. Arrays init'd via `array_init` lowering. |

### Compound Assignments

All `*_assign` variants follow this pattern:
```
lowerExpr(lhs) → lhs_val
lowerExpr(rhs) → rhs_val
nextTemp(result_type) → op_r
emitInst(.binary{ op, lhs_val, rhs_val, op_r })
lowerCompoundLValueStore(self, node_idx, lhs_val, op_r)
```

Covers: `add_assign`, `sub_assign`, `mul_assign`, `div_assign`, `mod_assign`, `shl_assign`, `shr_assign`, `and_assign`, `xor_assign`, `or_assign`.

### Plain Assignment

```
lowerExpr(rhs) → src
lowerAssignLValue(lhs, src, diag_node)
```
`lowerAssignLValue` handles: `ident_expr` → `store_local` / `store_global` / `assign`; `index_access` → `assign_index`; `field_access` → `lowerFieldStore`; `deref` → `store`; `paren_expr` → recurse.

### Field Access

Two modes:
1. **Compile-time resolved**: `TypeAlias.field` → `emitTaggedUnionInit` (for a TU), `enum_const` (for an enum), or an error-set member.
2. **Runtime**: `lowerExpr(base)` → resolve base type → `.load_field{ field_id }` for struct/union/TU. Slice `.len` → `SLICE_FIELD_LEN`, slice `.ptr` → `SLICE_FIELD_PTR`.

### Field Store

`lowerFieldStore` is dispatched from `lowerAssignLValue` for `field_access` lvalues. Base handling:
- **Index base** (`arr[i].field = v`): computes a POINTER base (`ptr_temp + idx_temp` via `BIN_ADD`, typed `*elem`) and emits `store_field{ base = ptr, field_id }`; the C emitter renders `ptr->field = v;`. A pointer-to-array base uses `load_index{decay=1}` to take `&(*ptr)[idx]` instead of a row-scaled add.
- **Nested lvalue base** (`o.inner.a = v`; base is `field_access`/`deref`/`paren_expr`): routes through `base_temp = lowerLValueAddr(child_0, *BaseTy)` (or `lowerExpr` when the base is itself pointer-typed) so the outer `store_field` stores through the pointer. This fixes the dropped write-back that a plain `lowerExpr` copy would cause.
- **Ident / pointer-var base** (`o.tag = 1`, `ptr.x = v`): `base_temp = lowerExpr(child_0)` — for an aggregate local this is the local's own temp; for a pointer var it is the pointer value.
- **Packed struct/union member**: when the base resolves to a packed struct or packed union, the store emits `store_bitfield{ base, value, bit_offset, bit_width }` from the field's packed bit layout. Assigning a whole packed-struct value to a nested packed-struct field is a located `error[3000]` (bit-slice store unsupported).

### Packed Bitfield Access

Nested packed-field chains (`a.b.c` where `a`/`b` are packed) are analyzed by `lowerPackedChainAnalyze` (up to 16 levels): it walks the `field_access` chain, finds the first packed-struct/packed-union container, and sums the packed bit offsets down to the leaf. A read emits `load_bitfield{ base, result, name_id, bit_offset, bit_width }`; a store emits `store_bitfield`. The leaf width comes from the registry's packed-bitfield table. Reading or writing a whole packed-struct value is rejected with `error[3000]`.

### Index Access

```
lowerExpr(base) → base_temp
maybeExtractSlicePtr() → ptr_temp (extracts `.ptr` field from a slice)
lowerExpr(index) → idx_temp
nextTemp(elem_type) → tid
emitInst(.load_index{ ptr_temp, idx_temp, tid, decay })
```
Under `-fsafe`, `emitSafeCheckIndex` emits a `check_trap{kind=5}` (`idx < len`) before a user load/store: the length is the static array length when known (including via a pointer-to-array or a field of a struct/union container), otherwise a runtime `SLICE_FIELD_LEN` load from the original slice base. `[*]T`/scalar pointers are unchecked; a signed index wider than `usize` additionally requires `idx >= 0`. `decay=1` marks a pointer-to-array base whose element address must be `&(*base)[j]`.

### Dereference / Address-Of

```
deref:   lowerExpr(ptr) → ptr_temp; nextTemp(pointee_type) → tid; emitInst(.load{ ptr_temp, tid })
addr_of: lowerLValueAddr(lvalue) → tid
```
`lowerLValueAddr` dispatches by l-value kind: ident → `.addr_of`; `index_access` → pointer+index via `BIN_ADD` (or `load_index{decay=1}` for a pointer-to-array); `deref` → reuses the inner expression; `paren_expr` → recurse; `field_access` → `.addr_of_field` (address of a field within the base's address, rendered `result = &base->f_N;`). A module global reached through a module alias (`&mid.leaf.counter`) resolves to `load_global` + `addr_of`. An unsupported l-value kind reaches `iceAddrOfLValueUnsupported` (`error[3043]`).

### Array Init / Struct Init / Tuple Literal

**Array init**: `nextTemp(array_type)`; per element `lowerExpr(element)` → `int_const(index)` → `assign_index`.

**Struct init**: `nextTemp(struct_type)`; per field `lowerExpr(val)` then `assign_field`. A tagged-union target emits `int_const(tag_index)` + `assign_field(TU_FIELD_TAG)` and optionally `assign_field(TU_FIELD_PAYLOAD)`; a `struct_type` target emits `assign_field(field_index, val)`; a `union_type` target scans the union's members and emits `assign_field(member_index, val)`. `undefined`-initialized array-typed fields are skipped (no dead `undefined_const` temp, no `assign_field`).

**Tuple literal**: single-element tuples forward to `lowerExpr(ec[0])`; empty tuples return `TYPE_VOID`.

### Function Calls

**Direct call** (callee resolves to a fn symbol):
```
Reserve args_start temps
for each arg: lowerExpr(arg) → applyCoercion → .assign to args slot
nextTemp(return_type) → result
emitInst(.call_direct{ side-table slot })   // CallDirectData: name_id, module_id,
                                            // args_start, args_count, result,
                                            // return_type, is_extern, call_conv
```

**Indirect call** (callee is pointer-to-fn):
```
lowerExpr(callee) → callee_temp
Reserve args
for each arg: lowerExpr → .assign
emitInst(.call{ callee_temp, args_start, args_count, result })
```

**Cross-module call** (field access on a module): resolves the symbol and emits `call_direct` with the target `module_id`. A cross-module `pub const` whose init is an `int_literal`/`char_literal`/`float_literal` folds to `int_const`/`float_const` at the declared type at the ref site; other consts use `load_global`. The callee's calling-convention flag is captured by `lowerDeclCallConvFlag` into `CallDirectData.call_conv`.

### Builtins

`print()` is special-cased: it emits `print_str` for each format-string segment and `print_val` per argument.

`@ptrCast`/`@volatileCast` emit `ptr_cast`; `@intCast` emits `int_cast` or, under `-fsafe` when a narrowing or sign-change check is required, `int_cast_checked`; `@intToFloat` emits `int_to_float`; `@ptrToInt`/`@intFromPtr` emit `ptr_to_int`; `@intToPtr`/`@ptrFromInt` emit `int_to_ptr`; `@bitCast` resolves the target type and emits `int_cast`; `@enumToInt` forwards the value as-is; `@intToEnum`/`@as` emit `int_cast` to the target. `@sizeOf`/`@alignOf`/`@offsetOf`/`@bitSizeOf`/`@bitOffsetOf` resolve through the comptime-values table (ICE otherwise). `@fieldParentPtr` computes the outer pointer via `ptr_to_int`/`sub`/`int_to_ptr`.

**Variadic builtins**: `@cVaStart`/`@cVaArg`/`@cVaEnd` emit `va_start`/`va_arg`/`va_end`; `@cVaStart` in a non-variadic function emits `error[3012]`, as does a variadic function with zero fixed params.

**Core I/O builtins**: `@putChar`/`@stdoutWrite`/`@stderrWrite`/`@getChar`/`@exit`/`@sleepMs` emit the six `builtin_*` ops; `@exit` sets `block_terminated = 1` (noreturn). `@panic` emits the `"panic: "` prefix, the message, a newline, and a `trap`, and marks the block terminated. **Console builtins**: `@consoleClear`/`@consoleGotoxy`/`@consoleSetColor` emit the three `builtin_console_*` ops. `@isWindows()` folds via the comptime-values path and never produces a runtime op. There are no socket builtins; networking is the `std_net` extern surface (see 10_c_runtime).

**Async builtins**: `@asyncFrameSize` resolves the callee's published frame size and emits an `int_const`. `@asyncInit` initializes the caller-provided Context header (`used = 0`, sticky `oom = 0`), optionally emits a `-fsafe` `check_trap{kind=7}` when the buffer's pointee array size is compile-time known and smaller than the frame, then calls the shared frame-init helper (`async_state_machine.asyncEmitFrameInit`). `@asyncResume` loads the frame's step word, emits a `-fsafe` `check_trap{kind=4}` (null-unwrap), converts it to a generic step fn pointer, and emits an indirect `call` with the frame and the optional argument. `@asyncSuspend` lowers to a null `?*void` (the suspension itself is realized by the async transform).

### Control Flow

#### If Statement
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

A comptime-known condition (from `comptime_values`, guarded against `if_capture`) lowers ONLY the active branch — no `branch` inst and, for `if_stmt`, no then/else/join blocks. This is what makes `if (@isWindows()) {…} else {…}` emit only the active branch.

#### If Expression
Same pattern as the if-statement but with a `result` temp that both branches assign into.

#### While Statement
```
createBlock(cond_bb, body_bb, exit_bb, cont_bb)
push LoopInfo{ header=cont_bb, exit=exit_bb }
.jump(cond_bb)
→ cond_bb: lowerExpr(cond) → check_optional? → .branch{ cond, body_bb, exit_bb }
→ body_bb: bindCapture? → lowerStmtBody(body) → .jump(cont_bb) (if not terminated)
→ cont_bb: lowerStmtBody(incr) → .jump(cond_bb) (if not terminated)
→ exit_bb: pop loop_stack
```

#### For Statement

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

#### Switch Expression
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

**Switch case collection** (`lowerAppendSwitchCaseItem`): each non-else prong's `case_ec` children are walked and a `SwitchCase{ value, target_bb }` is appended per case node. The case-value extraction handles:
- `int_literal` / `char_literal` → the literal's u64 value from `AstStore.int_values` at the node's payload index.
- `range_inclusive` / `range_exclusive` → expanded to individual case values (only when both bounds are int/char literals and the count is ≤ 16384).
- `enum_literal` → `enum_value_table[case_node]` ordinal via `u32ToU32MapGet`, falling back to the raw payload.
- `error_literal` → `error_code_registry` dense code via `u32ToU32MapGetOrAddDense`, falling back to the `enum_value_table` ordinal.
- `field_access` → an enum member value or a tagged-union variant index, resolved against the switch condition's type.

The `else` prong is identified by `flags` bit0.

#### Return / Break / Continue
```
return:   expandDefers(0, 0, 0) → lowerExpr(value) → .ret(val) or .ret_void
break:    expandDefers(exit_scope, 0, 0) → .jump(exit_target)
continue: expandDefers(cont_scope, 0, 0) → .jump(header_target)
```

**Labeled break/continue:** `break :label` / `continue :label` read `node.payload` as `label_id` (0 = unlabeled). The unlabeled path keeps the top-of-stack jump; the labeled path scans `loop_stack` top-down for `LoopInfo.label_id == label_id` and jumps to that loop's exit/header. `LoopInfo.label_id` is stamped from `self.current_label` at all three loop-push sites, and `current_label` is set from a `labeled_stmt` node's payload in `lowerStmt` with save/restore around the `child_0` recursion. `break :label` out of a labeled **non-loop** block is unsupported — the break handler searches only `loop_stack`.

### Optional Unwrapping

`bindOptionalCapture` takes an optional value, emits `unwrap_optional` (or `unwrap_optional_checked` under `-fsafe` for a non-void payload) to get the payload, then `decl_local` to bind the capture name.

### Error Union Handling

#### Try Expression
```
lowerExpr(inner) → inner_temp
.check_error(inner_temp) → is_err
.branch{ is_err, err_bb, ok_bb }
→ err_bb: expandDefers(0, 1, 0) → .ret(inner_temp) or rewrap → .ret(rewrapped)
→ ok_bb: .unwrap_error_payload(inner_temp) → payload → .jump(join_bb)
→ join_bb: return payload
```

#### Catch Expression
```
lowerExpr(lhs) → lhs_temp
.check_error → .branch{ is_err, err_bb, ok_bb }
→ err_bb: .unwrap_error_code → bind capture → lowerExpr(handler) → materializeInto → .assign(join_temp) → .jump(join_bb)
→ ok_bb: .unwrap_error_payload → .assign(join_temp) → .jump(join_bb)
→ join_bb: return join_temp
```

#### OrElse Expression
Same structure as catch but for `?T`:
```
lowerExpr(lhs) → lhs_temp
.check_optional → .branch{ has_val, ok_bb, null_bb }
→ null_bb: lowerExpr(default) → materializeInto → .assign(join_temp) → .jump(join_bb)
→ ok_bb: .unwrap_optional → .assign(join_temp) → .jump(join_bb)
→ join_bb
```

### Slice Expression
```
lowerExpr(base) → base_temp
Extract ptr/len from array or slice: .load_field(SLICE_FIELD_PTR/LEN) or .ptr_cast(array→manyptr) + int_const(len)
If start: .binary(ADD, ptr, start) → offset_ptr
If end: .binary(SUB, end, start) → new_len
emitInst(.make_slice{ ptr, len, result, type_id })
```

### Block Expression
```
nextTemp(TYPE_VOID)
lowerStmtBody(node)  // recurses into block children
```

---

## Defer/Errdefer Expansion

**Push**: `pushDefer(kind, ast_node)` appends a `DeferAction{ kind(0=defer, 1=errdefer), ast_node, scope_depth }` to `defer_stack`.

**Expand**: `expandDefers(target_depth, is_error_path, pop)` iterates the stack from the top:
- `defer` (kind=0): always emits the body.
- `errdefer` (kind=1): emits only when `is_error_path != 0`.

At scope-termination exits (`lowerStmtBody` block exit, `lowerStmt` block exit, `lowerFn` end) `pop=1` removes the action after emitting — preserving scope-lifetime semantics (a defer never re-emits after its scope closes). At internal exits (`return_stmt`, `break_stmt`, `continue_stmt`, try-error path) `pop=0` leaves the action on the stack so the body is inlined at **every** runtime exit while the scope is live.

Called at:
- Scope exit in `lowerStmtBody` (target_depth = `self.scope_depth`, is_error_path = 0)
- `return_stmt` (target_depth = 0, is_error_path = 0)
- `break_stmt`/`continue_stmt` (target_depth = targeted scope + 1, is_error_path = 0)
- `try_expr` error path (target_depth = 0, is_error_path = 1)

---

## Temp Hoisting

`hoistTemps()` runs at the end of `lowerFn()`. It creates a new `LirInstArrayList`, appends a `decl_temp` for each temp in `hoisted_temps` (skipping `TYPE_VOID`), appends all existing entry-block instructions, and replaces the entry block's instruction list. All temporaries are therefore declared at function entry before any control flow — the IR has no SSA phi nodes, so every temp is effectively an `alloca`.

---

## TCO (Tail Call Optimization)

The lowerer implements **tail-call elimination for self-recursion** and a **`tail_call` LIR variant** for same-type cross-function tails.

### `loop_header` injection at entry block

Every function gets `loop_header(0)` as the first entry-block instruction. `lowerFn` emits it immediately after `self.current_bb = createBlock(self)`. The entry block id is always 0 (nothing allocates a block before `lowerFn`'s entry `createBlock`). `hoistTemps` then prepends the `decl_temp` instructions to block 0, so the final entry-block order is `decl_temp*, loop_header, body` — the C89 emitter's `.loop_header` arm emits `z_bb_0:` there, landing the label after every temp/local declaration.

### `findTailCall`

A bounded **5-hop def-use walk** from the return temp (`hops < 5`). Each hop scans all blocks/instructions for the inst whose result is the current temp:
- `.call_direct` → `CallInfo{ is_self = (name_id == func.name_id and module_id == func.module_id), is_indirect=0, ... }` from the side-table slot.
- `.call` (indirect) → `CallInfo{ is_self=0, is_indirect=1, is_extern=0, callee, return_type = TYPE_UNDEFINED, ... }`.
- `.unwrap_error_payload` / `.wrap_error_ok` / `.wrap_error_err` with the matching result → follow `.value`; this lets `return try self(...)` (ok-path payload) and `return <coerced>` (wrap chain) resolve back to the underlying call. `.unwrap_error_code` returns null (the error path is not a tail).

A hop that finds no defining inst returns `null`.

### `return_stmt` TCO

After `expandDefers` and `lowerExpr`, guarded by `func.is_extern == 0`:
- **Self-recursion** (`is_self == 1` and `args_count == params.len`): `zeroCallCFG` first, then param-rebind assigns `param_temp_i = args_start + i` for every param, then `jump` back to the entry `loop_header`, then `block_terminated = 1` (suppressing the plain `ret`).
- **Cross-function** (`is_self == 0` and `ci.return_type == func.return_type`): `zeroCallCFG`, then emit `tail_call` from `CallInfo`, `block_terminated = 1`. The type-equality guard means type-changing coercions fall back to the plain `ret`; indirect calls (`return_type == TYPE_UNDEFINED`) never cross-TCO.
- Params mismatch (`args_count != params.len`) or an extern fn → normal `ret` (defensive).

`hasOtherConsumers` is a **defensive guard** called before `zeroCallCFG` in both TCO branches. It scans all blocks for any instruction referencing the call result that is not a recognized chain consumer (`call_direct`, `call`, the unwrap/wrap/check family, `ret`, `nop`); if one exists, TCO is skipped. No valid Z98 pattern triggers it today.

### try-CFG elimination

When the tail resolves through a try, the dead call CFG is zeroed out: `zeroCallCFG` nops the defining call, the following `check_error`/`check_optional` if present, and the following `branch` if present; `zeroChainInsts` nops the intermediate `unwrap_error_payload`/`unwrap_error_code`/`wrap_error_ok`/`wrap_error_err` insts that read the nop'd call result. Rebind assigns / `tail_call` are emitted into the **call block**, then the original current block is restored. `block_terminated = 1` also suppresses the join-block `ret`.

### Statement-form if/switch; defer-after-TCO ordering

Per-branch `return_stmt` sites inside `if_stmt`/`switch_stmt` bodies reach this same handler and get TCO automatically. Expression-form `return if/switch (...)` (join-temp results) is out of scope: the walk starts at the return temp and cannot resolve a join temp to one call without full dataflow, so those fall back to plain `ret`.

`expandDefers(self, 0, 0, 0)` is called once at the top of `return_stmt`, before any TCO decision. The self-TCO branch then nops the freshly-emitted defer instructions when the defer stayed in the same block; cross/non-TCO branches preserve them. The defer fires once at terminal exit via `expandDefers(self, 0, 0, 1)` at the end of `lowerFn`.

---

## Type Coercions

`applyCoercion` dispatches to `materializeInto` and the specific cast instructions:

| CoercionKind | LIR Pattern |
|--------------|-------------|
| `none` | `applyNoneCoercion` — rewrites `null` → optional-null (`set_optional_null`) or `int_const(0)` for pointer/fn targets |
| `wrap_optional_null` | `materializeInto(src, target, null_src, node)` → `set_optional_null`; src is the `?T`-typed temp produced by the null_literal branch, so `materializeInto` short-circuits on `src_ty == expected` or wraps into outer error-union layers |
| `wrap_optional` | `materializeInto(src, target, intent, node)` → `wrap_optional` |
| `wrap_error_success` | `materializeInto(src, target, intent, node)` → `wrap_error_ok` |
| `wrap_error_err` | `materializeInto(src, target, error_src, node)` → `wrap_error_err` |
| `int_widen` | `int_cast` |
| `float_widen` | `float_cast` |
| `int_literal_coerce` | `int_cast` |
| `ptr_to_optional_ptr` | `materializeInto(src, target, intent, node)` → `wrap_optional` |
| `array_to_slice` | `int_const(len)` + `make_slice{ ptr, len }` |
| `array_to_many_ptr` | `ptr_cast` |
| `slice_to_many_ptr` | `ptr_cast` |
| `string_to_slice` | `int_const(len)` + `make_slice{ ptr, len }` |
| `string_to_many_ptr` | `ptr_cast` |
| `string_to_ptr` | `ptr_cast` |
| `const_qualify` | No-op (identity) |
| `unwrap_optional` | No-op (identity) |

`materializeInto(src_temp, expected, intent, src_node)` is the general mechanism: given a source temp and an expected type, it walks the type hierarchy (up to 8 optional/error-union layers) and emits `set_optional_null`/`wrap_optional`/`wrap_error_ok`/`wrap_error_err`, optionally preceded by an inner `int_cast`/`float_cast`.

**Null construction.** For a `null_literal` whose coercion routes to `SrcIntent.null_src` (`wrap_optional_null`/`wrap_optional`/`wrap_error_success`) with an optional layer in the target chain, the null_literal branch walks the coercion target chain (`optional_type` → layer; `error_union_type` → payload, max 8) and emits `set_optional_null` directly on a temp typed as that optional layer — instead of a dead `null_const` temp typed `int`. `materializeInto` then short-circuits on `src_ty == expected` for a plain `?T`, or wraps the `?T` temp into outer error-union layers for `E!?T`. Non-optional-target null (pointer/fn, no optional layer) still uses the `null_const` path.

---

## Control Flow Graph Construction

Blocks are created lazily via `createBlock()`. Every branch/switch terminator sets `is_terminated = 1` on the source block. The CFG is implicit in the block indices stored in jump/branch instructions. No explicit edge lists or dominator trees are built at the LIR level.

---

## LIR Optimization Pass — `sf/src/lir_opt_pass.zig`

Runs per function in the emission phase (`c89_emit.zig` `emitModule`/`emitModuleFile`), immediately after the spill fault-in and before the emitter walks the function. It rewrites the in-memory `LirFunction` in place, deterministically. Dead-temp deletion is NOT re-implemented here: the emission-side DCE (`emitHoistedDecls`) already removes unused temps — this pass only makes copies and constant ops disappear so that DCE has less to keep.

Entry point `lirOptRun(alloc, reg, lir_fn)` builds per-temp scratch arrays sized by `maxTempOf` (the max `hoisted_temps` id), then runs, in order:

1. `copyPropagate` — an `assign` copy (`dst = src`, `name_id == 0`, identical scalar/pointer types) whose dst is read exactly once at an explicit operand slot in the same block after the copy, whose src is single-use and defined by a PURE op, and neither temp is address-taken / param / `decl_local`-bound / `load_global`-aliased, is removed by renaming the consumer's operand to `src` and tombstoning the copy with `.nop`. Call/`call_direct`/`tail_call` argument runs and side-table operands are excluded — the arg ids are a contiguous temp-id run the pass cannot rewrite per-slot.
2. `runConstFold` — PURE `binary`/`unary` ops whose value operands are all `int_const` fold to one `int_const` (comparisons to `bool_const`) at the result type's width with two's-complement semantics; `int_cast` folds only when the value is exactly representable at the target. Checked casts (`int_cast_checked`) are skipped.
3. `coalesceArgCopies` — argument-fill copies that survive copy-prop are collapsed by re-targeting the arg's PURE single-use producer to write the slot id directly and tombstoning the fill (identical TypeId, both single-use, scalar/pointer move, same-block producer < fill < call-reader).
4. `coalesceJoinCopies` — per-arm join/merge fills collapse the same way: re-target the arm's PURE single-use producer to the join temp and tombstone the arm fill.
5. `computeNestMetadata` — records per temp an inline-candidate bit (`lirOptNestCandidate`) and expression-tree depth (`lirOptNestDepthOf`), plus def/read locations (`lirOptNestDefLoc`/`lirOptNestConsLoc`). The emitter (not this pass) enforces the C90 nesting cap and the C-shape rules. A memory-reading PURE def (the load family) is only a candidate when its single read is in the same block with no ORDERED inst between def and read; register/const-only defs have no such window.

| Constant | Value | Purpose |
|----------|-------|---------|
| `kCopyPropMaxIter` | 128 | Iteration cap for the copy-prop / coalesce fixpoint loops |
| `kEmitNestDepthCap` | 32 | C90 expression-nesting cap (emitter-enforced) |

Purity table (`defInfoPure`): `binary`, `unary`, the const family (`int_const`/`float_const`/`bool_const`/`null_const`/`string_const`/`undefined_const`/`enum_const`/`set_optional_null`), the casts (`int_cast`/`int_cast_checked`/`width_wrap`/`float_cast`/`ptr_cast`/`int_to_float`/`int_to_ptr`/`ptr_to_int`), `make_slice`, `addr_of`/`addr_of_field`, `func_ref`, the optional/error wrappers, the load family, and the overflow ops. Everything else is ORDERED.

---

## LIR Streaming — `sf/src/lir_stream.zig`

`LirStream` wraps a `SpillStore` plus a 512-byte path buffer and a running `write_offset`. `phase_LIRLowering` calls `lirStreamBeginWrite(path, alloc)` once, then `lirStreamAppend(fn)` per lowered function, returning a `LirSlot { module_id, disk_offset, byte_len }`. `phase_C89Emission` calls `lirStreamBeginRead(alloc)` and faults each function in with `lirStreamReadFunction(slot, dst)` before emission; `lirStreamEndRead()` closes the stream.

Serialization is a raw little-endian byte dump of the function's scalar payloads (u32/u64/f64/u8 ids — no pointers/slices), so the dump is byte-preserving: `lirStreamAppend` writes the header fields (`name_id`, `module_id`, `return_type`, `is_extern`, `is_pub`, `is_variadic`, `call_conv`, `poison_uninit`, `is_export`), the seven counts, then the raw arrays (`params`; per-block `{id, is_terminated, 3 pad, insts}`; `hoisted_temps`; `switch_cases`; `side_table`; and the `temp_variant_sub_field` keys/values/occupied). `lirStreamReadFunction` reconstructs each array with exact-length allocations into the caller's `Sand` and verifies the computed `expected_len` against `slot.byte_len`, panicking on mismatch (`"S-LIR byte_len mismatch on fault-in read"`).

In Ram backend mode, `lirStreamBeginRead` does not re-open or truncate: the write-phase buffer already holds all bytes, so it only resets the read cursor.

---

## Spill Store — `sf/src/spill_store.zig`

`SpillStore` is an offset-addressed byte spill over a Disk (`pal.streamOpen`/`streamSeek`/`streamWrite`/`streamRead`/`streamClose`) or Ram (arena-backed growable byte buffer) backend. Each producer/consumer treats the spill as byte-addressed opaque data, so byte identity holds in both modes.

| Constant / type | Value | Purpose |
|-----------------|-------|---------|
| `SPILL_COUNT` | 6 | Number of spill streams |
| `SPILL_SEEK_MAX` | `0x7FFFFFFF` | Uniform i32-seek guard |
| `SpillBackend` | `disk = 0`, `ram = 1` | Per-spill backend |
| `SpillId` | `s_ast=0`, `s_lir=1`, `s_hash=2`, `s_res=3`, `s_side=4`, `s_extra=5` | Spill identifiers |

The backend is selected once per spill from the immutable per-spill flag prefix (`spillBackendFor`); the CLI `-s<N>` flag calls `spillSetLevel(N)` to set indices `< N` to Ram (all-Disk by default). Ram buffers grow via `sandTryReallocInPlace` first, else a fresh allocation plus copy. `spillSeek`/`spillWriteAt`/`spillReadAt` enforce the i32 seek limit and panic on a null Disk handle; a Ram read past the logical high-water panics (parity with a Disk short read). `SpillStore` fields: `backend`, `opened`, `handle` (Disk `FILE*`), `buf`/`cap`/`len`/`cur` (Ram buffer, capacity, logical high-water, last I/O end), `alloc` (arena backing the Ram buffer).

---

## Debugging

The lowerer emits marker output gated on the `--markers` flag via `pal.markerWrite()`/`pal.markerWriteInt()`, which check `g_markers_enabled` (`sf/src/pal.zig`). Run `zig1 --markers --dump-c89 <file>` and capture stderr to see the per-node tracing. **The `--dump-lir` flag is DEAD**: its flag string is declared but never matched in `parseArgs`, so nothing reads it anywhere in the pipeline.

| Marker | Meaning |
|--------|---------|
| `LEX:n<idx>k<kind>` | Entering `lowerExpr` (node + kind) |
| `CT:t<type>r<tid>` | Creating a temp with type_id (`nextTemp`) |
| `NXT:i<idx>k<kind>t<tid>` | `nextTemp` warning for void/undefined type |
| `FNL:<name_id>` | Function lowering — one per lowered `fn_decl` |
| `D3HT:<tid,type>\|...` | Hoisted temps dump — one per fn, entry count = total temp count |
| `CEM:n<idx>` | Coercion check — coercion missing (per `lowerExpr`) |
| `CEP:n<idx>k<kind>` | Coercion check — coercion present, kind emitted |
| `COE`/`CO2` | Compound-assign coercion sites |
| `GBL`, `BB`, `ILR`, `STK`, `BLC` | Global context / struct init / int literal / statement kind / block child tracing |

All markers use `pal.markerWrite()` and output to stderr only when `--markers` is enabled.

