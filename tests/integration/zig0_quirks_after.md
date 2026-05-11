# Bug: C89FeatureValidator false positive on struct field access in function args

## Summary

The `C89FeatureValidator` (added in recent zig0 commits) flags non-trivial
function call arguments as "type expressions", producing false positives for
struct field access, enum value access, and return-value field chaining.

Root cause: `isTypeExpression()` in `ast_utils.cpp:33-40` treats ANY
`NODE_MEMBER_ACCESS` as a type expression if the member's resolved type is a
type (`SYMBOL_TYPE` or `SYMBOL_UNION_TYPE`). This is wrong — `tok.kind`
(where `tok` is a local variable and `kind` is an enum field) is a **value**
expression, not a **type** expression.

## Files and Locations

### 1. False positive trigger

**File:** `src/bootstrap/c89_feature_validator.cpp` lines 537-545

```cpp
// 1. Detect explicit generic call (type expression as argument)
if (call->args) {
    for (size_t i = 0; i < call->args->length(); ++i) {
        if (isTypeExpression((*call->args)[i], unit.getSymbolTable())) {  // ← false positive
            reportNonC89Feature(node->loc, "Generic function calls (with type arguments) are not C89-compatible.");
            break;
        }
    }
}
```

Every function call's arguments are checked. If ANY argument is flagged as a
"type expression", the entire call is rejected.

### 2. Root cause

**File:** `src/bootstrap/ast_utils.cpp` lines 33-40

```cpp
case NODE_MEMBER_ACCESS: {
    const ASTMemberAccessNode* ma = node->as.member_access;
    // 1. If the member points directly to a type symbol
    if (ma && ma->symbol) {
        Symbol* sym = ma->symbol;
        if (sym->kind == SYMBOL_TYPE || sym->kind == SYMBOL_UNION_TYPE)
            return true;  // ← BUG: fires for tok.kind because kind's TYPE is a SYMBOL_TYPE
    }
    // 2. If the whole expression resolved to an aggregate type
    if (node->resolved_type) {
        if (node->resolved_type->kind == TYPE_STRUCT  ||
            node->resolved_type->kind == TYPE_UNION   ||
            ...
```

For `tok.kind`:
- AST is `NODE_MEMBER_ACCESS` with `object = tok` (identifier), `field = kind`
- `ma->symbol` resolves to the `kind` field's declaration
- `ma->symbol->kind` is `SYMBOL_TYPE` because `kind`'s type is `TokenKind` (an enum)
- Function returns **true** — **incorrectly** treating a field value as a type

For `lexerNextToken(&l1).kind`:
- Same pattern: return value of function call, then `.kind` access
- `ma->symbol` resolves to `kind`'s declaration, type is `TokenKind`
- Function returns **true** for the same wrong reason

### 3. What the function SHOULD check

The function should distinguish between:
- **`token_mod.TokenKind`** — left side is a MODULE, right side IS a type → TRUE
- **`tok.kind`** — left side is a LOCAL VARIABLE, right side is a value → FALSE

The `NODE_MEMBER_ACCESS` case needs to check whether the LEFT operand
(`ma->object`) resolves to a type/module symbol, not just whether the
field's type is a type symbol.

## Reproduction

### Environment

```bash
g++ -std=c++98 -Isrc/include src/bootstrap/bootstrap_all.cpp -o sf/build/zig0
```

### Steps

**Minimal repro (3 files):** `tests/integration/import_repro/`

**a.zig:**
```zig
pub const Foo = struct { x: u32 };
```

**b.zig:**
```zig
const a = @import("a.zig");
pub fn makeFoo() a.Foo { return a.Foo{ .x = 42 }; }
pub fn useFoo(f: a.Foo) void { _ = f; }
```

**main.zig:**
```zig
const b = @import("b.zig");
pub fn main() void {
    var f = b.makeFoo();
    b.useFoo(f.x);  // ← triggers false positive: f.x passed as arg
}
```

**Run:**
```bash
./sf/build/zig0 -o /dev/null main.zig
```

**Expected:** clean exit, 5 `.c` files emitted.
**Actual:** `non-C89 feature` at `b.useFoo(f.x);`

### Full compiler test

```bash
./sf/build/zig0 -o sf/build/out.c sf/src/main.zig 2>&1 | grep "non-C89 feature" | wc -l
# → ~60 false positives across parser.zig, dump.zig, lexer.zig
```

## Suggested Fix

**File:** `src/bootstrap/ast_utils.cpp`, function `isTypeExpression()`,
`NODE_MEMBER_ACCESS` case (lines 33-53).

Replace lines 35-40 with a check that the LEFT operand (the object being
accessed) is itself a type or module:

```cpp
case NODE_MEMBER_ACCESS: {
    const ASTMemberAccessNode* ma = node->as.member_access;
    if (ma && ma->symbol) {
        // Only treat as type expression if the OBJECT is a type or module,
        // not if it's a local variable (e.g., tok.kind should be FALSE)
        if (ma->object) {
            bool object_is_type = false;
            switch (ma->object->type) {
                case NODE_IDENTIFIER: {
                    Symbol* obj_sym = symbols.lookup(ma->object->as.identifier.name);
                    if (obj_sym && (obj_sym->kind == SYMBOL_TYPE ||
                        obj_sym->kind == SYMBOL_UNION_TYPE ||
                        obj_sym->kind == SYMBOL_MODULE)) {
                        object_is_type = true;
                    }
                    break;
                }
                case NODE_TYPE_NAME:
                case NODE_POINTER_TYPE:
                case NODE_ARRAY_TYPE:
                    object_is_type = true;
                    break;
                default:
                    break;
            }
            if (object_is_type) {
                Symbol* sym = ma->symbol;
                if (sym->kind == SYMBOL_TYPE || sym->kind == SYMBOL_UNION_TYPE)
                    return true;
            }
        }
    }
    // Keep the rest of the original logic (resolved_type checks)
    ...
```

The key insight: `a.Foo` should be a type expression (object `a` is a module),
but `tok.kind` should not (object `tok` is a local variable).

## Impact

Without this fix, ALL function calls with struct/union field access arguments
are rejected, making it impossible to write idiomatic Zig code that chains
field accesses into function calls. This affects every `sf/src/` file that
reads struct fields and passes them to functions.
