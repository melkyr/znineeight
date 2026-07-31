# LIR Lowering Layer

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

### All 54 LirInst Variants `sf/src/lir.zig:22`

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
| `null_const` | `result` | Null literal |
| `set_optional_null` | `result, type_id` | Set optional to null (typed null) |
| `undefined_const` | `result, type_id` | Undefined literal |
| `enum_const` | `value, result, type_id, member_name_id` | Enum literal with member name |

#### Function Calls
| Variant | Fields | Purpose |
|---------|--------|---------|
| `call` | `callee, args_start, args_count, result` | Indirect function call |
| `call_direct` | `name_id, module_id, args_start, args_count, result, return_type, is_extern` | Direct named function call |
| `func_ref` | `name_id, module_id, result` | Function pointer reference |

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

### Supporting Types

| Type | Fields | Purpose |
|------|--------|---------|
| `DeferAction` | `kind, ast_node, scope_depth` | Descriptor for deferred statement execution (`kind`: 0=defer, 1=errdefer) |
| `LoopInfo` | `header_bb, exit_bb, scope_depth, label_id` | Loop context for break/continue resolution |
| `SwitchInfo` | `exit_bb, scope_depth` | Switch context |
| `SrcIntent` | enum `value`, `null_src`, `error_src` | Classifies source expression for coercion |

### Key Functions

| Function | Signature | Description |
|----------|-----------|-------------|
| `lowererInit` | `(ctx, alloc) → LirLowerer` `sf/src/lower.zig:256` | Creates LirLowerer with empty stacks, pre-caches builtin name IDs |
| `emitInst` | `(self, LirInst)` `sf/src/lower.zig:321` | Appends instruction into current basic block |
| `nextTemp` | `(self, type_id) → u32` `sf/src/lower.zig:325` | Allocates temp ID, records in hoisted_temps |
| `createBlock` | `(self) → u32` `sf/src/lower.zig:364` | Creates new BasicBlock, appends to func.blocks |
| `lowerExpr` | `(self, node_idx) → u32` `sf/src/lower.zig:446` | Lower AST expression to LIR temp; applies coercion wrapper |
| `lowerExprImpl` | `(self, node_idx) → u32` `sf/src/lower.zig:1032` | Core expression lowering dispatch |
| `lowerStmt` | `(self, node_idx)` `sf/src/lower.zig:3197` | Lower AST statement to LIR |
| `lowerFn` | `(self, fn_node) → LirFunction` `sf/src/lower.zig:4092` | Lower entire function to LIR |
| `applyCoercion` | `(self, src_temp, coercion) → u32` `sf/src/lower.zig:3991` | Apply type coercion (widen, wrap, cast) |
| `expandDefers` | `(self, target_depth, is_error_path)` `sf/src/lower.zig:3922` | Emit deferred statements at scope exit |
| `pushDefer` | `(self, kind, ast_node)` `sf/src/lower.zig:3914` | Push a defer/errdefer action onto stack |
| `hoistTemps` | `(self)` `sf/src/lower.zig:3942` | Prepend decl_temp instrs to entry block |
| `materializeInto` | `(self, src_temp, expected, intent) → u32` `sf/src/lower.zig:852` | Layer type wrappers (optional/error-union) to match expected type |
| `addLocalDecl` | `(self, name_id, type_id, temp, depth)` `sf/src/lower.zig:470` | Register a local variable |
| `findLocalTemp` | `(self, name_id) → ?u32` `sf/src/lower.zig:940` | Look up local temp by name |
| `lowerLValueAddr` | `(self, lv_node_idx, result_type) → u32` `sf/src/lower.zig:640` | Compute address of l-value |
| `lowerAssignLValue` | `(self, lv_node_idx, value_temp, diag_node_idx)` `sf/src/lower.zig:694` | Emit store to l-value target |

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
| `null_literal` | `null_const` → temp(TYPE_NULL) | Untyped null |
| `undefined_literal` | `undefined_const` → temp(TYPE_UNDEFINED) | Undefined value |
| `enum_literal` | `enum_const` or `int_const` or tagged-union init | Enum member; for TU emits `int_const` tag + `assign_field` tag |
| `error_literal` | `int_const` → temp(TYPE_I32) | Error value as integer |

### Arithmetic & Logic

All binary operations follow the same pattern:
```
lowerExpr(lhs) → tid_lhs
lowerExpr(rhs) → tid_rhs
nextTemp(resolved_type) → tid_result
emitInst(.binary{ op, tid_lhs, tid_rhs, tid_result })
return tid_result
```

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
| `negate` | `.unary{ UN_NEG }` |
| `bool_not` | `.unary{ UN_NOT }` |
| `bit_not` | `.unary{ UN_BNOT }` |

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

### Field Access `sf/src/lower.zig:1740`

Two modes:
1. **Compile-time resolved**: `TypeAlias.field` → `emitTaggedUnionInit` (for TU) or `enum_const` (for enum) or error set member
2. **Runtime**: `lowerExpr(base)` → resolve base type → if struct/union/TU → `.load_field{ field_id }`. Slice `.len` → `SLICE_FIELD_LEN`, slice `.ptr` → `SLICE_FIELD_PTR`.

### Index Access `sf/src/lower.zig:1430`
```
lowerExpr(base) → base_temp
maybeExtractSlicePtr() → ptr_temp (extracts `.ptr` field from slice)
lowerExpr(index) → idx_temp
nextTemp(elem_type) → tid
emitInst(.load_index{ ptr_temp, idx_temp, tid })
```
Coercion context: `applyCoercion` after expression (`sf/src/lower.zig:454`).

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
Dispatches by l-value kind: ident → `.addr_of`, index_access → ptr+idx via `BIN_ADD`, deref → reuses inner expr, paren → recurse.

### Array Init `sf/src/lower.zig:2664`
```
nextTemp(array_type) → base_temp
for each element:
  lowerExpr(element) → val_temp
  emitInst(.int_const{ ei }) → ix_temp
  emitInst(.assign_index{ base_temp, ix_temp, val_temp })
return base_temp
```

### Struct Init `sf/src/lower.zig:2695`
```
nextTemp(struct_type) → base_temp
for each field init:
  lowerExpr(val) → val_temp
  find field index by name
  if TU: emit `.int_const(tag_index)` + `.assign_field(TU_FIELD_TAG, tag)` + optionally `.assign_field(TU_FIELD_PAYLOAD, val)`
  if struct: emit `.assign_field(field_index, val)`
```

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

**print() builtin** (`sf/src/lower.zig:375`): Special-cased. Emits `print_str` for the format string, `print_val` per argument.

**Builtin calls** (`sf/src/lower.zig:2381`): `@ptrCast`, `@intCast`, `@intToFloat`, `@ptrToInt`, `@intToPtr` emit corresponding LIR instructions. `@sizeOf`/`@alignOf` resolved via comptime values table or ICE. `@enumToInt` forwards the value as-is.

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

#### Switch Expression `sf/src/lower.zig:2800`
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

#### Return Statement `sf/src/lower.zig:3614`
```
expandDefers(0, 0)  // emit all pending defers
lowerExpr(value) → .ret(val) or .ret_void
```

#### Break Statement `sf/src/lower.zig:3635`
```
expandDefers(exit_scope, 0) → .jump(exit_target)
```

#### Continue Statement `sf/src/lower.zig:3661`
```
expandDefers(cont_scope, 0) → .jump(header_target)
```

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

**Important (verified, P7):** the expansion **pops** the action — `self.defer_stack.len = i` at `lower.zig:3931` (errdefer at `:3935`) — before lowering its body. A `defer`/`errdefer` is therefore lowered at exactly **one** scope exit, not at every exit. The design doc (`docs/sf/AST_LIR_Lowering_p2.md:406-421`) shows the same loop **without** the pop; the implementation deviates. See the P7 `readFile`/`fclose` trace below (item 3): only the first-lowered return path gets the inlined `fclose`, the other return paths leak the `FILE*`.

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

## TCO (Tail Call Optimization) Pattern

The lowerer does **not** implement TCO. No tail-call elimination or sibling-call optimization is performed. Function calls always produce a `call` or `call_direct` instruction regardless of position. The `loop_header` LirInst variant (lir.zig:31) exists but is never emitted by the lowerer. See the P7 evidence below (item 5) for the lisp `eval` trampoline trace.

---

## Type Coercions `sf/src/lower.zig:3991`

`applyCoercion` dispatches to `materializeInto` and specific cast instructions:

| CoercionKind | LIR Pattern |
|-------------|-------------|
| `none` | `applyNoneCoercion` — handles null→optional null ptr via `set_optional_null`/`int_const(0)` |
| `wrap_optional_null` | `materializeInto(src, target, null_src)` → `set_optional_null` |
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

`materializeInto` (`sf/src/lower.zig:852`) is the general mechanism: given a source temp and an expected type, it walks the type hierarchy (optional layers, error union layers) and emits wrapping instructions (`wrap_optional`, `wrap_error_ok`, `wrap_error_err`, `set_optional_null`) to match the expected type shape.

---

## Control Flow Graph Construction

Blocks are created lazily via `createBlock()`. Every branch/switch terminator sets `is_terminated = 1` on the source block. The CFG is implicit in the block indices stored in jump/branch instructions. No explicit edge lists or dominator trees are built at the LIR level.

---

## Experimental Evidence (P7 Deep-Dive, 2026-07-31)

Verified on the 4 working examples (`examples/z98/{mud_server,game_of_life,lisp_interpreter_curr,json_parser}/main.zig`) with two independent methods:

- `[markers]` — the P0 traces `/tmp/dd/*.mrk` (`zig1 --markers --dump-c89`). The LIR-phase region runs from the `L\n` marker (`main.zig:506`) through the per-module `M<idx>:<ast_root>:R<decls>:<kinds>` markers (`main.zig:535`), the per-fn `FNL:<name_id>` markers (`lower.zig:4108`) and `D3HT:` temp dumps (`lower.zig:4175`), up to `A0 <kinds>` (`main.zig:584`) and the closing `C\n` (`main.zig:603`).
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

Dominant shape: **`assign` + `int_const` + `jump` + `branch` dominate in every example** — a straight-line, alloca-based, jump-heavy IR. json_parser is the most call-heavy (127 `call_direct`, its parser is deeply recursive), lisp the most branch/switch-heavy (21 `switch_br` in `eval` alone). Per-function detail `[fprintf]` (top function per example): mud `main` 427 insts (assign 84, int_const 43, binary 41, jump 40); gol `main` 496 (int_const 133, assign 99, assign_field 54); lisp `eval` 826 (assign 182, load_field 75, jump 74); json `parseObject` 214 (assign 46, call_direct 24, jump 19). 44 of the 54 variants fire via `emitInst`; the 10 that never fire in these examples are `decl_temp` (only via `hoistTemps`, `lower.zig:3953`), `loop_header`, `label`, `float_cast`, `int_to_float`, `int_to_ptr`, `float_const`, `enum_const`, `load_global`, `store_global` — and `unary` is rare (13 total across all 4).

### 2. Temp counts per function / hoisting

`D3HT:<tid,type>|…` is emitted once per lowered fn (`lower.zig:4175`); its entry count = total temporaries for that function (params included — each param gets a `nextTemp`, `lower.zig:4135`, then its type is patched in `hoisted_temps`, `lower.zig:4145`). `[markers]`:

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

`expandDefers` counts `[fprintf]`: pushDefer 0/0/0/1, expandDefers calls 86/55/593/195 for mud/gol/lisp/json. **Finding (single-use defer):** `expandDefers` pops the action it expands — `self.defer_stack.len = i` at `lower.zig:3931` (and `:3935` for errdefer) — so a `defer` is lowered at exactly **one** exit site, not at every scope exit. In `readFile` only the first-lowered return path (the `fseek(f,0,SEEK_END)!=0` error, json_parser.c:845-854) contains the `fclose(zT_31)` call (at :849); the other return paths (json_parser.c:872, :892, :933, :946, :955) return without closing `f`. The design doc `docs/sf/AST_LIR_Lowering_p2.md:406-421` shows `expandDefers` **without** the pop — this is an implementation deviation with real correctness impact (FILE* leak on every path except the first return). Not fixed here (documentation-only task).

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

### 5. TCO assessment (lisp `eval` loop)

**No TCO is detectable — confirmed.** Evidence:

- `[fprintf]` the `loop_header` LirInst (lir.zig:31) is **never emitted** by the lowerer (0 in all 4 examples). `while_stmt` lowering (lower.zig:3302-3388) builds a plain 5-block CFG (entry → cond → body → exit → cont, back-edge cont → cond) with `jump`/`branch` only; `loop_header` exists as a variant but is dead code (c89_emit.zig:2281 consumes it as a no-op).
- `[fprintf]` `eval`'s manual `while (true)` trampoline (eval.zig:12) lowers to: `jump cond` (entry), `bool_const(1)` + `branch` (cond block BB1), body with the expr-type `switch_br` (21 of them), and a back-edge `jump` to BB1. The source-level `continue`s (eval.zig:56,61,222) become plain `goto`/`jump` to the loop header — they are loop branches, not tail calls.
- `[markers]`/`[fprintf]` the tail-position `return try apply(fun, args, …)` (eval.zig:169) emits `call_direct` → `check_error` → `branch` → (err: `ret`; ok: `unwrap_error_payload`) — a **real, frame-preserving call**, not a jump. The emitted C shows it verbatim: `zT_340 = zF_24BC4A3B_apply(zT_335,…)` with `return zT_340` on the error path (lisp_interpreter_curr.c:5480-5509; the error-path `return zT_340` is at :5509, block `z_bb_160`). `eval` itself also contains 4 plain recursive `zF_08D22E0F_eval(...)` calls (lisp_interpreter_curr.c:4636, :4753, :4990, :5440).

The doc's existing claim ("The lowerer does not implement TCO", §TCO above) is **correct**; this section adds the concrete evidence. The recursive Lisp engine therefore relies on the C stack for deep recursion.

### 6. Coercion application: `applyCoercion` vs `materializeInto`

`applyCoercion` (lower.zig:3991) dispatches exactly as the §Type Coercions table describes: the 5 wrapper kinds (`wrap_optional_null`, `wrap_optional`, `wrap_error_success`, `wrap_error_err`, `ptr_to_optional_ptr`) and `none`-with-null delegate to `materializeInto` (lower.zig:852), which walks up to 8 optional/error-union layers (lower.zig:859-895) and emits `set_optional_null`/`wrap_optional`/`wrap_error_ok`/`wrap_error_err`, optionally preceded by an inner `int_cast`/`float_cast` (lower.zig:898-910). `[fprintf]` call counts:

| Example | applyCoercion calls | materializeInto calls | dominant kinds |
|---------|---------------------|------------------------|----------------|
| mud_server | 51 | 8 | int_literal_coerce 20, none 14, string_to_slice 12 |
| game_of_life | 99 | 10 | none 52, int_literal_coerce 39, const_qualify 8 |
| lisp_interpreter_curr | 595 | 135 | none 329, wrap_error_success 60, string_to_slice 53, wrap_error_err 53, int_literal_coerce 48 |
| json_parser | 159 | 34 | none 95, int_literal_coerce 27, wrap_error_success 15, wrap_error_err 14 |

Cross-check `[markers]`: the `CEM`/`CEP` markers are emitted **per `lowerExpr`** call (lower.zig:446-468) — `CEP:n…k<kind>` when a coercion entry exists (→ `applyCoercion`), `CEM:n…` when missing. `[markers]` CEP counts (mud 36, gol 43, lisp 261, json 63) and the CEP-kind distribution (int_literal_coerce / string_to_slice / wrap_error_* / unwrap_optional / wrap_optional_null, exactly the table's kinds) agree with the `[fprintf]` `applyCoercion` kinds. The `[fprintf]` totals are higher because `applyCoercion` also fires at non-`lowerExpr` sites (call args `lower.zig:2022, :2092, :2176, :2269`, return values, compound-assign sites `lower.zig:1391`); the `none` kind (52 in gol) comes from `applyNoneCoercion` (lower.zig:3967), which rewrites `null` → optional-null / `int_const(0)` pointer.

---

## Debugging

The lowerer emits verbose marker output prefixed with `"L"` (for LIR lowering). **The `--dump-lir` flag is DEAD**: it is parsed and stored (`main.zig:695-696` sets `cli.dump_lir`) but never read anywhere in the pipeline. Marker output is instead gated on the `--markers` flag via `pal.markerWrite()`/`markerWriteInt()`, which check `g_markers_enabled` (`sf/src/pal.zig:96-103`). Run `zig1 --markers --dump-c89 <file>` and capture stderr to see the per-node tracing below.

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
| `FNL:<name_id>` | Function lowering — one per lowered fn_decl (`lower.zig:4108`) |
| `D3HT:<tid,type>\|...` | Hoisted temps dump — one per fn, entry count = total temp count (`lower.zig:4175`) |
| `CEM:n<idx>` | Coercion check — coercion missing (per lowerExpr, `lower.zig:463`) |
| `CEP:n<idx>k<kind>` | Coercion check — coercion present, kind emitted (`lower.zig:456`) |
| `COE/CO2` | Compound-assign coercion sites (`lower.zig:1391`) |
| `XD:<depth>,<err>` / `PD:<kind>,<node>` | expandDefers / pushDefer tracing (instrumented builds; see P7 evidence above) |

All markers use `pal.markerWrite()` which outputs to stderr when `--markers` is enabled.


