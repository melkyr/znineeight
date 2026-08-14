# 05 — Semantic Analysis [updated: 2026-08-13 — 11 socket builtins (@socketCreate/BindListen/Accept/Connect/Send/Recv/Select/FdZero/FdSet/FdIsset/Close) added to the builtin_call resolver (semantic_analyzer.zig:1441-1489); prior 2026-08-08 — console builtins (@isWindows/@consoleClear/@consoleGotoxy/@consoleSetColor) added to the builtin_call resolver; prior 2026-08-08 — 6 core I/O builtins (@putChar/@stdoutWrite/@stderrWrite/@getChar/@exit/@sleepMs); prior 2026-08-07 — labeled_stmt transparent unwrap in stmt dispatcher + expr redirect; prior variadic fn-call typing via `FnPayload.flags_packed`]

## Summary Table

| Artifact | Count | Notes |
|----------|-------|-------|
| `SemanticAnalyzer` fields | 60 | 30 non-builtin + 30 builtin name IDs |
| Expression kind dispatch arms | 46+ | Every `AstKind` handled in `semanticAnalyzerResolveExpr` |
| `CoercionKind` variants | 17 | `none` through `wrap_optional_null` (coercion.zig:1-19) |
| Coercion checks in `classifyCoercion` | ~18 | Null, optional, error union, ptr, slice, array, widening |
| Marker codes | 80+ | `IDE`, `D7`, `L`, `S`, `STY`, `FAE`, `PFA`, `FAPR`, `COE`, `CCK`, `COR`, `SIF`, etc. |
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
    // 30 builtin name IDs (19 incl. F1/F2 + 11 socket):
    ptrcast_name_id, ptrtoint_name_id, inttoptr_name_id,
    intcast_name_id, floatcast_name_id, inttofloat_name_id,
    inttoenum_name_id, size_of_name_id, align_of_name_id,
    putchar_name_id, stdout_write_name_id, stderr_write_name_id,
    getchar_name_id, exit_name_id, sleep_ms_name_id,
    is_windows_name_id, console_clear_name_id, console_gotoxy_name_id,
    console_set_color_name_id,
    socket_create_name_id, socket_bind_listen_name_id, socket_accept_name_id,
    socket_connect_name_id, socket_send_name_id, socket_recv_name_id,
    socket_select_name_id, socket_fd_zero_name_id, socket_fd_set_name_id,
    socket_fd_isset_name_id, socket_close_name_id,
};
```

Key state: expected-type stack for contextual type inference (enum literals, error literals, null), statement worklist for iterative traversal, switch context for enum literal resolution, and local declaration shadow stack.

### semanticAnalyzerInit (`sf/src/semantic_analyzer.zig:74-153`)

`[inference: sandAlloc-builtin name interning, zero-init stacks/lists, return SemanticAnalyzer]`

Allocates no heap memory in the struct itself. Interns 30 builtin names (`@ptrCast`, `@ptrToInt`, `@intToPtr`, `@intCast`, `@floatCast`, `@intToFloat`, `@intToEnum`, `@sizeOf`, `@alignOf`, `@putChar`, `@stdoutWrite`, `@stderrWrite`, `@getChar`, `@exit`, `@sleepMs`, `@isWindows`, `@consoleClear`, `@consoleGotoxy`, `@consoleSetColor`, `@socketCreate`, `@socketBindListen`, `@socketAccept`, `@socketConnect`, `@socketSend`, `@socketRecv`, `@socketSelect`, `@socketFdZero`, `@socketFdSet`, `@socketFdIsset`, `@socketClose`) plus the discard identifier `_`. Stacks and work arrays are zero-capacity — grown on first use.

### semanticAnalyzerIsTypeValueCast (`sf/src/semantic_analyzer.zig:152-160`)

`[inference: match name_id vs 6 cast builtins → return bool]`

Checks if name_id matches @ptrCast, @intToPtr, @intCast, @floatCast, @intToFloat, or @intToEnum. Used by builtin_call dispatch in ResolveExpr to short-circuit as type-value cast.

### semanticAnalyzerGrowLocalDecls (`sf/src/semantic_analyzer.zig:136-152`)

`[inference: grow-by-doubling from min 8, memcpy name+type arrays]`

Grows the parallel name/type local-decl arrays. Called by registerLocalDecl on overflow.

### registerLocalDecl (`sf/src/semantic_analyzer.zig:154-163`)

`[inference: grow if full → write name_id/type_id → inc count]`

Core local declaration registration. Called by resolveIdent local lookup, resolveFnBody param registration, and if/while/for header captures.

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

#### Measured push/pop behavior (`[fprintf]` on pushExpectedType/popExpectedType + call sites)

Max stack depth per example: mud 2, gol 2, lisp 3, json 3. Push/pop counts are always balanced
(mud 191/191, gol 193/193, lisp 852/852, json 408/408) — every `pushExpectedType` is matched by a
`popExpectedType`.

**Return statement + tagged-union struct literal (mud parseCommand, main.zig:88
`return .{ .Go = @intCast(u8, 0) };`):**
```
[P5R] ret node=219 fn_ret=26 top=0        <- return_stmt; fn returns Command TU (type 26)
[P5E] PUSH ty=26 depth=1                  <- push current_fn_return
[P5SI] struct_init node=218 target=26     <- return expr: tagged-union struct_init
[P5SI] field push fi=1 field_ty=8         <- field Go: u8
[P5E] PUSH ty=8 depth=2                   <- nested field-type push (max 2 for mud)
[P5E] POP depth=1
[P5E] POP depth=0
```

**Struct-literal field chain (lisp value.zig:20
`v.* = Value{ .Cons = .{ .car = car, .cdr = cdr } };`):**
```
[P5E] PUSH ty=31 depth=1                  <- assign pushes lhs (Value TU, type 31)
[P5SI] struct_init node=3608 target=31    <- Value{...}
[P5SI] field push fi=4 field_ty=38        <- Cons: anonymous struct
[P5E] PUSH ty=38 depth=2
[P5SI] struct_init node=3606 target=38    <- .{...} target comes from topExpectedType
[P5SI] field push fi=0 field_ty=39        <- car: *Value
[P5E] PUSH ty=39 depth=3                  <- deepest (max 3 for lisp)
```

**If/else branches (json parserPeek, json.zig:32
`return if (self.pos < self.input.len) self.input[self.pos] else zero;`):**
```
[P5R] ret node=352 fn_ret=8 top=0         <- return_stmt; fn returns u8 (8)
[P5E] PUSH ty=8 depth=1                   <- push fn return type
[P5I] if_expr node=351 top=8              <- BOTH branches see u8 on the stack
[P5ID] LOCAL hit 'self' ...               <- then-branch resolves (index_access)
SIF:1N351 T8                              <- then==else -> unified u8
[P5E] POP depth=0
```

`if_expr` itself never pushes (no push in `semanticAnalyzerResolveIfExpr`,
semantic_analyzer.zig:822-836); its then/else branches inherit the expected type pushed by the
enclosing return-statement or var-decl.

### semanticAnalyzerStmtWorkPush (`sf/src/semantic_analyzer.zig:1427-1441`)

`[inference: grow-by-doubling from 64, write/inc work pointer]`

Worklist growth and push. Grows the statement work array (min 64, doubling). Pushes stmt node index onto the worklist.

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

#### Measured lookup priority (`[fprintf]` on `semanticAnalyzerResolveIdent` in the generated C89)

Five stages, first hit wins. Stage-2 symbol lookup is *checked first* even though
`nameCacheGet` is computed earlier (semantic_analyzer.zig:191-194); the name-cache key is
`(u64)name_id` (module 0), so stage 3 only sees bare-name entries.

| # | Stage | Code | Marker | lisp trace evidence |
|---|-------|------|--------|---------------------|
| 1 | local shadow (reverse scan) | semantic_analyzer.zig:177-190 | `D7:*` / `L\n` | `f_ptr` param: `[P5ID] LOCAL hit name=264 'f_ptr' type=40` |
| 2 | symbol registry (own module) | semantic_analyzer.zig:193-199 | `S\n` / `STY:*` / `TAL` / `SVO` | `sand_mod` module sym: `[P5ID] SYM hit name=20 'sand_mod' type=21 kind=5`; `Value` alias: `[P5ID] SYM type_alias name=55 'Value' type=31` |
| 3 | name cache (module-0 key) | semantic_analyzer.zig:191-192,200 | `C2:T` | `usize`: `[P5ID] CACHE hit name=12 'usize' type=13`; `i32`→6, `i64`→7 |
| 4 | discard sentinel `_` | semantic_analyzer.zig:221-223 | — | `[P5ID] DISCARD name=70` → TYPE_UNDEFINED |
| 5 | fallback VOID | semantic_analyzer.zig:224-227 | `IDT:<name>:VOID` | `[P5ID] VOID name=70` → TYPE_VOID |

Stage-3 entries come from `typeRegistryRegisterPrimitives` → `registerPrimitiveName`, which caches
`usize`/`i32`/`i64`/... under their bare name_id (type_registry.zig:621-627), plus module-0 types
cached by `resolveNamedTypeExpressions` (type_resolver.zig:949-971). Stage counts per example:
mud 235 LOCAL / 29 SYM / 4 TAL / 5 CACHE / 3 VOID; gol 137/15/18/9/1; lisp 909/113/12/19/1;
json 441/8/8/9/1 + 1 DISCARD.

Cross-module references resolve in two hops. The base `mod` goes through stage 2 (module symbol,
`kind=5`); the field name is then looked up in the *target* module's table by
`resolveFieldAccess` (`symbolRegistryQualifiedLookup(symbols, target_mod, field_name)`,
semantic_analyzer.zig:279-281, `Q1:FL/KL/TL/FN`). lisp `sand_mod.sand_init` from main.zig:110:
```
FAE PFA:BK24 PFA:FN88
[P5ID] SYM hit name=20 'sand_mod' type=21 kind=5    <- stage 2 on base ident
Q1:FL2 Q1:KL3 Q1:TL54 Q1:FN88                       <- cross-module field (function, fn type 54)
```
`[fprintf]` + `[markers]`.

**Known quirk (sentinel) — [FIXED F6]:** `_stub_0` was both the discard sentinel (semantic_analyzer.zig:49,109)
and a scratch register reused by `semanticAnalyzerResolveIndexAccess` / `ResolveSliceExpr` /
`ResolveTupleLiteral` / `ResolveArrayInit` (semantic_analyzer.zig:1749, 1784, 1811, 1830). After
any of those resolve, `_stub_0` held a TypeId, so a later `_` ident missed stage 4 and returned
TYPE_VOID instead of TYPE_UNDEFINED. Observed pre-F6: mud 3× `_`→VOID (main.zig:164/173/202), gol 1×,
lisp 1× (parser.zig:30), json 1× `_`→VOID + 1× `_`→DISCARD (main.zig:88, resolved before any
index_access clobber).

**Fix (F6, 2026-07-31):** Each clobber function now saves `_stub_0` at entry and restores it
at all exit points (via `saved` local + restore before each `return`). The `resolveAssign`
shield (semantic_analyzer.zig:977-982, comparing lhs name against a fresh interner lookup)
remains as belt-and-suspenders for `_ = expr`. See F6-report for gate results.

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

`sf/src/semantic_analyzer.zig:1131-1396` — master `switch` on `node.kind`:

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
| 18 | `builtin_call` | → dispatch by child_0 | TYPE_INT_LIT / resolved type / arg type / TYPE_VOID / TYPE_U8 / TYPE_NORETURN |
| 19 | `bool_not` | `[inference: resolve child, return TYPE_BOOL]` | `TYPE_BOOL` |
| 20 | `negate` | → `semanticAnalyzerResolveNegate` | numeric type or VOID |
| 21 | `bit_not` | → `semanticAnalyzerResolveBitNot` | integer type or VOID |
| 22 | `try_expr` | → `semanticAnalyzerResolveTryExpr` | error union payload |
| 23 | `catch_expr` | `[inference: unwrap error union + capture]` | payload type |
| 24 | `orelse_expr` | → `semanticAnalyzerResolveOrelseExpr` | optional payload |
| 25 | `break_stmt` / `continue_stmt` | `[inference: return TYPE_VOID]` | `TYPE_VOID` |
| 26 | `var_decl` / `defer_stmt` / `errdefer_stmt` / `labeled_stmt` | → `semanticAnalyzerResolveStmtIter` | `TYPE_VOID` |
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

#### Measured arm-hit table (4 examples, `[markers]` A4:K / STX:k)

Counts below are resolveExpr resolutions that reach the tail (`A4:K`). `RXS` is the swt_ex entry count
(semantic_analyzer.zig:1137); every swt_ex entry resolves, so RXS == A4:K56 (lisp 56 == 56). Note the
raw `RXS` grep count of 112 is a double-count: `semanticAnalyzerResolveExpr` emits `RXS` with no
trailing newline followed by `RXS:n<idx>` (semantic_analyzer.zig:1138-1139), so the concatenated
`RXSRXS:n<idx>` matches the `RXS` pattern twice. `P0: n` (semantic_analyzer.zig:1024) is a marker in
`semanticAnalyzerResolveSwitchExpr`, not in the swt_ex dispatch arm. TypeId results (`STX:r`) are
omitted; the table is hit-frequency only.

| Arm | Kinds hit (of 4 examples) | mud | gol | lisp | json |
|-----|---------------------------|-----|-----|------|------|
| 1 int_literal | all | 61 | 82 | 113 | 67 |
| 2 float_literal | — | 0 | 0 | 0 | 0 |
| 3 char_literal | mud,gol,lisp,json | 2 | 2 | 18 | 62 |
| 4 bool_literal | mud,lisp,json | 9 | 0 | 25 | 4 |
| 5 null_literal | mud,lisp,json | 4 | 0 | 5 | 1 |
| 6 undefined_literal | all | 4 | 2 | 8 | 3 |
| 7 unreachable_expr | gol,lisp,json | 0 | 2 | 23 | 1 |
| 8 string_literal | all | 21 | 5 | 75 | 58 |
| 9 enum_literal | mud only | 3 | 0 | 0 | 0 |
| 10 error_literal | lisp,json | 0 | 0 | 61 | 14 |
| 11 ident_expr | all | 276 | 180 | 1054 | 471 |
| 12 field_access | all | 88 | 9 | 268 | 99 |
| 13 index_access | all | 30 | 6 | 49 | 24 |
| 14 slice_expr | all | 1 | 10 | 13 | 6 |
| 15 deref | lisp,json | 0 | 0 | 70 | 6 |
| 16 address_of | mud,lisp,json | 15 | 0 | 38 | 6 |
| 17 fn_call | all | 35 | 22 | 167 | 130 |
| 18 builtin_call | all | 39 | 8 | 41 | 22 |
| 19 bool_not | mud,lisp | 2 | 0 | 3 | 0 |
| 20 negate | gol,lisp | 0 | 2 | 5 | 0 |
| 21 bit_not | lisp only | 0 | 0 | 1 | 0 |
| 22 try_expr | lisp,json | 0 | 0 | 74 | 21 |
| 23 catch_expr | lisp,json | 0 | 0 | 24 | 2 |
| 24 orelse_expr | json only | 0 | 0 | 0 | 1 |
| 25 break_stmt/continue_stmt | lisp only | 0/0 | 0/0 | 1/2 | 0/0 |
| 26 var_decl/defer/errdefer | — | 0 | 0 | 0 | 0 |
| 27 if_expr | all | 1 | 2 | 3 | 1 |
| 28 if_stmt | lisp,json | 0 | 0 | 9 | 1 |
| 29 for_stmt | — | 0 | 0 | 0 | 0 |
| 30 while_stmt | — | 0 | 0 | 0 | 0 |
| 31 swt_ex (kind 56) | all | 1 | 3 | 56 | 2 |
| 32 tuple_literal | gol only | 0 | 2 | 0 | 0 |
| 33 struct_init | all | 14 | 19 | 11 | 8 |
| 34 array_init | gol only | 0 | 4 | 0 | 0 |
| 35 type/decl nodes (84-90,3-5,9) | error_set_decl(9) only | 0 | 0 | 1 | 2 |
| 36 paren_expr | mud,lisp,json | 2 | 0 | 24 | 1 |
| 37 return_stmt | mud,lisp | 2 | 0 | 58 | 0 |
| 38 expr_stmt | gol,lisp,json | 0 | 1 | 56 | 2 |
| 39 import_expr | all | 3 | 2 | 31 | 3 |
| 40 block | all | 2 | 19 | 72 | 9 |
| 41 add/sub/mul/div/mod | div+mod never | 7/4/0/0/0 | 6/0/2/0/0 | 10/3/3/0/0 | 18/6/4/0/0 |
| 42 bit_and/or/xor/shl/shr | bit_and only (lisp 1) | 0 | 0 | 1 | 0 |
| 43 bool_and/bool_or | all | 2/0 | 4/3 | 11/5 | 13/7 |
| 44 cmp_eq/ne/lt/le/gt/ge | all six hit | 8/3/13/1/2/1 | 3/0/11/2/1/6 | 29/11/20/1/5/3 | 36/11/14/2/2/5 |
| 45 plain/add/sub/mul/div assigns | 51-53; 54,55 lisp only | 21/9/2/0/0 | 6/8/0/0/0 | 73/19/1/1/1 | 15/12/0/0/0 |
| 46 range_exclusive/inclusive | — | 0 | 0 | 0 | 0 |

**Never-hit arms** across all 4 examples:
- Arm 2 `float_literal` — no float literals in any example.
- Arm 26 `var_decl`/`defer_stmt`/`errdefer_stmt`/`labeled_stmt` — statement kinds are handled directly in
  `semanticAnalyzerResolveStmtIter` (semantic_analyzer.zig:1564/1702; labeled_stmt unwrap at
  semantic_analyzer.zig:1767-1770); the resolveExpr fallback arm (semantic_analyzer.zig:1341-1343,
  incl. `labeled_stmt`) is never exercised.
- Arm 29 `for_stmt` and arm 30 `while_stmt` — resolved only via `ResolveFor/WhileHeader` in
  StmtIter (semantic_analyzer.zig:1683-1692). lisp/json DO contain `for` loops
  (builtins.zig:28/61, json main.zig:49/63) but those nodes go through StmtIter (`SP:K73`),
  never through resolveExpr.
- Arm 41 `div`, `mod_op`; arm 42 `bit_or`/`bit_xor`/`shl`/`shr` (only `bit_and` hit, lisp 1×);
  arm 45 `shl_assign`(57)/`shr_assign`(58)/`and_assign`(59)/`xor_assign`(60)/`or_assign`(61).
- Arm 46 `range_exclusive`/`range_inclusive` — no `for` range headers; also excluded from A4:K
  by its early return (semantic_analyzer.zig:1361-1363).
- Arm 35: only `error_set_decl` (9) reaches resolveExpr — as the init of a top-level
  `pub const X = error{...}` resolved by the phase-level init path (main.zig:375-385;
  lisp util.zig:1, json file.zig:18 / json.zig:14). `ptr_type`/`slice_type`/`fn_type`/etc. type
  nodes are resolved by the type resolver (type_resolver.zig), not by resolveExpr.

**Caveats:**
- Arms 28/37 (`if_stmt`, `return_stmt`) are usually processed in StmtIter; the A4:K hits come
  from statement nodes appearing in expression position (e.g. a block's last child resolved by
  `semanticAnalyzerResolveExpr`, semantic_analyzer.zig:1335-1336).
- Arm 31's kind value (swt_ex) now resolves correctly independently — `mod_assign=74` (was 56, F5 fix).
  Previously `swt_ex = 56` collided with `mod_assign = 56` (ast.zig:58/76).
  ResolveExpr checked `swt_ex` first (semantic_analyzer.zig:1137, 1299), so all
  kind-56 resolutions were switches. No example contained a genuine `%=`; if one did, it
  would have been mis-routed to the swt_ex arm (latent collision, fixed by F5).

#### Measured: `@ptrCast(fn(...) T, p)` target type (`[gdb]`)

lisp eval.zig:264 `const f = @ptrCast(fn ([]*value_mod.Value, *sand_mod.Sand) util.LispError!*value_mod.Value, f_ptr);`
(builtin_call node 2588). The builtin_call arm (semantic_analyzer.zig:1216-1240) treats it as a
type-value cast: it resolves the value arg first (`f_ptr` — a LOCAL shadow of the
`.Builtin => |f_ptr|` switch capture, type 40 = `*void`), then passes the fn-type AST node to
`resolveTypeExprFull`.

GDB at the type-value-cast arm (generated C, `node_idx == 2588`):
```
ec[0]=2586 (AST kind 90 = fn_type)  ec[1]=2587 (f_ptr)
resolveTypeExprFull(2586) -> result = 115
type[115]: kind=17 (ptr_type) payload_idx=15 size=4     <- ptr-to-fn, NOT the fn type itself
ptr base = 114
type[114]: kind=24 (fn_type) payload_idx=48
FnPayload@48: params_start=88 params_count=2 return_type=59 is_extern=0
param0=85 ([]*Value)  param1=56 (*Sand)
return_type 59: kind=22 (error_union_type) error_set=35 (LispError) payload=39 (*Value)
```

The `@ptrCast(fn(...), p)` **target type is a pointer to the fn type**. The `fn_type` arm of the
type resolver (type_resolver.zig:729-788) synthesizes a `fn_type` registry entry with a generated
name `fnt_<ret>_<p1>_...` (type_resolver.zig:749-778), marks it fn-ptr-used
(`typeRegistryMarkFnPtrUsed`, type_resolver.zig:786), and returns
`typeRegistryGetOrCreatePtr(fn_type, false)` — a pointer to it (type_resolver.zig:787). The local
`f` gets this ptr-to-fn type, and `f(args, temp_sand)` works because `semanticAnalyzerResolveFnCall`
dereferences a ptr callee to its fn type (semantic_analyzer.zig:735-742).

#### Builtin I/O dispatch (F1, 2026-08-08) — `[updated: 2026-08-13]`

The `builtin_call` resolver (semantic_analyzer.zig:1402-1495) dispatches 6 core I/O
builtins by `child_0` name ID (fields `putchar_name_id` … `sleep_ms_name_id`, interned in
`semanticAnalyzerInit`; core I/O arms at semantic_analyzer.zig:1413-1428). Each resolves its
value args via `semanticAnalyzerResolveExpr` and returns the signature type:

| Builtin | Args resolved | Returns |
|---------|---------------|---------|
| `@putChar(c: u8)` | `ec[0]` | `TYPE_VOID` |
| `@stdoutWrite(buf: [*]const u8, len: usize)` | `ec[0]`, `ec[1]` | `TYPE_VOID` |
| `@stderrWrite(buf: [*]const u8, len: usize)` | `ec[0]`, `ec[1]` | `TYPE_VOID` |
| `@getChar()` | none | `TYPE_U8` |
| `@exit(code: u8)` | `ec[0]` | `TYPE_NORETURN` |
| `@sleepMs(ms: u32)` | `ec[0]` | `TYPE_VOID` |

The `@getChar` zero-arg form depends on the parser zero-arg builtin fix (parser.zig:581).

#### Console builtin dispatch (F2, 2026-08-08) — `[updated: 2026-08-13]`

The same resolver (semantic_analyzer.zig:1429-1440) adds the 4 console builtins by `child_0`
name ID (fields `is_windows_name_id`, `console_clear_name_id`, `console_gotoxy_name_id`,
`console_set_color_name_id`):

| Builtin | Args resolved | Returns |
|---------|---------------|---------|
| `@isWindows()` | none | `TYPE_BOOL` (comptime-folded — never reaches runtime) |
| `@consoleClear()` | none | `TYPE_VOID` |
| `@consoleGotoxy(x: i32, y: i32)` | `ec[0]`, `ec[1]` | `TYPE_VOID` |
| `@consoleSetColor(fg: i32, bg: i32)` | `ec[0]`, `ec[1]` | `TYPE_VOID` |

`@isWindows()` is the sema-half of a comptime intrinsic: `comptime_eval.zig` folds it to a
`ComptimeVal` 0/1 (module const `host_is_windows`, currently `false`), so `phase_ComptimeEvaluation`
populates `comptime_values[node]` and the lowerer emits an `int_const` (`TYPE_BOOL` — set in the
comptime-fold path, lower.zig:2721-2724). `if (@isWindows())` then folds to only the active branch
(see 07 §Builtin console + comptime branch folding).

#### Socket builtin dispatch (F6, 2026-08-13) — `[updated: 2026-08-13]`

The same resolver (semantic_analyzer.zig:1441-1489) adds the 11 socket builtins by `child_0`
name ID (fields `socket_create_name_id` … `socket_close_name_id`). All resolve their value args
via `semanticAnalyzerResolveExpr`; fd/port are `i32`/`u32` (fd = i32, arch-independence ruling
m0544) — the emitted C bodies port `net_runtime.c:18-153` 1:1 (see 08 §6.9):

| Builtin | Args resolved | Returns |
|---------|---------------|---------|
| `@socketCreate(port: u32)` | `ec[0]` | `TYPE_I32` |
| `@socketBindListen(sock: i32, backlog: u32)` | `ec[0]`, `ec[1]` | `TYPE_I32` |
| `@socketAccept(sock: i32)` | `ec[0]` | `TYPE_I32` |
| `@socketConnect(sock: i32, port: u32)` | `ec[0]`, `ec[1]` | `TYPE_I32` |
| `@socketSend(sock: i32, buf: [*]const u8, len: u32)` | `ec[0]`, `ec[1]`, `ec[2]` | `TYPE_I32` |
| `@socketRecv(sock: i32, buf: [*]u8, len: u32)` | `ec[0]`, `ec[1]`, `ec[2]` | `TYPE_I32` |
| `@socketSelect(nfds: i32, readfds: ?[*]u8, writefds: ?[*]u8, exceptfds: ?[*]u8, timeout_ms: u32)` | `ec[0..4]` | `TYPE_I32` |
| `@socketFdZero(set: [*]u8)` | `ec[0]` | `TYPE_VOID` |
| `@socketFdSet(fd: i32, set: [*]u8)` | `ec[0]`, `ec[1]` | `TYPE_VOID` |
| `@socketFdIsset(fd: i32, set: [*]u8)` | `ec[0]`, `ec[1]` | `TYPE_BOOL` |
| `@socketClose(sock: i32)` | `ec[0]` | `TYPE_VOID` |

The three fd-set args of `@socketSelect` are optional (`?[*]u8` — `null` for unused sets); the
emitter null-coalesces them (`(NAME.has_value ? NAME.value : NULL)`, c89_emit.zig:3377-3398,
F6-review fix). Guarded repro: `repro/mi_matrix/net_builtin_test`.

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

### semanticAnalyzerResolveLogical (`sf/src/semantic_analyzer.zig:569-577`)

`[inference: both operands TYPE_BOOL → TYPE_BOOL; else TYPE_VOID]`

Dispatched from ResolveExpr for bool_and/bool_or. Returns TYPE_BOOL only if both lhs and rhs are TYPE_BOOL.

### semanticAnalyzerResolveNegate (`sf/src/semantic_analyzer.zig:579-586`)

`[inference: INT_LIT → INT_LIT; numeric → same type; else VOID]`

Dispatched from ResolveExpr for negate. Returns the inner type if numeric.

### semanticAnalyzerResolveBitNot (`sf/src/semantic_analyzer.zig:588-595`)

`[inference: INT_LIT → INT_LIT; integer → same type; else VOID]`

Dispatched from ResolveExpr for bit_not. Returns the inner type if integer.

### semanticAnalyzerResolveFnCall (`sf/src/semantic_analyzer.zig:649-800`)

`[inference: direct callee → resolve return type → push/pop expected types for params → record coercions]`

**Phase 1 — direct call optimization (callee is ident_expr):**
- Symbol lookup. If `SymbolKind.function` with decl_node:
  - Look up return_type_node in resolved type table.
  - If not resolved, try name cache (module-0 + per-module) or `resolveTypeExprFull`.
  - If `direct_ret != 0`, iterate args against fn params: `call_param_map` or `xt_items[params_start+ai]` → `pushExpectedType` → resolve → `tryRecordCoercion`.

**Phase 2 — general callee:**
- Resolve callee expr. If ptr_type pointing to fn_type, dereference.
- If not fn_type: emit `FN3:N<T>T<K>` marker, return `TYPE_VOID`.
- **Variadic arity (2026-08-06, `semantic_analyzer.zig:759-797`):** read
  `fnp.flags_packed & 0x01` → `is_var`. When variadic, require `args.len >=
  params_count` (a short call returns `fnp.return_type` leniently); a
  non-variadic call requires an exact match. The first `params_count` args are
  typed against the named params; the extra variadic args are resolved with
  `pushExpectedType(0)` and recorded into `call_arg_types` (loose typed).
- Per-arg loop: `pushExpectedType(param_type)` → resolve → `popExpectedType` → `tryRecordCoercion`.

### semanticAnalyzerResolveSwitchExpr (`sf/src/semantic_analyzer.zig:1046-1179`)

`[inference: resolve condition → set current_switch_cond_tu → resolve prongs → unify types → return unified]`

1. Increment `switch_depth`. Marker `SE`.
2. Resolve condition. If tagged_union_type, set `current_switch_cond_tu`.
3. Iterate prongs. For each:
   - If else-prong with capture (flag 0x10) → error `ERR_3001`.
   - If `current_switch_cond_tu != 0` and prong has cases:
     - For each case: if enum_literal or undefined_literal → resolve via `semanticAnalyzerResolveEnumLiteral`.
     - If capture (flag 0x10): register local decl with field type from TU fields.
   - Resolve prong body expr.
   - **Type unification**: track `unified` type. Coercion-aware: if bt can coerce to unified, record coercion. If unified can coerce to bt, swap. If both numeric and one is int_lit → use concrete.
   - **MIX else-branch (non-coercible prong types, `semantic_analyzer.zig:1167`):**
     [updated: 2026-08-07] records `resolvedTypeTableSet(..., TYPE_VOID)` for the switch node and
     **`continue`s to the next prong** (F4, commit b1b3f7e9) — the conflicting prong is skipped from
     the `unified`-type contribution but ALL remaining prongs still resolve. Previously this branch
     `return type_mod.TYPE_VOID;` — aborting `resolveSwitchExpr` mid-loop, so any later prong (e.g.
     a function-call prong) was never sema'd and `call_arg_types` was never populated
     (`semantic_analyzer.zig:775`), leaving the lowerer's fallback to type call-arg slots as raw
     lowered types (wrong `&arena`→`unsigned int`, `"save.dat"`→`char*`). Fixes
     `switch_mixed_case_argtype`.
4. Return unified type. Marker `SWU:n<t>U:t<unified>`.

### semanticAnalyzerResolveEnumLiteral (`sf/src/semantic_analyzer.zig:838-901`)

`[inference: switch context → expected type stack → tagged union field scan → error or return type]`

1. If `current_switch_cond_tu != 0`: scan TU fields for matching name_id. Register `enum_value_table[node_idx]=fi`. Return `current_switch_cond_tu`.
2. If `expected_type_stack` top is tagged_union: scan fields. If field type is VOID → register enum value, return top type. If field type is non-VOID → error `ERR_3008` "enum literal member requires payload".
3. If field not found in expected TU → error `ERR_3009` "unknown enum literal member".
4. Fallback → return `TYPE_VOID` (unresolvable).

### semanticAnalyzerResolveStructInit (`sf/src/semantic_analyzer.zig:1029-1095`)

`[inference: explicit type → expected type → scan fields → push/pop expected types for each init]`

- If type is tagged_union: iterate field_inits, find matching field by name_id, push expected type, resolve init, record coercion.
- If type is struct: same process on struct fields.
- If type is union: same process on union members (FIXED 2026-08-13).
- **FIXED — bare `union_type` target (2026-08-13, F1):** the dispatcher now
  has a `union_type` branch (semantic_analyzer.zig:1094-1121) mirroring the
  `struct_type` loop — scans `un_items[payload_idx].fields_start/
  .fields_count` for the matching member by `name_id`, push/pop expected
  type, resolve the init, `tryRecordCoercion` per member, and
  `resolvedTypeTableSet(node_idx, union_type)`. A bare-union struct literal
  (`Inner{ .Int = v }`) — including nested inside an outer struct literal
  (`Wrapper{ .tag = ..., .data = Inner{ .Int = v } }`) — now resolves to the
  union type and records its member coercion (was `TYPE_VOID` with nothing
  recorded, leaving the nested literal untyped). Reproduction:
  `repro/mi_matrix/union_literal_nested_xmod` prints `42` (was gcc
  `'zT_3' undeclared`). Same shape as `examples/z98/lisp_interpreter`
  `token.zig` `Token{ .tag = ..., .data = TokenData{ .Int = v } }`.
  [updated: 2026-08-13]

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

### semanticAnalyzerResolveStmtIter (`sf/src/semantic_analyzer.zig:1599-1918`)

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
- **`labeled_stmt` → transparent unwrap (F1, 2026-08-07, semantic_analyzer.zig:1767-1770):** if
  `child_0 != 0`, push it onto the stmt work queue — the label is a pure wrapper, the inner
  statement resolves as if unlabeled. (Defensive expr-redirect twin at
  semantic_analyzer.zig:1341: a `labeled_stmt` reaching `resolveExpr` re-enters the stmt iter and
  returns `TYPE_VOID`, preventing the `error[3020]` unhandled-else.)
- Other → `semanticAnalyzerResolveExpr`.

Skips `fn_decl` children (inner functions handled by outer phase).

#### Worklist strategy: why iterative, not recursive (`[fprintf]` + `[inference]`)

`semanticAnalyzerResolveStmtIter` (semantic_analyzer.zig:1539-1723) is explicitly iterative: it
pushes the root statement onto `stmt_work`, then pops/processes in a `while` loop until drained
back to the entry `sp_base` (semantic_analyzer.zig:1540-1543). Three reasons this design was
chosen over plain recursion:

1. **Bounded C-call depth for statement trees.** The companion pre-pass `resolveStmtTypes`
   (main.zig:413-462) is recursive and hard-caps at `depth > 16` (main.zig:414). The real
   semantic pass must not blow the bootstrap C89 stack on deeply nested blocks; the worklist
   keeps C-call depth flat regardless of statement nesting.
2. **Explicit source-order traversal.** Children are pushed in reverse
   (semantic_analyzer.zig:1553-1562) so the pop order is pre-order source order — the same
   guarantee a recursive descent gives, without recursion. `constraintCheckerCheckBreakContinue`
   uses the same explicit-`(node_idx, depth)`-stack pattern (constraint_checker.zig:70-109).
3. **Per-module lifecycle.** The worklist lives on the `SemanticAnalyzer`, which is created per
   module (main.zig:356) on the scratch arena (reset at main.zig:345). `sp_base` is captured at
   entry, so every fn body drains exactly back to its base — the worklist is always empty
   (at base) between fn bodies and dies with the module's scratch reset.

The worklist is statement-scoped: *expression* subtrees are still resolved recursively via
`semanticAnalyzerResolveExpr` (semantic_analyzer.zig:1131), which re-enters the worklist only for
statement-like nodes (var_decl/defer/errdefer, semantic_analyzer.zig:1281-1283). A deep
expression nest still recurses; the worklist absorbs only statement nesting.

**Measured max worklist depth** (`stmt_work_len`, `[fprintf]` on
`semanticAnalyzerStmtWorkPush`; max over push records, `[P5W]`):

| Example | Max worklist depth | Deepest fn | Pushes |
|---------|:------------------:|------------|-------:|
| mud_server | 13 | main | 159 |
| game_of_life | 21 | main | 97 |
| lisp_interpreter_curr | 18 | main | 545 |
| json_parser | 16 | parseObject | 301 |

The worklist depths stay in the 13-21 range and are never limited by the 16-deep recursion cap
that `resolveStmtTypes` needs — game_of_life's `main` reaches 21 pending statements, deeper than
the recursive pre-pass allows. The worklist is what lets statement nesting exceed recursion depth
without C-stack growth.

### semanticAnalyzerResolveStmt (`sf/src/semantic_analyzer.zig:1839-1841`)

`[inference: delegate to semanticAnalyzerResolveStmtIter]`

Public entry point. Thin wrapper around semanticAnalyzerResolveStmtIter.

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

### semanticAnalyzerCaptureType (`sf/src/semantic_analyzer.zig:165-172`)

`[inference: if optional → unwrap payload; else return cond_type as-is]`

Unwraps optional types in if/while/for capture expressions. If cond_type is optional, returns the payload type; otherwise returns cond_type unchanged.

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

### semaTraceStep (`sf/src/semantic_analyzer.zig:1725-1743`)

`[inference: follow ident_expr → var_decl → slice_expr → ident_expr chain, up to 3 steps]`

Source-tracing helper for index-access error messages. Follows a variable name through up to 3 levels of var_decl/slice_expr indirection to find the original source name. Called by semanticAnalyzerResolveIndexAccess.

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

### errLitSrcType (`sf/src/semantic_analyzer.zig:622-631`)

`[inference: if child is error_literal and target is error_union → return error_set; else ret_val]`

Helper for tryRecordCoercion and resolveReturnStmt. Extracts the error set type from an error union target when the source node is an error literal.

### resolveReturnStmt (`sf/src/semantic_analyzer.zig:633-647`)

`[inference: push expected fn return → resolve expr → record coercion]`

If child exists: `pushExpectedType(current_fn_return)` → resolve → `popExpectedType`. If `current_fn_return` is non-zero non-void: `tryRecordCoercion` with `errLitSrcType`.

### tryRecordCoercion (`sf/src/semantic_analyzer.zig:597-618`)

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

#### Measured CoercionKind distribution (`[markers]` CCK:ca / CCK:vr / COR:K)

`CCK:ca` (semantic_analyzer.zig:615) logs every `classifyCoercion` result in `tryRecordCoercion`;
`CCK:vr` (semantic_analyzer.zig:1630) logs the var-decl path; `COR:K` (semantic_analyzer.zig:618)
logs only coercions actually recorded (`ck != none` or null→ptr). Per-example `CCK:ca` counts below
(the recorded subset — `ck != none` — equals `COR:K`; the trailing `none(0)` column is the `CCK:ca`
kind-0 count, which `COR:K` excludes, e.g. lisp 3 / json 2):

| Example | wrap_optional(1) | wrap_error_success(2) | wrap_error_err(3) | array_to_slice(5) | string_to_slice(8) | const_qualify(12) | int_literal_coerce(15) | wrap_optional_null(16) | none(0: CCK:ca kind-0 count; excluded from COR:K) |
|---------|:----:|:----:|:----:|:----:|:----:|:----:|:----:|:----:|:----:|
| mud_server | 1 | 0 | 0 | 0 | 10 | 1 | 15 | 2 | 0 |
| game_of_life | 0 | 0 | 0 | 0 | 0 | 4 | 30 | 0 | 0 |
| lisp_interpreter_curr | 15 | 60 | 53 | 1 | 53 | 6 | 30 | 1 | 3 |
| json_parser | 1 | 15 | 14 | 0 | 1 | 1 | 19 | 1 | 2 |

Var-decl path (`CCK:vr`): mud 2×none/2×string_to_slice/5×int_literal_coerce;
gol 2×none/9×int_literal_coerce; lisp 6×none/18×int_literal_coerce/2×wrap_optional_null;
json 3×none/8×int_literal_coerce.

Takeaways:
- `int_literal_coerce` (15) is the most frequent recorded coercion in **all 4 examples**
  (mud 15, gol 30, lisp 30, json 19): literals resolve to `TYPE_INT_LIT` and are coerced to a
  concrete numeric at assignment / call-arg / return.
- Error-union wrapping (`wrap_error_success` 2 + `wrap_error_err` 3) dominates the error-heavy
  examples lisp (113 recorded) and json (29), and is absent from mud/gol.
- `string_to_slice` (8) is heavy in mud (10) and lisp (53) — `[*c]u8` string literals coerced to
  `[]const u8` slices.
- Never recorded in any example: `unwrap_optional` (4 — added directly, not via
  `classifyCoercion`, at semantic_analyzer.zig:818/1256), `array_to_many_ptr` (6),
  `slice_to_many_ptr` (7), `string_to_many_ptr` (9), `string_to_ptr` (10),
  `ptr_to_optional_ptr` (11), `int_widen` (13), `float_widen` (14). The 4 examples therefore
  exercise only 8 of the 17 non-`none` variants.

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

#### coercionTableEnsureCapacity (`sf/src/coercion.zig:43-53`)

`[inference: grow-by-doubling from 8, memcpy entries, update cap]`

Internal grow helper for CoercionTable. Called by coercionTableAdd when entries_len >= entries_cap.

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

#### resolvedTypeTableEnsureCapacity (`sf/src/resolved_type_table.zig:37-49`)

`[inference: grow-by-doubling from 8, memcpy entries, update cap]`

Internal grow helper for ResolvedTypeTable entries array. Called by resolvedTypeTableSet when entries_len >= entries_cap.

#### sourceTableEnsureCapacity (`sf/src/resolved_type_table.zig:73-84`)

`[inference: grow-by-doubling from 8, memcpy u32 items, update cap]`

Internal grow helper for ResolvedTypeTable source items array. Called by resolvedSourceTableSet when source_len >= source_cap.

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
