# Bug: C89 Codegen Rejects Global `const` with `@import()` Initializer

## Summary

zig0's C89 codegen (`codegen.cpp:444`) rejects **any** global `const`
declaration whose initializer is not a literal constant expression, even when
the value is a type from another module. The `isConstantInitializer()` function
only accepts literal expressions (integers, floats, strings, struct initializers,
etc.) and does not recognize `@import("mod.zig").Field` as a valid constant
initializer.

This prevents type aliases like:
```zig
const Token = @import("token.zig").Token;
```

The direct module import `const mod = @import("mod.zig");` IS correctly handled
(by a separate check at lines 435-437), but aliasing a **field** of that module
at global scope is not.

## Minimal Reproduction

```
tests/integration/import_repro/
├── a.zig          # defines Foo type
├── b.zig          # tries to alias Foo via @import()
├── bfixed.zig     # workaround: uses a.Foo instead of alias
└── main.zig       # entry point
```

**a.zig (type definition):**
```zig
pub const Foo = struct { x: u32 };
pub fn makeFoo(val: u32) Foo {
    return Foo{ .x = val };
}
```

**b.zig (broken — type alias via @import()):**
```zig
const Foo = @import("a.zig").Foo;   // ← ERROR
const a = @import("a.zig");
pub fn useFoo() void {
    var f = a.makeFoo(42);
    _ = f;
}
```

**main.zig:**
```zig
const b = @import("b.zig");
pub fn main() void {
    b.useFoo();
}
```

### Reproduce

```bash
./sf/build/zig0 -o /dev/null tests/integration/import_repro/main.zig
```

### Expected Output

Clean exit with `.c` and `.h` files emitted.

### Actual Output

```
tests/integration/import_repro/b.zig:1:7: error: global variable must have constant initializer
    const Foo = @import("a.zig").Foo;
          ^
    hint: Try using a literal or a constant expression
```

## Root Cause

In `src/bootstrap/codegen.cpp`, the function `generateVarDecl` (around line 430)
has three checks for global `const` declarations:

```cpp
// Line 435-437: Direct module imports are skipped ( OK )
if (decl->initializer->type == NODE_IMPORT_STMT || ...) { return; }

// Line 439: Type expressions are skipped ( SHORT-CIRCUITS for struct types )
if (decl->is_const && isTypeExpression(decl->initializer, ...)) { return; }

// Line 443-444: All other non-constant initializers → ERROR
if (!isConstantInitializer(decl->initializer)) {
    report(ERR_GLOBAL_VAR_NON_CONSTANT_INIT, ...);
}
```

For `const Foo = @import("a.zig").Foo;`:
- Initializer is `NODE_MEMBER_ACCESS` (not `NODE_IMPORT_STMT`) → **line 435 misses it**
- `isTypeExpression()` returns false for `NODE_MEMBER_ACCESS` of an import's field →
  **line 439 misses it** (this is the bug)
- `isConstantInitializer()` returns false → **error fires**

The fix is in `isTypeExpression()` (or in the check at line 439): it needs to
handle the case where a `NODE_MEMBER_ACCESS` resolves to a type via the module's
symbol table.

## Workaround (no zig0 changes)

Use module-qualified type names everywhere instead of global type aliases:

```zig
// BROKEN:
const Foo = @import("a.zig").Foo;
pub fn useFoo() void {
    var f: Foo = a.makeFoo(42);
}

// WORKS:
const a = @import("a.zig");      // module import is fine
pub fn useFoo() void {
    var f: a.Foo = a.makeFoo(42);  // use a.Foo type directly
}
```

**bfixed.zig (workaround):**
```zig
const a = @import("a.zig");
pub fn useFoo() void {
    var f: a.Foo = a.makeFoo(42);
    _ = f;
}
```

Confirmed working:
```bash
./sf/build/zig0 -o /dev/null tests/integration/import_repro/main.zig  # now uses bfixed.zig
# → clean exit, 5 .c files emitted
```

## Affected Codebase

The entire `sf/src/` compiler uses global type aliases pervasively (~20 files,
~40 lines). Every one of these triggers the error:

| Pattern | Files | Example |
|---------|-------|---------|
| `const X = @import("mod.zig").X;` | token, growable_array, source_manager, string_interner, diagnostics, parser, dump | `const Sand = @import("allocator.zig").Sand;` |
| `const X = mod.X;` (chained) | pal, lexer, main, tests | `const Token = token_mod.Token;` |

## Workaround to apply across sf/src/

Replace each global type alias with direct module-qualified usage. For example:

```zig
// parser.zig — before:
const Token = @import("token.zig").Token;
const AstStore = @import("ast.zig").AstStore;
pub const Parser = struct {
    tokens: []const Token,
    store: *AstStore,
    ...
};

// parser.zig — after:
const token_mod = @import("token.zig");
const ast_mod = @import("ast.zig");
pub const Parser = struct {
    tokens: []const token_mod.Token,
    store: *ast_mod.AstStore,
    ...
};
```

This is the only workaround that doesn't require zig0 C++ changes.
