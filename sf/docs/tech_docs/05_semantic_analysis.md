# 05 — Semantic Analysis [updated: 2026-09-21 — refreshed against current source: socket builtins removed (std_net extern surface), async/introspection/pointer/bitcast builtins, volatile + packed/enum checks, spill-backed resolved-type table; line refs and dated evidence removed; Task 10D adds the Zig-matched `defer`/`errdefer` outward-control-flow rejections ERR_3051–ERR_3054; Task 11N adds `semanticAnalyzerArrayFieldLen` so `.len` on a struct/union array field resolves to `TYPE_USIZE` despite the array-field decay, gated on the accessed name being `len` (fix round 1); Task 11P resolves the `for`-range start/end operands in the `range_exclusive`/`range_inclusive` arm before returning `TYPE_U32`]

> Covers: `semantic_analyzer.zig`, `coercion.zig`, `resolved_type_table.zig`, `constraint_checker.zig`, `assign_helper.zig`

## Summary Table

| Artifact | Count | Notes |
|----------|-------|-------|
| `SemanticAnalyzer` fields | 83 | 49 non-builtin + 34 builtin name IDs (11 socket IDs removed) |
| Expression kind dispatch arms | 47+ | Every `AstKind` handled in `semanticAnalyzerResolveExpr` |
| `CoercionKind` variants | 17 | `none` through `wrap_optional_null` |
| Coercion checks in `classifyCoercion` | ~20 | noreturn/undefined, null, optional, error union, ptr/slice/many-ptr (qualifier-monotone), array, widening, literal |
| Marker codes | 90+ | `IDE`, `D7`, `L`, `S`, `STY`, `FAE`, `PFA`, `FAPR`, `COE`, `CCK`, `COR`, `SIF`, `MIX`, `SWU`, etc. |
| Expected-type stack | stack-based | Push/pop in calls, returns, assigns, struct init, var decls, switch prongs |
| Resolved type table | `node_idx→TypeId` | Dense 5 B/node spill table + sparse resident source map |
| Constraint checks | 3 | Return type, switch exhaust, break/continue validation |
| assign_helper | 1 | `resolveAssignedLocalTemp` (lowering-side lookup) |

---

## semantic_analyzer.zig (`sf/src/semantic_analyzer.zig`, 3438 lines)

Central phase-5 engine. Walks function bodies bottom-up via a worklist and resolves every expression to a `TypeId`. Records coercions for lowering and emits diagnostics for type errors.

### SemanticAnalyzer struct (`sf/src/semantic_analyzer.zig`)

```zig
pub const SemanticAnalyzer = struct {
    type_table: *ResolvedTypeTable,
    diag: *DiagnosticCollector,
    registry: *TypeRegistry,
    symbols: *SymbolRegistry,
    store: *AstStore,
    module_id: u32,
    source_file_id: u32,
    expected_type_stack_items: [*]TypeId,
    expected_type_stack_len: usize,
    expected_type_stack_cap: usize,
    expected_type_stack_alloc: *Sand,
    stmt_work_items: [*]u32,
    stmt_work_len: usize,
    stmt_work_cap: usize,
    current_fn_return: TypeId,
    current_fn_name: u32,
    coercion_table: *coercion_mod.CoercionTable,
    enum_value_table: *hash_mod.U32ToU32Map,
    error_code_registry: *hash_mod.U32ToU32Map,
    call_arg_types: *hash_mod.U32ToU32Map,
    call_param_map: *hash_mod.U32ToU32Map,
    current_switch_cond_tu: u32,
    switch_depth: u32,
    defer_depth: u32,
    defer_inner_loops: u32,
    defer_label_stack: [16]u32,
    defer_label_isloop: [16]u8,
    defer_label_len: usize,
    local_decl_names: [*]u32,
    local_decl_types: [*]u32,
    local_decl_count: usize,
    local_decl_cap: usize,
    local_consts: type_resolver.LocalConstScope,
    packed_gate_items: [*]u32,
    packed_gate_len: usize,
    packed_gate_cap: usize,
    packed_struct_tids: [*]u32,
    packed_struct_decl_nodes: [*]u32,
    packed_struct_cache_len: usize,
    packed_struct_cache_cap: usize,
    checked_struct_tids: [*]u32,
    checked_struct_tids_len: usize,
    checked_struct_tids_cap: usize,
    _stub_0: u32,
    _stub_1: u32,
    interner: *interner_mod.StringInterner,
    // 34 builtin name IDs (socket IDs removed netbind S3, 2026-09-04):
    ptrcast_name_id, volatilecast_name_id, ptrtoint_name_id, inttoptr_name_id,
    int_from_ptr_name_id, ptr_from_int_name_id, field_parent_ptr_name_id,
    bitcast_name_id, intcast_name_id, floatcast_name_id, inttofloat_name_id,
    inttoenum_name_id, enumtoint_name_id, as_name_id,
    size_of_name_id, align_of_name_id, offset_of_name_id,
    bit_size_of_name_id, bit_offset_of_name_id,
    putchar_name_id, stdout_write_name_id, stderr_write_name_id,
    getchar_name_id, exit_name_id, panic_name_id, sleep_ms_name_id,
    is_windows_name_id, console_clear_name_id, console_gotoxy_name_id,
    console_set_color_name_id,
    async_frame_size_name_id, async_init_name_id, async_resume_name_id,
    async_suspend_name_id,
    async_analysis_ready: bool,
    module_reg: *mr_mod.ModuleRegistry,
    suspending_fns: *hash_mod.U64ToU32Map,
};
```

Key state: expected-type stack for contextual type inference (enum literals, error literals, null), statement worklist for iterative traversal, switch context for enum literal resolution, local declaration shadow stack + function-local `const` scope, packed-struct gate/checked caches, and async suspending-function registry.

### semanticAnalyzerInit (`sf/src/semantic_analyzer.zig`)

`[inference: sandAlloc-builtin name interning, zero-init stacks/lists, return SemanticAnalyzer]`

Allocates no heap memory in the struct itself. Interns the 34 builtin names and the discard identifier `_`: (`@ptrCast`, `@volatileCast`, `@ptrToInt`, `@intToPtr`, `@intFromPtr`, `@ptrFromInt`, `@fieldParentPtr`, `@bitCast`, `@intCast`, `@floatCast`, `@intToFloat`, `@intToEnum`, `@enumToInt`, `@as`, `@sizeOf`, `@alignOf`, `@offsetOf`, `@bitSizeOf`, `@bitOffsetOf`, `@putChar`, `@stdoutWrite`, `@stderrWrite`, `@getChar`, `@exit`, `@panic`, `@sleepMs`, `@isWindows`, `@consoleClear`, `@consoleGotoxy`, `@consoleSetColor`, `@asyncFrameSize`, `@asyncInit`, `@asyncResume`, `@asyncSuspend`). Stacks and work arrays are zero-capacity — grown on first use. The 11 socket names are no longer interned.

### semanticAnalyzerIsTypeValueCast (`sf/src/semantic_analyzer.zig`)

`[inference: match name_id vs 8 cast builtins → return bool]`

Checks if name_id matches `@ptrCast`, `@volatileCast`, `@intToPtr`, `@intCast`, `@floatCast`, `@intToFloat`, `@intToEnum`, or `@as`. Used by builtin_call dispatch in ResolveExpr to short-circuit as type-value cast.

### semanticAnalyzerIsBuiltinSupported / semanticAnalyzerBuiltinNameEq (`sf/src/semantic_analyzer.zig`)

`[inference: name-id allow-list + string-equality fallbacks → bool]`

`semanticAnalyzerIsBuiltinSupported` is the allow-list gating the builtin_call arm; `semanticAnalyzerBuiltinNameEq` compares an interned name against a literal for builtins without a dedicated name-id field (`@enumToInt`, `@cVaStart`, `@cVaArg`, `@cVaEnd`, `@panic`).

### semanticAnalyzerGrowLocalDecls (`sf/src/semantic_analyzer.zig`)

`[inference: grow-by-doubling from min 8, memcpy name+type arrays]`

Grows the parallel name/type local-decl arrays. Called by registerLocalDecl on overflow.

### Async diagnostics (`sf/src/semantic_analyzer.zig`)

`semanticAnalyzerDiagAsyncOutsideSuspending` emits `ERR_3018` when `@asyncSuspend` is used outside a function known to be suspending (via `async_analysis.asyncIsSuspending`). `semanticAnalyzerDiagAsyncBuiltinInDefer` emits `ERR_3019` for any `@async*` builtin reached while `defer_depth > 0`.

### Defer control-flow rejections — `ERR_3051`–`ERR_3054` (`sf/src/semantic_analyzer.zig`)

Task 10D implements official Zig's (`src/AstGen.zig`) rule for control flow inside a `defer`/`errdefer` body, applied before lowering. `semanticAnalyzerDiagDeferCtl` emits the diagnostic at the offending node; `semanticAnalyzerCheckDeferBody` is a recursive walk entered from the `defer_stmt`/`errdefer_stmt` arm of `semanticAnalyzerResolveStmtIter` (state saved/restored around it):

- `return_stmt` → `ERR_3051` "cannot return from defer expression" (Zig's `any_defer_node`).
- `try_expr` → `ERR_3054` "'try' not allowed inside defer expression" (Zig's `any_defer_node`).
- `break_stmt`/`continue_stmt` → `ERR_3052`/`ERR_3053` "cannot break/continue out of defer expression" **only** when the target is not declared inside the body (Zig's `cur_defer_node` walk). A `while`/`for` increments `defer_inner_loops`; a `labeled_stmt` pushes onto `defer_label_stack` (with `defer_label_isloop` recording whether the label wraps a loop, so a labeled-block target is legal for `break` but not `continue`). `semanticAnalyzerDeferBreakAllowed`/`semanticAnalyzerDeferContinueAllowed` test membership.
- A nested `fn_decl` stops the walk (resets both markers); a nested `defer`/`errdefer` is skipped here and validated by its own arm. Children are walked generically via `nodeHasNodeExtraChildren`/`nodeChildIsNode` in `semanticAnalyzerCheckDeferChildren`.

### Packed / enum gates (`sf/src/semantic_analyzer.zig`)

`semanticAnalyzerGatePackedFields` and `semanticAnalyzerGatePackedUnionMembers` validate each `field_decl` of a `packed` struct/union: the field type must be `bool`, an integer, or (for structs) a packed struct; `enum` fields require an explicit unsigned backing. Fields wider than 31 bits and non-integer fields are rejected with `error[3000]`. `semanticAnalyzerGateEnumTypeDecl` / `semanticAnalyzerGateEnumModuleDecl` validate `enum(uN)` backings (unsigned only; `bool`/signed/invalid rejected) and that every tag value fits the backing width (`2^N - 1`, no silent truncation). `semanticAnalyzerPackedFieldTypeAllowed` and `semanticAnalyzerPackedStructDeclForType` back these checks; the `packed_gate_items`/`packed_struct_*`/`checked_struct_tids` caches memoize results.

### Volatile helpers (`sf/src/semantic_analyzer.zig`)

`semanticAnalyzerVolatileDrop` decides whether a coercion would implicitly discard a `volatile` qualifier (ptr/many-ptr/slice to a non-volatile counterpart, including optional unwrapping and array-decay pointee shapes). `semanticAnalyzerMaybeDiagVolatileDrop` emits `error[3000]` "cannot implicitly discard 'volatile' qualifier; use @volatileCast to remove it". `semanticAnalyzerPtrCastDropsVolatile` rejects `@ptrCast` dropping volatile; `semanticAnalyzerVolatileCastValid` requires `@volatileCast` to have a volatile source and the same base type.

### Calling-convention / shape checks (`sf/src/semantic_analyzer.zig`)

`semanticAnalyzerFnPtrConvMismatch` compares two fn-ptr types' `FN_FLAG_STDCALL` bits; a mismatch promotes the assignment/return/var-decl diagnostic to a hard error. `isBShapeMismatch` hard-errors the real-Zig-invalid shapes (bare `*T`→slice, array element/length mismatch, error-set superset→subset, enum→integer without `@enumToInt`; `full` also selects bare `*T`→`[*]T` in var-decl/assignment positions).

### Termination analysis (`sf/src/semantic_analyzer.zig`)

`fnReturnRequiresValue` decides whether a result type carries data (false for `void`/`noreturn` and the void-payload forms of error unions and optionals). `astTerminates`/`astSwitchTerminates`/`astSwitchExhaustive`/`astWhileTerminates`/`astSubtreeHasBreak` are a definitely-returns predicate over the AST (block/if/switch/`while(true)`, declarations and assignments whose initializer terminates); `semanticAnalyzerResolveFnBody` uses it to emit `ERR_3003` "missing return" only when a value is required and a path can fall through.

### registerLocalDecl (`semantic_analyzer.zig`)

`[inference: grow if full → write name_id/type_id → inc count; SCT:n/SCT:t markers]`

Core local declaration registration. Called by resolveIdent local lookup, resolveFnBody param registration, and if/while/for header captures.

### pushExpectedType / popExpectedType (`semantic_analyzer.zig`)

`[inference: grow-by-doubling from 64, write/inc or dec stack pointer]`

```
pushExpectedType(self, ty):
  if stack full: grow to max(64, cap*2) entries
  items[len] = ty; len += 1

popExpectedType(self):
  if len > 0: len -= 1

topExpectedType(self) -> u32:
  if len == 0: return 0
  return items[len-1]
```

Used for contextual type inference: fn call args, return stmts, assigns, struct init fields, var decl init, if/else unification, switch prongs, enum/error literals. `if_expr` itself never pushes; its then/else branches inherit the expected type pushed by the enclosing return-statement or var-decl.


### semanticAnalyzerStmtWorkPush (`semantic_analyzer.zig`)

`[inference: grow-by-doubling from 64, write/inc work pointer]`

Worklist growth and push. Grows the statement work array (min 64, doubling). Pushes stmt node index onto the worklist.

### semanticAnalyzerResolveIdent (`semantic_analyzer.zig`)

`[inference: local-decl stack → symbol registry qualified lookup → name cache → TYPE_UNDEFINED → TYPE_VOID]`

Resolution order:
1. **Marker `IDE\n`** — entry; `SEM:vi` if name_id == 1 (underscore).
2. **Local declarations** (reverse scan): if `local_decl_names[li] == name_id`, emit `D7:Yn D7:n<name> D7:t D7:<type> L\n L:t<type>` and return type.
3. **Symbol registry**: `symbolRegistryQualifiedLookup(symbols, module_id, name_id)`:
   - `type_alias` → gate the alias decl (`semanticAnalyzerMaybeGateAliasDecl`); if `s.type_id != 0` return it, else fall back to the module-qualified then bare name cache, else `SVO\n` + `TYPE_VOID` (marker `TAL\n`).
   - `s.type_id != 0` → return `s.type_id` (marker `STY:N STY:T`, plus `STY:C` when a bare-name cache entry exists).
   - else → return `TYPE_VOID` (marker `SVO\n`).
4. **Name cache**: `nameCacheGet(registry, name_id)` (module-0 key) → return cached type (marker `C2:T`).
5. **Debug detail `D8:*`**: if node_idx in [450, 660], dump name, node kind, resolved type.
6. If name_id == `_stub_0` (discard sentinel) → return `TYPE_UNDEFINED`.
7. Fallback → return `TYPE_VOID` (marker `IDT:<name>:VOID\n`).

The name-cache key for the bare lookup is `(u64)name_id` (module 0); a separate module-qualified lookup uses `(module_id<<32)|name_id`. The `_stub_0` discard sentinel is saved and restored around every clobbering helper (`ResolveIndexAccess`/`ResolveSliceExpr`/`ResolveTupleLiteral`/`ResolveArrayInit`), and `resolveAssign` additionally special-cases `_ = expr`, so a discard ident reliably yields `TYPE_UNDEFINED`.

### semanticAnalyzerResolveFieldAccess (`semantic_analyzer.zig`)

`[inference: resolve base expr → type-kind dispatch on TypeKind for field lookup → resolvedTypeTableSet]`

Entry: `FAE\n PFA:BK<kind> PFA:FN<name_id>`.

**Phase 1 — ident_expr base (module-qualified, type alias fields):**
- If base is `ident_expr` and resolves to a symbol:
  - `type_alias` on tagged_union/enum/error_set → scan field/member/error names, return `alias_type_id`.
  - `module` → lookup field in target module (`Q1:FL/KL/TL/FN`). Flags check (bit 1 = `0x2`). If function, resolve fn type via return_type_node (`resolvedTypeTableGet`, else `resolveTypeExprFull`; markers `Q1FX`, `BR:x/rt/fnr/treN/treT/dv/ft`).
  - If the base ident is undeclared (`TYPE_VOID`) → `ERR_3001` "identifier '...' is not declared or imported in this module".
- An `import_expr` base resolves through the module registry and looks the field up in the target module.

**Phase 2 — general field access (non-ident base):**
- Resolve base expr. If `TYPE_VOID`, bail `FB\n`.
- **Pointer dereference**: if ptr_type/many_ptr_type, follow to pointee. Markers: `FAPR:OK FAPR:DK`.
- **Optional guard**: `error[3000]` "cannot access field on optional type; use .? to unwrap first".
- **Error union guard**: `error[3000]` "cannot access field on error-union type; handle the error first".

**Phase 3 — type-kind-specific field lookup:**
- `struct_type` → scan `FieldEntry[]` at `st_items[payload_idx].fields_start`.
- `union_type` / `packed_union_type` → scan `FieldEntry[]` at `un_items[payload_idx].fields_start`.
- `tagged_union_type` → `.tag` returns the tag type (`FT:TAG`); `.payload` returns the first non-void field type (array fields decay to `*elem`, marker `FP:PAYLOAD`); otherwise scan `FieldEntry[]`.
- `module_type` → `MFA\n`/`MF1\n`/`MFF\n`/`MFP` markers. Look up field in target module's symbols. If function, look up resolved fn type.
- `slice_type` → `.len` returns `TYPE_USIZE` (`FSL:USIZE\n`). `.ptr` returns `[*]elem` (`FSP:PTR\n`).
- `array_type` → `.len` returns `TYPE_USIZE` (`FAA:USIZE\n`).
- **array-field `.len` fallback** `[updated: 2026-09-21 — Task 11N]`: before the final `TYPE_VOID` fallback, `semanticAnalyzerArrayFieldLen(node.child_0)` inspects the `.len` base. If it is a `field_access` whose container (struct / union / packed_union, optionally through a pointer) declares the named field as an `array_type`, `.len` resolves to `TYPE_USIZE`. This recovers `s.a.len` after the Phase-4 array-field decay (`s.a` → `*u8`) makes the `array_type` arm above unreachable. The fallback is gated on the accessed name being `len` (`field_name_id == len_id`), so an unknown field on an array field (`s.a.foo`) still falls through to `TYPE_VOID` (rejected). A `[*]T` field (many-item pointer) is not an array and stays `TYPE_VOID` (rejected).
- `error_set_type` → `typeRegistryErrorSetMemberIndex` check. If found, return `base_type_id`.
- `enum_type` → scan enum members; if found, return `base_type_id`.

**Phase 4 — struct/union/tagged_union field scan:**
```
fi from 0..fields_count:
  if fe_items[fields_start+fi].name_id == field_name_id:
    result = fe.type_id
    if result is array_type: result = *elem (array-to-ptr decay)
    return result (marker FF:R<type>)
```

**Phase 5 — not found:** marker `NF\n FF2:N FF2:F FF2:B`, return `TYPE_VOID`.


### Expression Resolution Dispatch — semanticAnalyzerResolveExpr

`semantic_analyzer.zig` — master `if/else` chain on `node.kind`:

| Arm | AstKind | `[inference]` | Returns |
|-----|---------|---------------|---------|
| 1 | `int_literal` | `[inference: return TYPE_INT_LIT]` | `TYPE_INT_LIT` (19) |
| 2 | `float_literal` | `[inference: return TYPE_F64]` | `TYPE_F64` (16) |
| 3 | `char_literal` | `[inference: return TYPE_U8]` | `TYPE_U8` (8) |
| 4 | `bool_literal` | `[inference: return TYPE_BOOL]` | `TYPE_BOOL` (2) |
| 5 | `null_literal` | `[inference: return TYPE_NULL]` | `TYPE_NULL` (17) |
| 6 | `undefined_literal` | `[inference: return TYPE_UNDEFINED]` | `TYPE_UNDEFINED` (18) |
| 7 | `unreachable_expr` | `[inference: return TYPE_NORETURN]` | `TYPE_NORETURN` (3) |
| 8 | `string_literal` | `[inference: `*const [N]u8`, N = real byte length]` | `typeRegistryGetOrCreatePtr(array[u8;N], true)` |
| 9 | `enum_literal` | → `semanticAnalyzerResolveEnumLiteral` | switch context / expected type |
| 10 | `error_literal` | `[inference: expected-type → error set member lookup (unwraps optional)]` | error set TypeId, error union, or TYPE_VOID (`ERR_3011` when not found) |
| 11 | `ident_expr` | → `semanticAnalyzerResolveIdent` | local/symbol/cache/UNDEFINED/VOID |
| 12 | `field_access` | → `semanticAnalyzerResolveFieldAccess` | field type |
| 13 | `index_access` | → `semanticAnalyzerResolveIndexAccess` | elem type / tuple field type |
| 14 | `slice_expr` | → `semanticAnalyzerResolveSliceExpr` | slice type |
| 15 | `deref` | `[inference: ptr/many_ptr → base type]` | `pp.base` or base type |
| 16 | `address_of` | `[inference: return *T for expr of type T; packed field address rejected]` | `typeRegistryGetOrCreatePtr(base, false)` |
| 17 | `fn_call` | → `semanticAnalyzerResolveFnCall` | return type |
| 18 | `builtin_call` (unsupported) | `[inference: diag error[3000] unsupported builtin]` | `TYPE_VOID` |
| 19 | `builtin_call` (supported) | → dispatch by `child_0` | per builtin (see below) |
| 20 | `bool_not` | `[inference: resolve child, return TYPE_BOOL]` | `TYPE_BOOL` |
| 21 | `negate` / `wrap_negate` | → `semanticAnalyzerResolveNegate` | numeric type or VOID |
| 22 | `bit_not` | → `semanticAnalyzerResolveBitNot` | integer type or VOID |
| 23 | `try_expr` | → `semanticAnalyzerResolveTryExpr` | error union payload |
| 24 | `catch_expr` | `[inference: unwrap error union + capture]` | payload type |
| 25 | `orelse_expr` | → `semanticAnalyzerResolveOrelseExpr` | optional payload |
| 26 | `break_stmt` / `continue_stmt` | `[inference: return TYPE_VOID]` | `TYPE_VOID` |
| 27 | `var_decl` / `defer_stmt` / `errdefer_stmt` / `labeled_stmt` | → `semanticAnalyzerResolveStmtIter` | `TYPE_VOID` |
| 28 | `if_expr` | → `semanticAnalyzerResolveIfExpr` | unified then/else type |
| 29 | `if_stmt` | `[inference: resolve header, push children to worklist]` | `TYPE_VOID` |
| 30 | `for_stmt` | → `semanticAnalyzerResolveForHeader` | `TYPE_VOID` |
| 31 | `while_stmt` | → `semanticAnalyzerResolveWhileHeader` | `TYPE_VOID` |
| 32 | `swt_ex` | → `semanticAnalyzerResolveSwitchExpr` | unified prong type |
| 33 | `tuple_literal` | → `semanticAnalyzerResolveTupleLiteral` | tuple TypeId |
| 34 | `struct_init` | → `semanticAnalyzerResolveStructInit` | struct/TU/union TypeId |
| 35 | `array_init` | → `semanticAnalyzerResolveArrayInit` | array TypeId |
| 36 | `ptr_type` / `many_ptr_type` / `array_type` / `slice_type` / `optional_type` / `error_union_type` / `fn_type` / `struct_decl` / `enum_decl` / `union_decl` / `error_set_decl` | `[inference: return TYPE_TYPE; struct_decl also runs packed gate]` | `TYPE_TYPE` (20) |
| 37 | `paren_expr` | `[inference: delegate to child]` | child type |
| 38 | `return_stmt` | → `resolveReturnStmt` | `TYPE_NORETURN` |
| 39 | `expr_stmt` | `[inference: delegate to child]` | child type |
| 40 | `import_expr` | `[inference: return TYPE_VOID]` | `TYPE_VOID` |
| 41 | `block` | `[inference: stmt iter children, resolve last child]` | last child type / VOID |
| 42 | `add` / `sub` / `mul` / `div` / `mod_op` / `wrap_add` / `wrap_sub` / `wrap_mul` / `sat_add` / `sat_sub` / `sat_mul` | → `semanticAnalyzerResolveArithmetic` | numeric/ptr type or VOID |
| 43 | `bit_and` / `bit_or` / `bit_xor` / `shl` / `shr` / `sat_shl` | → `semanticAnalyzerResolveBitwise` | integer type or VOID |
| 44 | `bool_and` / `bool_or` | → `semanticAnalyzerResolveLogical` | `TYPE_BOOL` or VOID |
| 45 | `cmp_eq` / `cmp_ne` / `cmp_lt` / `cmp_le` / `cmp_gt` / `cmp_ge` | → `semanticAnalyzerResolveComparison` | `TYPE_BOOL` or VOID |
| 46 | `plain_assign` … `or_assign` plus `wrap_add_assign`/`wrap_sub_assign`/`wrap_mul_assign`/`sat_add_assign`/`sat_sub_assign`/`sat_mul_assign`/`sat_shl_assign` | → `semanticAnalyzerResolveAssign` | lhs type or VOID |
| 47 | `range_exclusive` / `range_inclusive` | `[inference: resolve child_0, and child_1 when present, then return TYPE_U32]` (early return) `[updated: 2026-09-21 — Task 11P]` | `TYPE_U32` |
| — | (any other AstKind) | `[inference: diag ERR_3020, return TYPE_VOID]` | `TYPE_VOID` |

After all arms: emit `STX:n<idx> STX:k<kind> STX:r<result> A4:N<idx> A4:K<kind> A4:R<result>`, `resolvedTypeTableSet(node_idx, result)`, `STB:N<idx> STB:R<result>`, return `result`.



#### Builtin dispatch

`semanticAnalyzerIsBuiltinSupported` (name-id equality, with string-equality fallbacks for `@enumToInt`, `@cVaStart`, `@cVaArg`, `@cVaEnd`, `@panic`) gates the whole arm: any other `@name` reaching `resolveExpr` emits `error[3000]: unsupported builtin function` and resolves to `TYPE_VOID`. `semanticAnalyzerIsTypeValueCast` returns true for the eight type-value casts (`@ptrCast`, `@volatileCast`, `@intToPtr`, `@intCast`, `@floatCast`, `@intToFloat`, `@intToEnum`, `@as`); those resolve their value arg first, then `resolveTypeExprFull` the type arg (child_0) and return that type.

**Core I/O builtins** — each resolves its value args via `semanticAnalyzerResolveExpr` and returns the signature type:

| Builtin | Args resolved | Returns |
|---------|---------------|---------|
| `@putChar(c: u8)` | `ec[0]` | `TYPE_VOID` |
| `@stdoutWrite(buf, len)` | `ec[0]`, `ec[1]` | `TYPE_VOID` |
| `@stderrWrite(buf, len)` | `ec[0]`, `ec[1]` | `TYPE_VOID` |
| `@getChar()` | none | `TYPE_U8` |
| `@exit(code)` | `ec[0]` | `TYPE_NORETURN` |
| `@panic(msg)` | `ec[0]` | `TYPE_NORETURN` |
| `@sleepMs(ms: u32)` | `ec[0]` | `TYPE_VOID` |

**Console builtins:**

| Builtin | Args resolved | Returns |
|---------|---------------|---------|
| `@isWindows()` | none | `TYPE_BOOL` (comptime-folded — never reaches runtime) |
| `@consoleClear()` | none | `TYPE_VOID` |
| `@consoleGotoxy(x: i32, y: i32)` | `ec[0]`, `ec[1]` | `TYPE_VOID` |
| `@consoleSetColor(fg: i32, bg: i32)` | `ec[0]`, `ec[1]` | `TYPE_VOID` |

`@isWindows()` is the sema-half of a comptime intrinsic: `comptime_eval.zig` folds it to a `ComptimeVal` 0/1 (module const `host_is_windows`, currently `false`), so `phase_ComptimeEvaluation` populates `comptime_values[node]` and the lowerer emits an `int_const` (`TYPE_BOOL`). `if (@isWindows())` then folds to only the active branch (see 07 §Builtin console + comptime branch folding).

**Introspection / pointer / bitcast builtins:**

| Builtin | Behavior | Returns |
|---------|----------|---------|
| `@sizeOf` / `@alignOf` / `@offsetOf` / `@bitSizeOf` / `@bitOffsetOf` | type arg resolved via `resolveTypeExprFull` | `TYPE_INT_LIT` |
| `@ptrToInt` / `@intFromPtr` | value arg resolved | `TYPE_USIZE` |
| `@ptrFromInt` | value arg resolved; target taken from `topExpectedType` (must be a ptr/many-ptr, else `error[3000]`) | the inferred ptr type |
| `@fieldParentPtr` | outer type + field name resolved; returns `*outer` | `*outer` |
| `@bitCast` | destination type + source resolved; requires same-size integer source and destination (`state==2`), else `error[3000]` | destination type |
| `@enumToInt` | arg resolved; enum arg yields its backing type | enum backing / arg type |
| `@cVaArg` | arg + type resolved | the resolved type |
| `@cVaStart` / `@cVaEnd` | accepted (supported); argument resolved by the generic arm | arg type |
| `@ptrCast` | type-value cast; exactly two args (`ERR_3049` otherwise); rejects dropping `volatile` | target type |
| `@volatileCast` | type-value cast; requires a volatile source and same base type | target type |

**Async builtins:**

| Builtin | Behavior | Returns |
|---------|----------|---------|
| `@asyncFrameSize(fn)` | resolves the fn reference; requires a known suspending function (`ERR_3046` otherwise) | `TYPE_INT_LIT` |
| `@asyncInit(...)` | resolves up to 4 args; rejected inside defer/errdefer (`ERR_3019`) | `*void` |
| `@asyncResume(...)` | resolves up to 2 args; rejected inside defer/errdefer (`ERR_3019`) | `?*void` |
| `@asyncSuspend(...)` | resolves arg; rejected inside defer/errdefer (`ERR_3019`) and outside a suspending function (`ERR_3018`) | `*void` |

#### Socket builtins — REMOVED

The 11 socket builtins (`@socketCreate`/`BindListen`/`Accept`/`Connect`/`Send`/`Recv`/`Select`/`FdZero`/`FdSet`/`FdIsset`/`Close`) were removed (netbind S3, 2026-09-04). A direct `@socket*` caller now fails `error[3000]: unsupported builtin function` (rc=2, 0 `.c`); networking is now the `std_net` extern surface (target-selected wsock32/libc `extern "c"` bindings, WSAStartup init, `createTcpClient`).


### semanticAnalyzerResolveArithmetic (`semantic_analyzer.zig`)

`[inference: ptr+int → ptr, ptr-ptr → isize, num+int_lit → num, else wider-width/size winner]`

```
lhs = resolveExpr(child_0), rhs = resolveExpr(child_1)
if lhs==0 or rhs==0: return TYPE_VOID

if op is add/sub:
  if lhs is ptr/slice and rhs is unsigned/int_lit → return lhs
  if add and lhs is unsigned/int_lit and rhs is ptr/slice → return rhs
  if sub and lhs is ptr/slice and rhs is ptr/slice → return isize

if lhs is int_lit and rhs is numeric → return rhs
if rhs is int_lit and lhs is numeric → return lhs

if not both numeric → return TYPE_VOID
if lhs == rhs → return lhs
if both integer → return the wider bit width
return the one with larger byte size
```

### semanticAnalyzerResolveBitwise (`semantic_analyzer.zig`)

`[inference: int_lit + integer → wider, both same integer type → that type]`

```
if lhs is int_lit and rhs is integer → return rhs
if rhs is int_lit and lhs is integer → return lhs
if lhs != rhs or lhs is not integer → return TYPE_VOID
return lhs
```

### semanticAnalyzerResolveComparison (`semantic_analyzer.zig`)

`[inference: error/enum literal with expected type, then numeric/optional/pointer/error-set/enum comparison, return TYPE_BOOL]`

Special expected-type push for error/enum literals when the other operand has a matching error_set/tagged_union type (markers `CPE`/`CP0`/`CPB`/`CPV`). Then:
- int_lit + numeric → `TYPE_BOOL`
- same numeric → `TYPE_BOOL`
- `==`/`!=`: optional+null, null+optional, error_set+error_set → `TYPE_BOOL`
- same bool → `TYPE_BOOL`
- same pointer → `TYPE_BOOL`
- same enum_type → `TYPE_BOOL`

### semanticAnalyzerResolveLogical (`semantic_analyzer.zig`)

`[inference: both operands TYPE_BOOL → TYPE_BOOL; else TYPE_VOID]`

Dispatched from ResolveExpr for bool_and/bool_or. Emits `LOE`/`LOB`/`LOV`. Returns TYPE_BOOL only if both lhs and rhs are TYPE_BOOL.

### semanticAnalyzerResolveNegate (`semantic_analyzer.zig`)

`[inference: INT_LIT → INT_LIT; numeric → same type; else VOID]`

Dispatched from ResolveExpr for negate and wrap_negate. Returns the inner type if numeric.

### semanticAnalyzerResolveBitNot (`semantic_analyzer.zig`)

`[inference: INT_LIT → INT_LIT; integer → same type; else VOID]`

Dispatched from ResolveExpr for bit_not. Returns the inner type if integer.

### semanticAnalyzerResolveFnCall (`semantic_analyzer.zig`)

`[inference: direct callee → resolve return type → push/pop expected types for params → record coercions]`

**Phase 1 — direct call optimization (callee is ident_expr):**
- Symbol lookup (marker `XF`/`xS`). If `SymbolKind.function` with decl_node:
  - Look up return_type_node in the resolved type table (marker `BR:rnt`).
  - If not resolved, route through `resolveTypeExprFull` with `.module_id = s.module_id` (markers `DRETFB:n`, `BR:fc`); no manual name-cache scan.
  - If `direct_ret != 0`, iterate args against fn params: `call_param_map` (`(decl_cap<<16)|ai`) or `xt_items[params_start+ai]` → `pushExpectedType` → resolve → record into `call_arg_types` → `tryRecordCoercion` (with `errLitSrcType` and a shape-mismatch diagnostic).

**Phase 2 — general callee:**
- Resolve callee expr. If ptr_type pointing to fn_type, dereference.
- If not fn_type: emit `FN3:N/T/K` markers, resolve every argument with `pushExpectedType(0)`, return `TYPE_VOID`.
- **Variadic arity:** read `fnp.flags_packed & 0x01` → `is_var`. When variadic, require `args.len >= params_count` (a short call returns `fnp.return_type` leniently); a non-variadic call requires an exact match. The first `params_count` args are typed against the named params; the extra variadic args are resolved with `pushExpectedType(0)` and recorded into `call_arg_types` (loosely typed).
- Per-arg loop: `pushExpectedType(param_type)` → resolve → `popExpectedType` → `tryRecordCoercion`.

The Phase-1 return-type fallback always routes through `resolveTypeExprFull` with `.module_id = s.module_id`.

### semanticAnalyzerResolveSwitchExpr (`semantic_analyzer.zig`)

`[inference: resolve condition → set switch context → resolve prongs → unify types → return unified]`

1. Increment `switch_depth`. Markers `SE`, `SWI:n/p/d`.
2. Resolve condition. A `tagged_union_type` or `enum_type` condition sets `current_switch_cond_tu` (marker `Z`); an `error_set_type` condition sets `cond_es` (marker `SWES:e`); an `error_union_type` condition sets `cond_es` from its error set (marker `SWEU:e`).
3. Iterate prongs. For each:
   - If else-prong with capture (flag 0x10) → error 3001 "switch else-prong capture ... is not supported".
   - If the condition is enum/tagged-union and the prong has cases: resolve each `enum_literal`/`undefined_literal` case via `semanticAnalyzerResolveEnumLiteral`; if capture (flag 0x10), register a local decl with the TU field type (or the switch type when the case is empty).
   - If `cond_es != 0` and the prong has cases: resolve `error_literal` cases with `cond_es` pushed as expected type.
   - Resolve the prong body expr, then drain any statements it queued on the stmt worklist back to `sw_base`.
   - **Type unification**: track `unified`/`unified_node`. String-literal prongs resolve toward a `[]const u8` peer; otherwise coercion-aware: if bt can coerce to unified, record coercion; if unified can coerce to bt, swap; if unified is int_lit and bt is numeric → use concrete.
   - **MIX else-branch (non-coercible prong types):** records `resolvedTypeTableSet(..., TYPE_VOID)` for the switch node and **`continue`s to the next prong** — the conflicting prong is skipped from the `unified`-type contribution but ALL remaining prongs still resolve.
4. If no prong contributed a unified type, `unified = TYPE_NORETURN`. Return unified. Marker `SWU:n/t`.

### semanticAnalyzerResolveEnumLiteral (`semantic_analyzer.zig`)

`[inference: switch context → expected type stack → tagged union/enum scan → error or return type]`

1. If `current_switch_cond_tu != 0`: for a tagged-union condition, scan TU fields for a matching name_id and register `enum_value_table[node_idx]=fi`, returning the switch type; for an enum_type condition, scan enum members, register the member value, and return the switch type.
2. If `expected_type_stack` top is a tagged_union: scan fields. If field type is VOID → register enum value, return top type. If field type is non-VOID → error `ERR_3008` "enum literal member requires payload".
3. If field not found in the expected TU → error `ERR_3009` "unknown enum literal member". If the expected type is an enum_type, scan its members and return the type.
4. Fallback → marker `ELV:N`, return `TYPE_VOID` (unresolvable).

### semanticAnalyzerResolveStructInit (`semantic_analyzer.zig`)

`[inference: explicit type → expected type → scan fields → push/pop expected types for each init]`

- If type is tagged_union: iterate field_inits, find matching field by name_id, push expected type, resolve init, record coercion.
- If type is struct: same process on struct fields.
- If type is `union_type` or `packed_union_type`: same process on union members, `resolvedTypeTableSet(node_idx, union_type)`. A bare-union struct literal (`Inner{ .Int = v }`), including nested inside an outer struct literal, resolves to the union type and records its member coercion.

### semanticAnalyzerResolveAssign (`semantic_analyzer.zig`)

`[inference: resolve lhs → push expected type for rhs → try coercion → error or return lhs type]`

Special case: if lhs is ident_expr with name `_`, resolve rhs but discard (explicit discard). Otherwise `pushExpectedType(lhs)` → resolve rhs → compute effective source via `errLitSrcType`; if the assignment would implicitly discard `volatile`, emit that diagnostic and return VOID; if assignable, `tryRecordCoercion` and return lhs. On mismatch, emit a type-mismatch diagnostic (with source/target TypeKind notes), raising the level to a hard error for fn-ptr calling-convention mismatch or `(b)`-shape mismatch. Markers `ASE`, `AS0`, `AS1`, `AS2`.

### semanticAnalyzerResolveFnBody (`semantic_analyzer.zig`)

`[inference: clear locals → register params → set current_fn_return → call stmt iter]`

1. Clear `local_decl_count` and `local_consts.count`.
2. Resolve fn_decl node, get `FnProto`. If the resolved fn type is variadic and `stdcall` (`FN_FLAG_STDCALL`), emit `ERR_3012` "variadic functions cannot use the stdcall calling convention".
3. For each param: if `child_0 != 0` (has type annotation), look up resolved type from RTT or set `TYPE_UNDEFINED`. Register as local decl (markers `RT:P/A/T/M`).
4. Set `current_fn_return` from `resolvedTypeTableGet(proto.return_type_node)` and `current_fn_name` from `proto.name_id`.
5. Resolve body via `semanticAnalyzerResolveStmt(body_node)`. Then, if `fnReturnRequiresValue(current_fn_return)` and the body does not definitely terminate (`astTerminates`), emit `ERR_3003` "missing return: not all control paths return a value".
6. Emit `EVC:N`/`EVC:C` enum-value-table count/cap markers.


### semanticAnalyzerResolveStmtIter (`semantic_analyzer.zig`)

`[inference: worklist-based iteration over statement tree]`

Worklist (stack-based) traversal. Pushes stmt children in reverse order for pre-order processing. Handles:
- `block` → push children in reverse (last first for correct order after pop).
- `var_decl` → resolve type annotation (ident_expr via `resolveExpr` with a `resolveTypeExprFull` fallback, else RTT / `resolveTypeExprFull`). Resolve init with push/pop expected type. Infer an error-literal type by scanning the registry for a containing error set; emit `ERR_3010` for an un-inferable enum literal. Record coercions (with a `volatile`-drop guard). Push a function-local `const` into `local_consts`. Register local decl + name cache; diagnostics for mismatches.
- `if_stmt` → resolve header, push else then then (for correct worklist order).
- `while_stmt` → resolve header, push body.
- `for_stmt` → resolve header, push body.
- `return_stmt` → `resolveReturnStmt`.
- Assignments → `semanticAnalyzerResolveExpr`.
- `defer_stmt`/`errdefer_stmt` → run `semanticAnalyzerCheckDeferBody` (Task 10D outward-control-flow rejections `ERR_3051`–`ERR_3054`), then bump `defer_depth`, recurse into the body, decrement.
- **`labeled_stmt` → transparent unwrap:** if `child_0 != 0`, push it onto the stmt work queue — the label is a pure wrapper, the inner statement resolves as if unlabeled. (A `labeled_stmt` reaching `resolveExpr` re-enters the stmt iter and returns `TYPE_VOID`, preventing the `error[3020]` unhandled-else.)
- `break_stmt`/`continue_stmt` → no-op here (validated by `constraint_checker.zig`).
- Other → `semanticAnalyzerResolveExpr`; if the result is an error union, emit `ERR_3015` "error union result is ignored".

Skips `fn_decl` children (inner functions handled by outer phase).

#### Worklist strategy: why iterative, not recursive

`semanticAnalyzerResolveStmtIter` is explicitly iterative: it pushes the root statement onto `stmt_work`, then pops/processes in a `while` loop until drained back to the entry `sp_base`. Three reasons this design was chosen over plain recursion:

1. **Bounded C-call depth for statement trees.** The companion pre-pass `resolveStmtTypes` (main.zig) is recursive and hard-caps its depth. The real semantic pass must not blow the bootstrap C89 stack on deeply nested blocks; the worklist keeps C-call depth flat regardless of statement nesting.
2. **Explicit source-order traversal.** Children are pushed in reverse so the pop order is pre-order source order — the same guarantee a recursive descent gives, without recursion. `constraintCheckerCheckBreakContinue` uses the same explicit-`(node_idx, depth)`-stack pattern.
3. **Per-module lifecycle.** The worklist lives on the `SemanticAnalyzer`, which is created per module on the scratch arena. `sp_base` is captured at entry, so every fn body drains exactly back to its base — the worklist is always empty (at base) between fn bodies and dies with the module's scratch reset.

The worklist is statement-scoped: *expression* subtrees are still resolved recursively via `semanticAnalyzerResolveExpr`, which re-enters the worklist only for statement-like nodes (var_decl/defer/errdefer). A deep expression nest still recurses; the worklist absorbs only statement nesting.

### semanticAnalyzerResolveStmt (`semantic_analyzer.zig`)

`[inference: delegate to semanticAnalyzerResolveStmtIter]`

Public entry point. Thin wrapper around semanticAnalyzerResolveStmtIter.

### semanticAnalyzerResolveTryExpr (`semantic_analyzer.zig`)

`[inference: resolve inner → error_union → payload type]`

If inner is error_union_type, return `eu.payload`. Else return `TYPE_VOID`.

### semanticAnalyzerResolveOrelseExpr (`semantic_analyzer.zig`)

`[inference: null + expected optional → wrap_optional_null coercion → payload type; optional → unwrap_optional coercion → payload type]`

Cases:
- Inner is `TYPE_NULL` and expected type is non-zero: if expected is optional, extract payload, add `wrap_optional_null` coercion, return payload.
- Inner is `optional_type`: extract payload, add `unwrap_optional` coercion; if an `orelse` RHS exists, push the payload as its expected type, resolve it, and record a coercion; return payload.
- Otherwise emit `ERR_3016` "orelse requires an optional operand; use 'catch' for error unions" and return `TYPE_UNDEFINED`.

### semanticAnalyzerResolveIfExpr (`semantic_analyzer.zig`)

`[inference: resolve header → resolve then/else → unify against expected type, else pairwise]`

Unification first honors an expected type from the enclosing context (`topExpectedType`). If both branches are assignable to it (with string literals typed `*const [N]u8` and treated as slice coercions), both are coerced to the expected type and it is returned. Otherwise the pairwise priority is:
- No else → return then_type
- then == else → return either
- then is noreturn → return else
- else is noreturn → return then
- then is int_lit, else is numeric → coerce then, return else
- else is int_lit, then is numeric → coerce else, return then
- then is VOID → return else
- else is VOID → return then
- Otherwise → return TYPE_VOID (type mismatch)

### semanticAnalyzerCaptureType (`semantic_analyzer.zig`)

`[inference: if optional → unwrap payload; else return cond_type as-is]`

Unwraps optional types in if/while/for capture expressions. If cond_type is optional, returns the payload type; otherwise returns cond_type unchanged.

### semanticAnalyzerResolveIfHeader / ForHeader / WhileHeader

`resolveIfHeader` (`semantic_analyzer.zig`):
`[inference: resolve condition → if_capture → registerLocalDecl with captured type]`
Capture unwraps optional via `semanticAnalyzerCaptureType`.

`resolveForHeader` (`semantic_analyzer.zig`):
`[inference: resolve iterable → slice/array/range → element type → register capture + index]`
If payload (capture name), register local decl with element type. If child_2 (index name), register with `TYPE_USIZE`. When the iterable is a `range_exclusive`/`range_inclusive` node, its start/end operands are resolved by that node's own arm of `semanticAnalyzerResolveExpr` (Task 11P), so operands whose lowering needs the resolved-type table (e.g. `.len` on a struct/union array or slice field) get resolved-type entries.

`resolveWhileHeader` (`semantic_analyzer.zig`):
`[inference: resolve condition → while_capture → registerLocalDecl]`
Same capture logic as if-header. Also resolves `child_2` (the `while` continue expression) so nested field stores there have resolved types.

### semaTraceStep (`semantic_analyzer.zig`)

`[inference: follow ident_expr → var_decl → slice_expr → ident_expr chain, up to 3 steps]`

Source-tracing helper for index-access error messages. Follows a variable name through up to 3 levels of var_decl/slice_expr indirection to find the original source name. Called by semanticAnalyzerResolveIndexAccess.

### semanticAnalyzerResolveIndexAccess (`semantic_analyzer.zig`)

`[inference: resolve index → resolve base → trace source → indexed elem type]`

Resolve child_1 (index), then child_0 (base), saving/restoring `_stub_0`. If base is `ident_expr`, trace back up to 3 steps through var_decl → slice_expr → ident_expr chain to find source name (for error messages) and record it via `resolvedSourceTableSet`. Returns `typeRegistryIndexedElemType`, or the tuple's first element type, or the base type. If the base is a scalar/aggregate that is not indexable, emits a hard `error[3000]` "cannot index a value of non-array, non-pointer type" instead of silently returning the base type.

### semanticAnalyzerResolveSliceExpr (`semantic_analyzer.zig`)

`[inference: resolve base → validate base kind → resolve bounds → create slice type from elem]`

Resolves child_0 (base/elem), child_1 (start), child_2 (end). Emits `error[2000]` "cannot slice base type: expected array, slice, or many-pointer" unless the base is an array/slice/many-ptr/ptr. Determines element type via `typeRegistryIndexedElemType`. Creates slice type with const flag from base type's flags.

### semanticAnalyzerResolveTupleLiteral (`semantic_analyzer.zig`)

`[inference: resolve each element → append to xt → create tuple type]`

Each element resolved. If element resolves to VOID, substitutes TYPE_I32. Appends types to `registry.xt_items`. Returns `typeRegistryGetOrCreateTuple(start, count)`.

### semanticAnalyzerResolveArrayInit (`semantic_analyzer.zig`)

`[inference: resolve child_0 annotation (or infer `[_]T` elem) → push element expected type → create array type]`

If `child_0` has a resolved array type, return it directly. Otherwise resolve an explicit `array_type` annotation (including a `[_]T` inferred-length annotation, whose element type is resolved and used as the expected type for every element). Element types come from char_literal → u8, int_literal → u32, else resolve with the element expected type pushed. With an annotation, returns the annotation type; otherwise creates an array type from the first element and the element count.

### errLitSrcType (`semantic_analyzer.zig`)

`[inference: if child is error_literal and target is error_union → return error_set; else ret_val]`

Helper for tryRecordCoercion and resolveReturnStmt. Extracts the error set type from an error union target when the source node is an error literal.

### resolveReturnStmt (`semantic_analyzer.zig`)

`[inference: push expected fn return → resolve expr → record coercion]`

Bare return: if `fnReturnRequiresValue(current_fn_return)` → `ERR_3003` "return with no value in function returning non-void". Otherwise `pushExpectedType(current_fn_return)` → resolve → `popExpectedType`. If the return type is non-zero non-void: emit `T2F:*` markers, compute the effective source via `errLitSrcType`, emit a shape-mismatch diagnostic when not assignable, then `tryRecordCoercion`.

### tryRecordCoercion (`semantic_analyzer.zig`)

`[inference: classifyCoercion → if non-none or null→ptr, add to coercion table]`

Emits `COE:N/S/D/SK/DK/NK` markers. If src == dst or src is UNDEFINED → skip. Calls `semanticAnalyzerMaybeDiagVolatileDrop`; if the coercion would implicitly discard a `volatile` qualifier, emit the diagnostic and record nothing. If not assignable → skip. Calls `classifyCoercion(registry, src, dst)` (marker `CCK:ca`). If coercion kind is not `none`, or src is null and dst is pointer → `coercionTableAdd(node, ck, dst_type)` (markers `COR:N/K`).

### Marker Reference

`File` is `sema` (`semantic_analyzer.zig`) unless noted.

| Marker | File | Meaning |
|--------|------|---------|
| `IDE\n` | sema | Resolve ident entry |
| `SEM:vi` | sema | Name is underscore (void ident) |
| `D7:Yn D7:n D7:t D7:<t>` | sema | Local decl found |
| `L\n L:t` | sema | Local resolved |
| `S\n` | sema | Symbol lookup |
| `TAL\n` | sema | Type alias resolved |
| `STY:N STY:T STY:C` | sema | Symbol type found (+ cached variant) |
| `SVO\n` | sema | Symbol is void |
| `C2:T` | sema | Name cache hit |
| `D8:*` | sema | Debug dump for node [450,660] |
| `IDT:<n>:VOID\n` | sema | Ident is void (unresolved) |
| `SCT:n SCT:t` | sema | Local decl registered |
| `FAE\n` | sema | Field access entry |
| `PFA:BK PFA:FN` | sema | Base kind + field name |
| `Q1:FL Q1:KL Q1:TL Q1:FN` | sema | Module-qualified lookup |
| `Q1FX\n` | sema | Cross-module fn decl |
| `BR:x BR:rt BR:fnr` | sema | Bridge fn return resolution |
| `BR:treN BR:treT BR:dv BR:ft` | sema | Bridge fallback through `resolveTypeExprFull` |
| `FAPR:OK FAPR:DK` | sema | Ptr deref in field access |
| `FT:TAG` / `FP:PAYLOAD` | sema | Tagged-union tag/payload field |
| `MFA\n` / `MF1\n` / `MFF\n` / `MFP` | sema | Module field access |
| `MF2` / `MF3\n` | sema | Module field fallback |
| `FSL:USIZE\n` | sema | Slice `.len` → usize |
| `FSP:PTR\n` | sema | Slice `.ptr` → many-ptr |
| `FAA:USIZE\n` | sema | Array `.len` → usize |
| `FF\n` | sema | Unknown base type |
| `FF:R` | sema | Field found result |
| `NF\n FF2:N FF2:F FF2:B` | sema | Field not found |
| `COE:N COE:S COE:D` | sema | Coercion attempt |
| `COE:SK COE:DK COE:NK` | sema | Src/dst TypeKind + node kind |
| `CS1\n` / `CS4\n` | sema | null-source coercion sites |
| `CCK:ca` | sema | classifyCoercion result (tryRecordCoercion) |
| `CCK:vr` | sema | classifyCoercion result (var-decl path) |
| `COR:N COR:K` | sema | Coercion recorded |
| `FNE\n` | sema | Fn call entry |
| `XF\n` / `xS\n` | sema | Direct-callee symbol hit/miss |
| `FN1\n FN1:R` | sema | Direct call resolved |
| `FN2\n` | sema | Callee void |
| `FN3:N FN3:T FN3:K` | sema | Not a fn type |
| `FN4a-FN4g` | sema | Fn call param resolution |
| `FN4:R` | sema | Fn call return |
| `PTM:A PTM:T PTM:N` | sema | Param type marker |
| `SF:H` | sema | Resolved fn-type param lookup |
| `BR:rnt DRETFB:n BR:fc BR:fnr` | sema | Direct return-type resolution |
| `T2F:C T2F:R T2F:F` | sema | Return coercion tracking |
| `LOE` / `LOB LOV` | sema | Logical op entry / bool or void |
| `CPE` / `CP0 CPB CPV` | sema | Comparison entry / outcomes |
| `SIF:0N-7N` / `SIF:FN` | sema | If-expr type unification |
| `SE` / `SWI:n SWI:p SWI:d` | sema | Switch expr entry / info |
| `P0: n` / `PL0:n` | sema | Switch with no payload / no prongs |
| `SWES:e` / `SWEU:e` | sema | Switch condition error-set / error-union |
| `Z` | sema | Switch enum/tagged-union condition |
| `PCT:C PCT:P` | sema | Prong context |
| `CC:K` | sema | Case kind |
| `SCE:p SCE:l SCE:R` | sema | Switch capture entry |
| `SCFE:n SCFE:t SCFE:k` / `SCAX:N SCAX:T` | sema | Switch capture field |
| `PBD:N PBD:K` / `PCT:n PCT:b PCT:f` | sema | Prong body details |
| `SWPB:i SWPB:t` | sema | Sw prong body type |
| `MIX:P MIX:U MIX:B MIX:tk MIX:uk MIX:cd MIX:b MIX:pf MIX:pn MIX:ni` | sema | Mixed prong types |
| `SWU:n SWU:t` | sema | Switch unified type |
| `eL\n EL:N EL:F EL:C EL:V EL:M` | sema | Enum literal entry |
| `ELV:N` | sema | Enum literal void |
| `ASE` / `AS0 AS1 AS2` | sema | Assign entry / outcomes |
| `RXS RXS:n` | sema | Switch in expr dispatch |
| `FAD:R` | sema | Field access result |
| `STX:n STX:k STX:r` | sema | Expression result |
| `A4:N A4:K A4:R` | sema | After-expr markers |
| `STB:N STB:R` | sema | Type table set |
| `AW:R` | sema | Array-init entry |
| `EBLK:N EBLK:C EBLK:S EBLK:D` | sema | Block-expr resolution |
| `ST:N ST:K` | sema | Unhandled node kind |
| `FB` | sema | Fn body entry |
| `RT:P RT:A RT:T RT:M` | sema | Fn param registration |
| `EVC:N EVC:C` | sema | Enum-value table count/cap |
| `SP:n SP:K` | sema | Stmt worklist pop |
| `BLK:N BLK:C` | sema | Block iteration |
| `BCK:B BCK:I BCK:N BCK:K` / `]\n` | sema | Block child push |
| `VD:N VD:C` | sema | Var decl |
| `D10:C0 D10:C1 D10:IK` | sema | Var-decl payload-55 debug |
| `VRT:<n>:<t>` | sema | Var resolved type |
| `I:K` | sema | Init node kind |
| `VDIAG:void_var` / `VFLOW:vdag` | sema | void-typed var diagnostic |
| `REG:cp REG:ct` | sema | Name cache register |
| `IFST:N IFST:C IFST:K IFST:2 IFST:K2` | sema | If-header details |
| `WST:N WST:K` | sema | While-header body kind |
| `FS:C FS:CK FS:T FS:P FS:E FS:M` | sema | For-header details |
| `D4F:N D4F:T` / `FIX2:LN` | sema | For capture / index registration |
| `ELS:n ELS:k ELS:c` | sema | Fallback stmt kind |
| `IXA:N` / `C0K:K` | sema | Index access entry / base kind |
| `STE:N` / `SRC:N SRC:S` | sema | Source trace entry / name |
| `IX:T IX:R` | sema | Index type result |
| `CC:nul` | coercion | classifyCoercion: null target |
| `CLS:p<base>e<elem>` | coercion | classifyCoercion: ptr-to-slice check |

---

## coercion.zig (`sf/src/coercion.zig`, 211 lines)

### CoercionKind enum (`sf/src/coercion.zig`)

| # | Variant | When |
|---|---------|------|
| 0 | `none` | No coercion needed / identity |
| 1 | `wrap_optional` | Source assignable to optional payload |
| 2 | `wrap_error_success` | Source assignable to error union payload |
| 3 | `wrap_error_err` | Source is error_set, target is error_union |
| 4 | `unwrap_optional` | optional → payload (orelse) |
| 5 | `array_to_slice` | [N]T → []T |
| 6 | `array_to_many_ptr` | [N]T → [*]T |
| 7 | `slice_to_many_ptr` | []T → [*]T |
| 8 | `string_to_slice` | [*c]u8 → []const u8 |
| 9 | `string_to_many_ptr` | [*c]u8 → [*c]u8 (identity) |
| 10 | `string_to_ptr` | [*c]u8 → *u8 |
| 11 | `ptr_to_optional_ptr` | *T → ?*T |
| 12 | `const_qualify` | T → const T (ptr/slice/many_ptr) |
| 13 | `int_widen` | Same-signedness, smaller → larger integer |
| 14 | `float_widen` | f32 → f64 |
| 15 | `int_literal_coerce` | Integer literal type → concrete numeric |
| 16 | `wrap_optional_null` | null → ?T (null → optional) |

### classifyCoercion (`sf/src/coercion.zig`)

`[inference: type-kind dispatch on source/target for 20+ checks, return CoercionKind]`

Deterministic check order:

1. `source == target` → `none`
2. Source kind is `noreturn_type` or `undefined_type` → `none`
3. `integer_literal_type` + `isNumeric(target)` → `int_literal_coerce`
4. Both integer (source not `TYPE_INT_LIT`), same signedness, source width < target width → `int_widen`
5. `TYPE_F32` → `TYPE_F64` → `float_widen`
6. `null_type` (marker `CC:nul`): `isPointer(target)` → `none`; `optional_type` → `wrap_optional_null`; `fn_type` → `none`.
7. Target is `optional_type`: if source assignable to payload → `wrap_optional`; if source is null → `none`.
8. Target is `error_union_type`: if source assignable to payload → `wrap_error_success`.
9. Source is `error_set_type` and target is `error_union_type`: → `wrap_error_err`.
10. ptr→ptr (qualifier-monotone under `VOLATILE_FLAG`): if either base is VOID → `none`; if target is const, source is not, same base → `const_qualify`.
11. slice→slice: if target is const, source is not, same elem → `const_qualify`.
12. many_ptr→many_ptr: if target is const, source is not, same base → `const_qualify`.
13. array→slice: same elem → `array_to_slice` (const target variant too).
14. array→many_ptr: same elem → `array_to_many_ptr`.
15. array→array: same elem and same length → `none` (identity).
16. ptr→many_ptr: if the source pointee is an array and its elem matches the many-ptr base → `none` (array-to-pointer decay).
17. slice→many_ptr: same elem → `slice_to_many_ptr`.
18. ptr→optional: if the optional payload is a ptr and source is assignable → `ptr_to_optional_ptr`.
19. u8↔c_char: `none` (identity).
20. ptr→slice (marker `CLS:p<base>e<elem>`): only a pointer to a **known-length array** whose elem matches the slice elem decays → `array_to_slice`. A bare `*const u8`/`*const c_char` → slice is NOT a coercion (no length; must not become a length-1 slice).
21. Fallback → `none`.


### CoercionTable (`sf/src/coercion.zig`)

```zig
pub const CoercionTable = struct {
    entries_items: [*]CoercionEntry,
    entries_len: usize,
    entries_cap: usize,
    entries_alloc: *Sand,
    index: hash_mod.U32ToU32Map,  // node_idx → entry_idx
};
```

Flat array of `CoercionEntry{node_idx, kind, target_type}` + hash index by node_idx.

#### coercionTableInit

`[inference: zero-cap entries, empty index, allocator bound]`

Returns a fresh `CoercionTable` bound to the given `Sand` allocator.

#### coercionTableAdd

`[inference: upsert pattern — get-or-insert in index, update existing or append new entry]`

If node_idx already in index, update entry in-place. Otherwise ensure capacity, append, add to index.

#### coercionTableEnsureCapacity

`[inference: grow-by-doubling from 8, in-place realloc or memcpy, update cap]`

Internal grow helper for CoercionTable. Called by coercionTableAdd when entries_len >= entries_cap.

#### coercionTableGet

`[inference: index lookup → entry or null]`

Simple hash lookup. Returns `?CoercionEntry`.

---

## resolved_type_table.zig (`sf/src/resolved_type_table.zig`, 234 lines)

Maps AST nodes to their resolved types and source names. Used by semantic analysis and lowering. The type relation is now a **dense, block-addressed spill table** (Disk/Ram backend); the source relation is a small sparse resident hash map.

### ResolvedTypeTable (`sf/src/resolved_type_table.zig`)

```zig
pub const ResolvedTypeTable = struct {
    cap: usize,                  // logical node extent (file covers blocks up to aligned(cap))
    entries_alloc: *Sand,        // supplies the resident cache window + Ram buffer
    spill: spill_mod.SpillStore, // dense spill (Disk/Ram backend)
    spill_path: [512]u8,
    spill_path_len: usize,
    cache_buf: [*]u8,            // RTT_SLOTS * RTT_BLOCK_BYTES resident window
    cache_allocated: u8,
    slot_block: [8]u32,          // resident slot -> block index (EMPTY_BLOCK = empty)
    slot_dirty: [8]u8,           // write-back flag per resident slot
    ring_next: u32,              // next eviction candidate
    src_map: hash_mod.U32ToU32Map, // sparse resident node_idx -> source_name_id (only-on-Set)
};
```

The dense record is `{ type_id u32 @0, present u8 @4 }` = 5 B/node (the old inlined source half is gone). Block geometry constants: `RTT_BLOCK_NODES = 409`, `RTT_BLOCK_BYTES = 2045`, `RTT_REC_BYTES = 5`, `RTT_SLOTS = 8`. `file_byte_off = block * RTT_BLOCK_BYTES + (node_idx % RTT_BLOCK_NODES) * 5`.

### Lifecycle and accessors

- `resolvedTypeTableInit(alloc)` — zero-cap table; `spill_path` defaults to `.zig1_res.tmp`, all slots empty, `src_map` empty.
- `resolvedTypeTableSetSpillPath(self, path)` — override the spill filename.
- `resolvedTypeTableReserve(self, node_count)` — extend the dense extent (block-aligned zero-fill).
- `resolvedTypeTableSet(self, node_idx, type_id)` — fault the block into a resident slot, write the 5-byte record with `present=1`, mark the slot dirty.
- `resolvedTypeTableGet(self, node_idx) -> ?TypeId` — `null` if `node_idx >= cap` or `present==0`; otherwise the stored TypeId.
- `resolvedSourceTableSet(self, node_idx, source_name_id)` / `resolvedSourceTableGet(self, node_idx) -> ?u32` — the sparse `src_map`; used by `semanticAnalyzerResolveIndexAccess` to trace variable sources through var_decl → slice_expr chains.
- `resolvedTypeTableClose(self)` — write back dirty slots and close the spill.

Internally, `rttExtend` grows the block-aligned dense extent, `rttBlockEnsure` evicts/writes back the ring victim and faults a block into the resident window, and `rttWriteU32`/`rttReadU32` encode the little-endian record. A spill extent beyond `SEEK_MAX` panics via `panicHandler`.

---

## constraint_checker.zig (`sf/src/constraint_checker.zig`, 113 lines)

Three independent validation passes run after semantic analysis. `checkReturnType` is also re-run by the phase driver against each resolved return statement.

### checkReturnType (`sf/src/constraint_checker.zig`)

`[inference: if return_stmt with no child and fn returns non-void/noreturn → error; if return expr not assignable → error]`

Two checks:
- `child_0 == 0` (bare return): if `current_fn_return` is non-void and non-noreturn → `ERR_3003` "return with no value in function returning non-void".
- `child_0 != 0`: if `return_expr_type != 0` and not assignable to `current_fn_return` → error "return type mismatch" (generic code 0).

### checkSwitchExhaust (`sf/src/constraint_checker.zig`)

`[inference: resolve cond type → if enum/tagged_union → count prong items → if covered < total and no else → error]`

- Only checks enum_type and tagged_union_type conditions (any other condition type is skipped).
- Counts total members from `en_items` or `tu_items`.
- Iterates prongs, summing case item counts (flag bit 0 = else).
- If `has_else == 0` and `covered_count < member_count` → `ERR_3004` "switch not exhaustive".

### constraintCheckerCheckBreakContinue (`sf/src/constraint_checker.zig`)

`[inference: DFS stack with depth tracking — break/continue at depth 0 → error]`

Explicit-stack iterative traversal (avoiding recursion depth limits). Each stack entry pairs `(node_idx, depth)`. Deeper `while_stmt`/`for_stmt` increments depth. If `break_stmt`/`continue_stmt` at depth == 0 → error "break/continue outside loop" (generic code 0). Pushes `child_0`–`child_2` and the node's extra children with the current depth.

---

## assign_helper.zig (`sf/src/assign_helper.zig`, 5 lines)

A single small helper shared with lowering: `resolveAssignedLocalTemp(lt_ptr, ln_ptr, count, temp_id)` reverse-scans the parallel local-type/local-name arrays (`count` entries) and returns the local name id whose type id equals `temp_id`, or `0` if none matches. It lets the lowerer recover a source variable name for a temp that was assigned from a local.

---

## Data Flow

```
semanticAnalyzerResolveFnBody(decl)
  │
  ├─ Resolve params: local_decl_names/types[] += param types from RTT
  ├─ Set current_fn_return
  │
  └─ semanticAnalyzerResolveStmt(body)
       │
       └─ semanticAnalyzerResolveStmtIter(root_node)
            │
            ├─ Worklist: push children in reverse order
            │
            ├─ For each stmt/expr node:
            │   │
            │   ├─ semanticAnalyzerResolveExpr(node) → TypeId
            │   │   │
            │   │   ├─ pushExpectedType / popExpectedType (contextual hints)
            │   │   ├─ resolve child exprs recursively
            │   │   ├─ resolvedTypeTableSet(node_idx, result)  ──┐
            │   │   ├─ tryRecordCoercion(node, src, dst)         │
            │   │   │   └─ coercionTableAdd(node, kind, dst)  ───┤
            │   │   └─ return TypeId                             │
            │   │                                                │
            │   └─ ResolvedTypeTable ────────────────────────────┤
            │        node_idx → TypeId                           │
            │        node_idx → source_name_id (index access)    │
            │                                                    │
            └─ After all stmts exhausted:                        │
                                                                    │
                    CoercionTable ────────────────────────────────┤
                      node_idx → {kind, target_type}               │
                                                                    │
                    ↓ constraint checks                             │
                    checkReturnType                                 │
                    checkSwitchExhaust                              │
                    constraintCheckerCheckBreakContinue              │
                                                                    │
                    ↓ Ready for lowering (phase 7)                  │
                    Each expression node has either:                │
                    - resolvedTypeTableGet(node) → TypeId           │
                    - coercionTableGet(node) → CoercionEntry        │
                    - or no entry (identity type)                   │
```

---

## Debugging

### Key Markers for Tracing

**Expression resolution tracing:**
- `STX:n<i> STX:k<k> STX:r<r>` — every resolved expr with node index, AstKind, result TypeId
- `A4:N A4:K A4:R` — same, emitted just after resolve, before RTT set
- `STB:N STB:R` — confirmation of RTT set

**Field access tracing:**
- `FAE\n PFA:BK<bk> PFA:FN<fn>` — entry with base kind and field name
- `FF:R<r>` — field found, returning type id
- `NF\n FF2:N<idx> FF2:F<name> FF2:B<base>` — field not found

**Fn call tracing:**
- `FNE\n` — entry
- `FN1\n FN1:R<r>` — direct call with resolved return
- `FN4a-FN4g` — param-by-param resolution with `PTM:A<T>M:T<T>M:N`

**Switch tracing:**
- `SE\n SWI:n<idx> SWI:p<payload>` — entry
- `PCT:C<cond_tu> PCT:P<prong_payload>` — per-prong context
- `SWPB:i<idx> SWPB:t<type>` — per-prong body resolved type
- `SWU:n<idx> SWU:t<unified>` — final switch type

**Variable declaration tracing:**
- `VD:N<name> VD:C<count>` — var decl start
- `VRT:<node>:<type>` — resolved type annotation
- `IK:K<kind>` — init node kind
- `REG:cp<name> REG:ct<type>` — name cache put

### Expected-Type Stack Inspection

The expected-type stack is a dynamic array on the scratch arena. To inspect at runtime:
- `self.expected_type_stack_items[self.expected_type_stack_len - 1]` — current top
- `self.expected_type_stack_len` — current depth

Breakpoints for stack state:
- `pushExpectedType` in `semantic_analyzer.zig` — watch `ty` parameter
- `popExpectedType` in `semantic_analyzer.zig` — watch `self.expected_type_stack_len` decrement

Use cases for expected-type stack:
- Error literals: expected type provides error set context
- Enum literals: expected type provides tagged union context
- Fn call args: expected type = param type
- Return stmts: expected type = fn return type
- Assignments: expected type = lhs type
- Struct init: expected type = field type per field

### GDB Breakpoints

```gdb
# Entry to semantic analysis for a module
break semanticAnalyzerResolveFnBody

# Every expression resolution
break semanticAnalyzerResolveExpr

# Every coercion insertion
break tryRecordCoercion

# Expected-type stack operations
break pushExpectedType
break popExpectedType

# Identifier resolution
break semanticAnalyzerResolveIdent

# Field access
break semanticAnalyzerResolveFieldAccess

# Switch expression (complex unification)
break semanticAnalyzerResolveSwitchExpr

# Return statement with coercion
break resolveReturnStmt

# Variable declaration type checking
break semanticAnalyzerResolveStmtIter

# Constraint checks
break checkReturnType
break checkSwitchExhaust
break constraintCheckerCheckBreakContinue
```

### Print commands for debugging

```gdb
# Print current fn return type
print self.current_fn_return

# Print expected type stack top
print self.expected_type_stack_items[self.expected_type_stack_len - 1]

# Print local decls count
print self.local_decl_count

# Print switch context
print self.current_switch_cond_tu

# Print coercion table entry for a node
print coercionTableGet(self.coercion_table, node_idx)
```
