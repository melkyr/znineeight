# 05 — Semantic Analysis

## Summary Table

| Artifact | Count | Notes |
|----------|-------|-------|
| `SemanticAnalyzer` fields | 34 | 17 direct + 8 builtin name IDs + 9 internal |
| Expression kind dispatch arms | 36+ | Every `AstKind` handled in `semanticAnalyzerResolveExpr` |
| `CoercionKind` variants | 18 | `none` through `wrap_optional_null` |
| Coercion checks in `classifyCoercion` | ~18 | Null, optional, error union, ptr, slice, array, widening |
| Marker codes | ~40+ | `IDE`, `D7`, `L`, `S`, `STY`, `FAE`, `PFA`, `FAPR`, `COE`, `CCK`, `COR`, `SIF`, etc. |
| Expected-type stack | stack-based | Push/pop in calls, returns, assigns, struct init, var decls |
| Resolved type table | `node_idx→TypeId` | 2 hash maps (type + source name) |
| Constraint checks | 3 | Return type, switch exhaust, break/continue validation |

---

## semantic_analyzer.zig (`sf/src/semantic_analyzer.zig`, 1841 lines)

Central phase-5 engine. Walks function bodies bottom-up via a worklist and resolves every expression to a `TypeId`. Records coercions for lowering and emits diagnostics for type errors.

### SemanticAnalyzer struct (`sf/src/semantic_analyzer.zig:22-61`)

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
    call_arg_types: *hash_mod.U32ToU32Map,
    call_param_map: *hash_mod.U32ToU32Map,
    current_switch_cond_tu: u32,
    switch_depth: u32,
    local_decl_names: [*]u32,
    local_decl_types: [*]u32,
    local_decl_count: usize,
    local_decl_cap: usize,
    _stub_0: u32,
    _stub_1: u32,
    interner: *interner_mod.StringInterner,
    // 8 builtin name IDs:
    ptrcast_name_id, ptrtoint_name_id, inttoptr_name_id,
    intcast_name_id, floatcast_name_id, inttofloat_name_id,
    inttoenum_name_id, size_of_name_id, align_of_name_id,
};
```

Key state: expected-type stack for contextual type inference (enum literals, error literals, null), statement worklist for iterative traversal, switch context for enum literal resolution, and local declaration shadow stack.

### semanticAnalyzerInit (`sf/src/semantic_analyzer.zig:63-124`)

`[inference: sandAlloc-builtin name interning, zero-init stacks/lists, return SemanticAnalyzer]`

Allocates no heap memory in the struct itself. Interns 8 builtin names (`@ptrCast`, `@ptrToInt`, `@intToPtr`, `@intCast`, `@floatCast`, `@intToFloat`, `@intToEnum`, `@sizeOf`, `@alignOf`) plus the discard identifier `_`. Stacks and work arrays are zero-capacity — grown on first use.

### pushExpectedType / popExpectedType (`sf/src/semantic_analyzer.zig:1443-1468`)

`[inference: grow-by-doubling from 64, write/inc or dec stack pointer]`

```
pushExpectedType(self, ty):
  if stack full: grow to max(64, cap*2) bytes
  items[len] = ty; len += 1

popExpectedType(self):
  if len > 0: len -= 1

topExpectedType(self) -> u32:
  if len == 0: return 0
  return items[len-1]
```

Used for contextual type inference: fn call args, return stmts, assigns, struct init fields, var decl init, if/else unification, enum/error literals.

### semanticAnalyzerResolveIdent (`sf/src/semantic_analyzer.zig:174-228`)

`[inference: local-decl stack → symbol registry qualified lookup → name cache → TYPE_UNDEFINED → TYPE_VOID]`

Resolution order:
1. **Marker `IDE\n`** — entry
2. **`SEM:vi`** — if name_id == 1 (underscore)
3. **Local declarations** (reverse scan): if `local_decl_names[li] == name_id`, emit `D7:Yn D7:n<name> D7:t D7:<type> L\n L:t<type>` and return type.
4. **Symbol registry**: `symbolRegistryQualifiedLookup(symbols, module_id, name_id)`:
   - `type_alias` → return `s.type_id` (marker `TAL\n`)
   - `s.type_id != 0` → return `s.type_id` (marker `STY:N STY:T`)
   - else → return `TYPE_VOID` (marker `SVO\n`)
5. **Name cache**: `nameCacheGet(registry, name_id)` → return cached type.
6. **Debug detail `D8:*`**: if node_idx in [450, 660], dump name, node kind, resolved type.
7. If name_id == `_stub_0` (discard) → return `TYPE_UNDEFINED`.
8. Fallback → return `TYPE_VOID` (marker `IDT:<name>:VOID\n`).

### semanticAnalyzerResolveFieldAccess (`sf/src/semantic_analyzer.zig:230-485`)

`[inference: resolve base expr → type-kind dispatch on TypeKind for field lookup → resolvedTypeTableSet]`

Entry: `FAE\n PFA:BK<kind> PFA:FN<name_id>`.

**Phase 1 — ident_expr base (module-qualified, type alias fields):**
- If base is `ident_expr` and resolves to a symbol:
  - `type_alias` on tagged_union/enum/error_set → scan field/member/error names, return `alias_type_id`.
  - `module` → lookup field in target module. Flags check (bit 1 = `0x2`). If function, resolve fn type via return_type_node (use `resolvedTypeTableGet` or `resolveTypeExprFull`).

**Phase 2 — general field access (non-ident base):**
- Resolve base expr. If `TYPE_VOID`, bail `FB\n`.
- **Pointer dereference**: if ptr_type/many_ptr_type, follow to pointee. Markers: `FAPR:OK FAPR:DK`.
- **Optional guard**: error "cannot access field on optional type".
- **Error union guard**: error "cannot access field on error-union type".

**Phase 3 — type-kind-specific field lookup:**
- `struct_type` → scan `FieldEntry[]` at `st_items[payload_idx].fields_start`.
- `union_type` → scan `FieldEntry[]` at `un_items[payload_idx].fields_start`.
- `tagged_union_type` → scan `FieldEntry[]` at `tu_items[payload_idx].fields_start`. Result is `base_type_id` (the tagged union itself), not the field type.
- `module_type` → `MFA\n` marker. Look up field in target module's symbols. If function, look up resolved fn type.
- `slice_type` → `.len` returns `TYPE_USIZE` (`FSL:USIZE\n`). `.ptr` returns `*elem` (`FSP:PTR\n`).
- `error_set_type` → `typeRegistryErrorSetMemberIndex` check. If found, return `base_type_id`.

**Phase 4 — struct/union/tagged_union field scan:**
```
fi from 0..fields_count:
  if fe_items[fields_start+fi].name_id == field_name_id:
    result = fe.type_id
    if result is array_type: result = *elem (array-to-ptr decay)
    if base is tagged_union: result = base_type_id (tag type)
    return result (marker FF:R<type>)
```

**Phase 5 — not found:** marker `NF\n FF2:N FF2:F FF2:B`, return `TYPE_VOID`.

### Expression Resolution Dispatch — semanticAnalyzerResolveExpr

`sf/src/semantic_analyzer.zig:1131-1382` — master `switch` on `node.kind`:

| Arm | AstKind | `[inference]` | Returns |
|-----|---------|---------------|---------|
| 1 | `int_literal` | `[inference: return TYPE_INT_LIT]` | `TYPE_INT_LIT` (19) |
| 2 | `float_literal` | `[inference: return TYPE_F64]` | `TYPE_F64` (16) |
| 3 | `char_literal` | `[inference: return TYPE_U8]` | `TYPE_U8` (8) |
| 4 | `bool_literal` | `[inference: return TYPE_BOOL]` | `TYPE_BOOL` (2) |
| 5 | `null_literal` | `[inference: return TYPE_NULL]` | `TYPE_NULL` (17) |
| 6 | `undefined_literal` | `[inference: return TYPE_UNDEFINED]` | `TYPE_UNDEFINED` (18) |
| 7 | `unreachable_expr` | `[inference: return TYPE_NORETURN]` | `TYPE_NORETURN` (3) |
| 8 | `string_literal` | `[inference: return [*c]u8]` | `typeRegistryGetOrCreatePtr(TYPE_C_CHAR, true)` |
| 9 | `enum_literal` | → `semanticAnalyzerResolveEnumLiteral` | switch context / expected type |
| 10 | `error_literal` | `[inference: expected-type → error set member lookup]` | error set TypeId or TYPE_VOID |
| 11 | `ident_expr` | → `semanticAnalyzerResolveIdent` | local/symbol/cache/UNDEFINED/VOID |
| 12 | `field_access` | → `semanticAnalyzerResolveFieldAccess` | field type |
| 13 | `index_access` | → `semanticAnalyzerResolveIndexAccess` | elem type / tuple field type |
| 14 | `slice_expr` | → `semanticAnalyzerResolveSliceExpr` | slice type |
| 15 | `deref` | `[inference: ptr/many_ptr → base type]` | `pp.base` or base type |
| 16 | `address_of` | `[inference: return *T for expr of type T]` | `typeRegistryGetOrCreatePtr(base, false)` |
| 17 | `fn_call` | → `semanticAnalyzerResolveFnCall` | return type |
| 18 | `builtin_call` | → dispatch by child_0 | TYPE_INT_LIT / resolved type / arg type |
| 19 | `bool_not` | `[inference: resolve child, return TYPE_BOOL]` | `TYPE_BOOL` |
| 20 | `negate` | → `semanticAnalyzerResolveNegate` | numeric type or VOID |
| 21 | `bit_not` | → `semanticAnalyzerResolveBitNot` | integer type or VOID |
| 22 | `try_expr` | → `semanticAnalyzerResolveTryExpr` | error union payload |
| 23 | `catch_expr` | `[inference: unwrap error union + capture]` | payload type |
| 24 | `orelse_expr` | → `semanticAnalyzerResolveOrelseExpr` | optional payload |
| 25 | `break_stmt` / `continue_stmt` | `[inference: return TYPE_VOID]` | `TYPE_VOID` |
| 26 | `var_decl` / `defer_stmt` / `errdefer_stmt` | → `semanticAnalyzerResolveStmtIter` | `TYPE_VOID` |
| 27 | `if_expr` | → `semanticAnalyzerResolveIfExpr` | unified then/else type |
| 28 | `if_stmt` | `[inference: resolve header, push children to worklist]` | `TYPE_VOID` |
| 29 | `for_stmt` | → `semanticAnalyzerResolveForHeader` | `TYPE_VOID` |
| 30 | `while_stmt` | → `semanticAnalyzerResolveWhileHeader` | `TYPE_VOID` |
| 31 | `swt_ex` | → `semanticAnalyzerResolveSwitchExpr` | unified prong type |
| 32 | `tuple_literal` | → `semanticAnalyzerResolveTupleLiteral` | tuple TypeId |
| 33 | `struct_init` | → `semanticAnalyzerResolveStructInit` | struct/TU TypeId |
| 34 | `array_init` | → `semanticAnalyzerResolveArrayInit` | array TypeId |
| 35 | `ptr_type` / `many_ptr_type` / `array_type` / `slice_type` / `optional_type` / `error_union_type` / `fn_type` / `struct_decl` / `enum_decl` / `union_decl` / `error_set_decl` | `[inference: return TYPE_TYPE]` | `TYPE_TYPE` (20) |
| 36 | `paren_expr` | `[inference: delegate to child]` | child type |
| 37 | `return_stmt` | → `resolveReturnStmt` | `TYPE_NORETURN` |
| 38 | `expr_stmt` | `[inference: delegate to child]` | child type |
| 39 | `import_expr` | `[inference: return TYPE_VOID]` | `TYPE_VOID` |
| 40 | `block` | `[inference: resolve children via stmt iter, return last child type]` | last child type / VOID |
| 41 | `add` / `sub` / `mul` / `div` / `mod_op` | → `semanticAnalyzerResolveArithmetic` | numeric/ptr type or VOID |
| 42 | `bit_and` / `bit_or` / `bit_xor` / `shl` / `shr` | → `semanticAnalyzerResolveBitwise` | integer type or VOID |
| 43 | `bool_and` / `bool_or` | → `semanticAnalyzerResolveLogical` | `TYPE_BOOL` or VOID |
| 44 | `cmp_eq` / `cmp_ne` / `cmp_lt` / `cmp_le` / `cmp_gt` / `cmp_ge` | → `semanticAnalyzerResolveComparison` | `TYPE_BOOL` or VOID |
| 45 | `plain_assign` / `add_assign` / ... / `xor_assign` | → `semanticAnalyzerResolveAssign` | lhs type or VOID |
| 46 | `range_exclusive` / `range_inclusive` | `[inference: return TYPE_U32]` | `TYPE_U32` |
| — | (any other AstKind) | `[inference: diag ERR_3020, return TYPE_VOID]` | `TYPE_VOID` |

After all arms: emit `STX:n<idx> STX:k<kind> STX:r<result> A4:N<idx> A4:K<kind> A4:R<result>`, `resolvedTypeTableSet(node_idx, result)`, `STB:N<idx> STB:R<result>`, return `result`.

### semanticAnalyzerResolveArithmetic (`sf/src/semantic_analyzer.zig:487-511`)

`[inference: ptr+int → ptr, ptr-ptr → isize, num+int_lit → num, else size-based winner]`

```
lhs = resolveExpr(child_0), rhs = resolveExpr(child_1)
if lhs==0 or rhs==0: return TYPE_VOID

if op is add/sub:
  if lhs is ptr/slice and rhs is unsigned → return lhs
  if add and lhs is unsigned and rhs is ptr → return rhs
  if sub and lhs is ptr and rhs is ptr → return isize

if lhs is int_lit and rhs is numeric → return rhs
if rhs is int_lit and lhs is numeric → return lhs

if not both numeric → return TYPE_VOID
if lhs == rhs → return lhs
return the one with larger size
```

### semanticAnalyzerResolveBitwise (`sf/src/semantic_analyzer.zig:513-522`)

`[inference: int_lit + integer → wider, both same integer type → that type]`

```
if lhs is int_lit and rhs is integer → return rhs
if rhs is int_lit and lhs is integer → return lhs
if lhs != rhs or lhs is not integer → return TYPE_VOID
return lhs
```

### semanticAnalyzerResolveComparison (`sf/src/semantic_analyzer.zig:524-567`)

`[inference: error/enum literal with expected type, then numeric/optional/pointer/error-set comparison, return TYPE_BOOL]`

Special expected-type push for error/enum literals when the other operand has a matching error_set/tagged_union type. Then:
- int_lit + numeric → `TYPE_BOOL`
- same numeric → `TYPE_BOOL`
- `==`/`!=`: optional+null, null+optional, error_set+error_set → `TYPE_BOOL`
- same bool → `TYPE_BOOL`
- same pointer → `TYPE_BOOL`

### semanticAnalyzerResolveFnCall (`sf/src/semantic_analyzer.zig:649-780`)

`[inference: direct callee → resolve return type → push/pop expected types for params → record coercions]`

**Phase 1 — direct call optimization (callee is ident_expr):**
- Symbol lookup. If `SymbolKind.function` with decl_node:
  - Look up return_type_node in resolved type table.
  - If not resolved, try name cache (module-0 + per-module) or `resolveTypeExprFull`.
  - If `direct_ret != 0`, iterate args against fn params: `call_param_map` or `xt_items[params_start+ai]` → `pushExpectedType` → resolve → `tryRecordCoercion`.

**Phase 2 — general callee:**
- Resolve callee expr. If ptr_type pointing to fn_type, dereference.
- If not fn_type: emit `FN3:N<T>T<K>` marker, return `TYPE_VOID`.
- Match arg count to param count. If mismatch, return `fnp.return_type` (lenient).
- Per-arg loop: `pushExpectedType(param_type)` → resolve → `popExpectedType` → `tryRecordCoercion`.

### semanticAnalyzerResolveSwitchExpr (`sf/src/semantic_analyzer.zig:1018-1129`)

`[inference: resolve condition → set current_switch_cond_tu → resolve prongs → unify types → return unified]`

1. Increment `switch_depth`. Marker `SE`.
2. Resolve condition. If tagged_union_type, set `current_switch_cond_tu`.
3. Iterate prongs. For each:
   - If else-prong with capture (flag 0x10) → error `ERR_3001`.
   - If `current_switch_cond_tu != 0` and prong has cases:
     - For each case: if enum_literal or undefined_literal → resolve via `semanticAnalyzerResolveEnumLiteral`.
     - If capture (flag 0x10): register local decl with field type from TU fields.
   - Resolve prong body expr.
   - **Type unification**: track `unified` type. Coercion-aware: if bt can coerce to unified, record coercion. If unified can coerce to bt, swap. If both numeric and one is int_lit → use concrete. Else → error `MIX:*` markers.
4. Return unified type. Marker `SWU:n<t>U:t<unified>`.

### semanticAnalyzerResolveEnumLiteral (`sf/src/semantic_analyzer.zig:838-901`)

`[inference: switch context → expected type stack → tagged union field scan → error or return type]`

1. If `current_switch_cond_tu != 0`: scan TU fields for matching name_id. Register `enum_value_table[node_idx]=fi`. Return `current_switch_cond_tu`.
2. If `expected_type_stack` top is tagged_union: scan fields. If field type is VOID → register enum value, return top type. If field type is non-VOID → error `ERR_3008` "enum literal member requires payload".
3. If field not found in expected TU → error `ERR_3009` "unknown enum literal member".
4. Fallback → return `TYPE_VOID` (unresolvable).

### semanticAnalyzerResolveStructInit (`sf/src/semantic_analyzer.zig:903-969`)

`[inference: explicit type → expected type → scan fields → push/pop expected types for each init]`

- If type is tagged_union: iterate field_inits, find matching field by name_id, push expected type, resolve init, record coercion.
- If type is struct: same process on struct fields.

### semanticAnalyzerResolveAssign (`sf/src/semantic_analyzer.zig:971-1016`)

`[inference: resolve lhs → push expected type for rhs → try coercion → error or return lhs type]`

Special case: if lhs is ident_expr with name `_`, resolve rhs but discard (explicit discard). Otherwise `pushExpectedType(lhs)` → resolve rhs → `tryRecordCoercion`. If not assignable, emit diagnostic with source/target type kinds.

### semanticAnalyzerResolveFnBody (`sf/src/semantic_analyzer.zig:1384-1425`)

`[inference: clear locals → register params → set current_fn_return → call stmt iter]`

1. Clear `local_decl_count`.
2. Resolve fn_decl node, get `FnProto`.
3. For each param: if `child_0 != 0` (has type annotation), look up resolved type from RTT or set `TYPE_UNDEFINED`. Register as local decl.
4. Set `current_fn_return` from `resolvedTypeTableGet(proto.return_type_node)`.
5. Resolve body via `semanticAnalyzerResolveStmt(body_node)`.

### semanticAnalyzerResolveStmtIter (`sf/src/semantic_analyzer.zig:1539-1723`)

`[inference: worklist-based iteration over statement tree]`

Worklist (stack-based) traversal. Pushes stmt children in reverse order for pre-order processing. Handles:
- `block` → push children in reverse (last first for correct order after pop).
- `var_decl` → resolve type annotation (ident_expr or type_resolver). Resolve init with push/pop expected type. Infer error/empty enum literal types by scanning registry. Record coercions. Register local decl + name cache. Diagnostics for mismatches.
- `if_stmt` → resolve header, push else then then (for correct worklist order).
- `while_stmt` → resolve header, push body.
- `for_stmt` → resolve header, push body.
- `return_stmt` → `resolveReturnStmt`.
- Assignments → `semanticAnalyzerResolveExpr`.
- `defer_stmt`/`errdefer_stmt` → push body.
- Other → `semanticAnalyzerResolveExpr`.

Skips `fn_decl` children (inner functions handled by outer phase).

### semanticAnalyzerResolveTryExpr (`sf/src/semantic_analyzer.zig:782-792`)

`[inference: resolve inner → error_union → payload type]`

If inner is error_union_type, return `eu.payload`. Else return `TYPE_VOID`.

### semanticAnalyzerResolveOrelseExpr (`sf/src/semantic_analyzer.zig:794-820`)

`[inference: null + expected optional → wrap_optional_null coercion → payload type; optional → unwrap_optional coercion → payload type]`

Two cases:
- Inner is `TYPE_NULL` and expected type is non-zero: if expected is optional, extract payload, add `wrap_optional_null` coercion, return payload.
- Inner is `optional_type`: extract payload, add `unwrap_optional` coercion, return payload.

### semanticAnalyzerResolveIfExpr (`sf/src/semantic_analyzer.zig:822-836`)

`[inference: resolve header → resolve then → resolve else → unify types]`

Type unification priority:
- No else → return then_type
- then == else → return either
- then is noreturn → return else
- else is noreturn → return then
- then is int_lit, else is numeric → coerce then, return else
- else is int_lit, then is numeric → coerce else, return then
- then is VOID → return else
- else is VOID → return then
- Otherwise → return TYPE_VOID (type mismatch)

### semanticAnalyzerResolveIfHeader / ForHeader / WhileHeader

`resolveIfHeader` (`sf/src/semantic_analyzer.zig:1470-1489`):
`[inference: resolve condition → if_capture → registerLocalDecl with captured type]`
Capture unwraps optional via `semanticAnalyzerCaptureType`.

`resolveForHeader` (`sf/src/semantic_analyzer.zig:1491-1521`):
`[inference: resolve iterable → slice/array/range → element type → register capture + index]`
If payload (capture name), register local decl with element type. If child_2 (index name), register with `TYPE_USIZE`.

`resolveWhileHeader` (`sf/src/semantic_analyzer.zig:1523-1537`):
`[inference: resolve condition → while_capture → registerLocalDecl]`
Same capture logic as if-header.

### semanticAnalyzerResolveIndexAccess (`sf/src/semantic_analyzer.zig:1745-1780`)

`[inference: resolve index → resolve base → trace source → indexed elem type]`

Resolve child_1 (index), then child_0 (base). If base is `ident_expr`, trace back up to 3 steps through var_decl → slice_expr → ident_expr chain to find source name (for error messages). Records source name via `resolvedSourceTableSet`. Returns `typeRegistryIndexedElemType` or tuple first element or base type.

### semanticAnalyzerResolveSliceExpr (`sf/src/semantic_analyzer.zig:1782-1802`)

`[inference: resolve base → resolve bounds → create slice type from elem]`

Resolves child_0 (base/elem), child_1 (start), child_2 (end). Determines element type via `typeRegistryIndexedElemType`. Creates slice type with const flag from base type's flags.

### semanticAnalyzerResolveTupleLiteral (`sf/src/semantic_analyzer.zig:1804-1816`)

`[inference: resolve each element → append to xt → create tuple type]`

Each element resolved. If element resolves to VOID, substitutes TYPE_I32. Appends types to `registry.xt_items`. Returns `typeRegistryGetOrCreateTuple(start, count)`.

### semanticAnalyzerResolveArrayInit (`sf/src/semantic_analyzer.zig:1818-1837`)

`[inference: check child_0 for explicit array type → else resolve first element → create array type]`

If `child_0` has a resolved array type, return it directly. Otherwise determine element type from first element (special case: char_literal → u8, int_literal → u32, else resolve). Create array type with element count.

### resolveReturnStmt (`sf/src/semantic_analyzer.zig:633-647`)

`[inference: push expected fn return → resolve expr → record coercion]`

If child exists: `pushExpectedType(current_fn_return)` → resolve → `popExpectedType`. If `current_fn_return` is non-zero non-void: `tryRecordCoercion` with `errLitSrcType`.

### tryRecordCoercion (`sf/src/semantic_analyzer.zig:597-620`)

`[inference: classifyCoercion → if non-none or null→ptr, add to coercion table]`

Checks: if src == dst or src is UNDEFINED → skip. If not assignable → skip. Calls `classifyCoercion(registry, src, dst)`. If coercion kind is not `none`, or src is null and dst is pointer → `coercionTableAdd(node, ck, dst_type)`.

### Marker Reference

| Marker | File | Line | Meaning |
|--------|------|------|---------|
| `IDE\n` | sema | 175 | Resolve ident entry |
| `SEM:vi` | sema | 176 | Name is underscore (void ident) |
| `D7:Yn D7:n D7:t D7:t` | sema | 182-185 | Local decl found |
| `L\n L:t` | sema | 186-187 | Local resolved |
| `S\n` | sema | 195 | Symbol lookup |
| `TAL\n` | sema | 196 | Type alias resolved |
| `STY:N STY:T` | sema | 197 | Symbol type found |
| `SVO\n` | sema | 198 | Symbol is void |
| `C2:T` | sema | 200 | Name cache hit |
| `D8:*` | sema | 201-219 | Debug dump for node [450,660] |
| `IDT:<n>:VOID\n` | sema | 225-227 | Ident is void (unresolved) |
| `FAE\n` | sema | 231 | Field access entry |
| `PFA:BK PFA:FN` | sema | 235-236 | Base kind + field name |
| `Q1:FL Q1:KL Q1:TL Q1:FN` | sema | 283-286 | Module-qualified lookup |
| `Q1FX\n` | sema | 298 | Cross-module fn decl |
| `BR:x BR:rt BR:fnr` | sema | 302-315 | Bridge fn return resolution |
| `FAPR:OK FAPR:DK` | sema | 352-354 | Ptr deref in field access |
| `MFA\n` | sema | 385 | Module field access |
| `MF1\n` | sema | 390 | Module field simple type |
| `MFF\n` | sema | 400 | Module field function |
| `FSL:USIZE\n` | sema | 437 | Slice .len → usize |
| `FSP:PTR\n` | sema | 445 | Slice .ptr → [*]T |
| `FF\n` | sema | 458 | Unknown base type |
| `FF:R` | sema | 474 | Field found result |
| `NF\n FF2:N FF2:F FF2:B` | sema | 481-482 | Field not found |
| `COE:N COE:S COE:D` | sema | 598-600 | Coercion attempt |
| `COE:SK COE:DK` | sema | 604-605 | Src/dst TypeKind |
| `CCK:ca` | sema | 615 | classifyCoercion result |
| `COR:N COR:K` | sema | 618 | Coercion recorded |
| `FNE\n` | sema | 650 | Fn call entry |
| `FN1\n FN1:R` | sema | 700-701 | Direct call resolved |
| `FN2\n` | sema | 733 | Callee void |
| `FN3:N FN3:T FN3:K` | sema | 744-746 | Not a fn type |
| `FN4a-FN4g` | sema | 749-770 | Fn call param resolution |
| `PTM:A PTM:T PTM:N` | sema | 767-769 | Param type marker |
| `LOE` | sema | 570 | Logical op entry |
| `LOB LOV` | sema | 574-576 | Logical bool or void |
| `CPE` | sema | 525 | Comparison entry |
| `CP0 CPB CPV` | sema | 551-565 | Comparison outcomes |
| `SIF:0N-7N` | sema | 826-835 | If-expr type unification |
| `SE` | sema | 1020 | Switch expr entry |
| `SWI:n SWI:p SWI:d` | sema | 1022-1023 | Switch info |
| `PCT:C PCT:P` | sema | 1050-1051 | Prong context |
| `CC:K` | sema | 1058 | Case kind |
| `SCE:p SCE:l` | sema | 1067-1068 | Switch capture entry |
| `SCFE:n SCFE:t` | sema | 1075-1076 | Switch capture field |
| `PBD:N PBD:K` | sema | 1094-1095 | Prong body details |
| `SWPB:i SWPB:t` | sema | 1100 | Sw prong body type |
| `MIX:*` | sema | 1117 | Mixed prong types |
| `SWU:n SWU:t` | sema | 1126 | Switch unified type |
| `eL\n EL:N EL:F` | sema | 839-851 | Enum literal entry |
| `ELV:N` | sema | 898 | Enum literal void |
| `ASE` | sema | 972 | Assign entry |
| `AS0 AS1 AS2` | sema | 988-995 | Assign outcomes |
| `RXS RXS:n` | sema | 1138-1139 | Switch in expr dispatch |
| `FAD:R` | sema | 1189 | Field access result |
| `STX:n STX:k STX:r` | sema | 1372-1374 | Expression result |
| `A4:N A4:K A4:R` | sema | 1375-1377 | After-expr markers |
| `STB:N STB:R` | sema | 1379-1380 | Type table set |
| `FB` | sema | 1385 | Fn body entry |
| `SP:n SP:K` | sema | 1547-1548 | Stmt worklist pop |
| `BLK:N BLK:C` | sema | 1551-1552 | Block iteration |
| `BCK:B BCK:I BCK:N BCK:K` | sema | 1556-1560 | Block child push |
| `VD:N VD:C` | sema | 1573-1574 | Var decl |
| `IK:K` | sema | 1600 | Init node kind |
| `CCK:vr` | sema | 1630 | Coercion check var decl |
| `VRT:<n>:<t>` | sema | 1592-1596 | Var resolved type |
| `REG:cp REG:ct` | sema | 1672-1673 | Name cache register |
| `ELS:n ELS:k ELS:c` | sema | 1709-1711 | Fallback stmt kind |
| `IXA:N` | sema | 1746 | Index access entry |
| `C0K:K` | sema | 1751 | Index base node kind |
| `STE:N` | sema | 1754 | Source trace entry |
| `SRC:N SRC:S` | sema | 1761-1762 | Source name trace |
| `IX:T IX:R` | sema | 1766-1772 | Index type result |
| `CC:nul` | coercion | 98 | classifyCoercion: null target |
| `CLS:p*` | coercion | 164 | classifyCoercion: ptr-to-slice |

---

## coercion.zig (`sf/src/coercion.zig`, 176 lines)

### CoercionKind enum (`sf/src/coercion.zig:1-19`)

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

### classifyCoercion (`sf/src/coercion.zig:85-176`)

`[inference: type-kind dispatch on source/target for 18+ checks, return CoercionKind]`

Deterministic check order:

1. `source == target` → `none`
2. `integer_literal_type` + `isNumeric(target)` → `int_literal_coerce`
3. Both integer, same signedness, src.size < tgt.size → `int_widen`
4. `TYPE_F32` → `TYPE_F64` → `float_widen`
5. `null_type` → `isPointer(target)`: `none`. → `optional_type`: `wrap_optional_null`. → `fn_type`: `none`.
6. Target is `optional_type`: if source assignable to payload → `wrap_optional`. If null → `none`.
7. Target is `error_union_type`: if source assignable to payload → `wrap_error_success`.
8. Source is `error_set_type` and target is `error_union_type`: → `wrap_error_err`.
9. ptr→ptr: if base is VOID → `none`. If target is const and source is not, same base → `const_qualify`.
10. slice→slice: if target is const and source is not, same elem → `const_qualify`.
11. many_ptr→many_ptr: if target is const and source is not, same base → `const_qualify`.
12. array→slice: same elem → `array_to_slice`.
13. array→many_ptr: same elem → `array_to_many_ptr`.
14. slice→many_ptr: same elem → `slice_to_many_ptr`.
15. ptr→optional: if optional payload is ptr and assignable → `ptr_to_optional_ptr`.
16. u8↔c_char: `none` (identity).
17. ptr→slice: if base matches elem → `string_to_slice`. If src pointee is array and elem matches → `array_to_slice`.
18. Fallback → `none`.

### CoercionTable (`sf/src/coercion.zig:35-41`)

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

#### coercionTableAdd (`sf/src/coercion.zig:65-77`)

`[inference: upsert pattern — get-or-insert in index, update existing or append new entry]`

If node_idx already in index, update entry in-place. Otherwise ensure capacity, append, add to index.

#### coercionTableGet (`sf/src/coercion.zig:79-83`)

`[inference: index lookup → entry or null]`

Simple hash lookup. Returns `?CoercionEntry`.

---

## resolved_type_table.zig (`sf/src/resolved_type_table.zig`, 105 lines)

Maps AST nodes to their resolved types and source names. Used by semantic analysis and lowering.

### ResolvedTypeTable (`sf/src/resolved_type_table.zig:11-21`)

```zig
pub const ResolvedTypeTable = struct {
    entries_items: [*]TypeTableEntry,
    entries_len/cap/alloc: ...,
    index: U32ToU32Map,        // node_idx → entry_idx
    source_index: U32ToU32Map, // node_idx → source_entry_idx
    source_items: [*]u32,      // source_name_id per source entry
    source_len/cap: ...,
};
```

Two separate arrays with independent hash indices:
- `entries`+`index`: `node_idx → TypeId`
- `source_items`+`source_index`: `node_idx → source_name_id` (for index-access source tracing)

#### resolvedTypeTableSet (`sf/src/resolved_type_table.zig:51-63`)

`[inference: upsert — if node exists, update; else ensure capacity, append, add to index]`

#### resolvedTypeTableGet (`sf/src/resolved_type_table.zig:65-71`)

`[inference: hash lookup → ?TypeId]`

#### resolvedSourceTableSet / Get (`sf/src/resolved_type_table.zig:86-105`)

Same pattern but for `node_idx → source_name_id`. Used by `semanticAnalyzerResolveIndexAccess` to trace variable sources through var_decl → slice_expr chains.

---

## constraint_checker.zig (`sf/src/constraint_checker.zig`, 110 lines)

Three independent validation passes run after semantic analysis.

### checkReturnType (`sf/src/constraint_checker.zig:11-28`)

`[inference: if return_stmt with no child and fn returns non-void/noreturn → error; if return expr not assignable → error]`

Two checks:
- `child_0 == 0` (bare return): if `current_fn_return` is non-void and non-noreturn → error "return with no value".
- `child_0 != 0`: if `return_expr_type != 0` and not assignable to `current_fn_return` → error "return type mismatch".

### checkSwitchExhaust (`sf/src/constraint_checker.zig:30-68`)

`[inference: resolve cond type → if enum/tagged_union → count prong items → if covered < total and no else → error]`

- Only checks enum_type and tagged_union_type conditions.
- Counts total members from `en_items` or `tu_items`.
- Iterates prongs, summing case item counts (flag bit 0 = else).
- If `has_else == 0` and `covered_count < member_count` → error `ERR_3004` "switch not exhaustive".

### constraintCheckerCheckBreakContinue (`sf/src/constraint_checker.zig:70-109`)

`[inference: DFS stack with depth tracking — break/continue at depth 0 → error]`

Explicit-stack iterative traversal (avoiding recursion depth limits). Each stack entry pairs `(node_idx, depth)`. Deeper `while_stmt`/`for_stmt` increments depth. If `break_stmt`/`continue_stmt` at depth == 0 → error "break/continue outside loop". Pushes children (child_0-2 + extra) with current depth.

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
- `pushExpectedType` (line 1443) — watch `ty` parameter
- `popExpectedType` (line 1459) — watch `self.expected_type_stack_len` decrement

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
