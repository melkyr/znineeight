# Nasty Bugs in zig0 (Z98 Bootstrap Compiler)

This file documents confirmed bugs in `zig0` — the C++98 bootstrap compiler that
translates Z98 (a Zig subset) to C89. These were discovered while building the
self-hosted compiler (`sf/src/`). Each bug has a standalone reproducer in this
directory.

## How to run a reproducer

```bash
cd /workspace/znineeight
./zig0 -o /tmp/repro.c tests/nasty_z0_bugs/<repro>.zig
gcc -std=c89 -m32 -Itmp -c /tmp/repro.c -o /tmp/repro.o 2>&1
```

Or compile to binary:

```bash
cd /workspace/znineeight
./zig0 -o /tmp/repro tests/nasty_z0_bugs/<repro>.zig
gcc -std=c89 -m32 -Wno-implicit-function-declaration -Iinclude \
  /tmp/repro/*.c src/runtime/zig_runtime.c -o /tmp/repro 2>&1
```

---

## Bug 1: String Literal → `Slice_u8` Only Works Once Per Function

**Status:** DOES NOT REPRODUCE with current zig0 binary (`/workspace/znineeight/zig0`).
All string literals correctly generate `__make_slice_u8` wrappers, including
in multi-module complex scenarios (verified with `sf/src/tests/repro_bug01.zig`).
Bug may have existed in an earlier version of zig0. If encountered in the wild,
workaround: assign to `const v: []const u8 = "..."`.

**Reproducer:** `bug01_string_literal_slice.zig` (negative — compiles cleanly)

---

## Bug 2: `pub fn foo(self: *T)` Inside Struct Declarations Rejected

**Status:** Confirmed. No fix planned (parser limitation).

**Summary:** Zig0's parser rejects `pub fn` declarations inside struct or union
types. The parser grammar for struct members does not accept method declarations.
The error comes from `parser.cpp:1464`.

**Root cause:** The Z98 grammar inherited by zig0 does not include method
syntax. Structs are pure data, not objects with methods.

**Workaround:** Define all struct "methods" as file-scope free functions with
a prefix naming convention:

```zig
const Foo = struct { x: i32 };

fn fooDoSomething(self: *Foo, arg: i32) void {
    self.x = arg;
}
```

**Reproducer:** `bug02_struct_method.zig`

---

## Bug 3: `&self.field` Always Fails (Address-Of Struct Field)

**Status:** Confirmed. No fix planned (codegen limitation).

**Summary:** Taking the address of a struct field accessed through a pointer
parameter (`self`) always fails. Zig0's codegen cannot emit `&self->field` for
nested pointer dereference + address-of.

**Root cause:** The C89 codegen for `&self.field` generates
`&(self->field)` which zig0's C codegen pipeline does not handle correctly
(struct pointer access generates a dereference expression, and `&` can't take
address of a temporary).

**Workaround:** Store sub-structs as heap-allocated pointers (`*Type` fields),
not inline values. Allocate them in init via `sandAlloc`:

```zig
// BROKEN
const Outer = struct {
    inner: Inner,
};
// &self.inner ← FAILS

// WORKING
const Outer = struct {
    inner: *Inner,
};
// self.inner ← WORKS (dereference pointer)
```

**Reproducer:** `bug03_and_self_field.zig`

---

## Bug 4: Name Mangling Collision (Vowel-Stripping Hash)

**Status:** Confirmed. zip0 compile passes (no errors), but gcc link fails with duplicate symbol.
Workaround required.

**Summary:** Two functions with different names can collide in zig0's C name
mangling if they share the same stripped form. zig0 strips consecutive vowels
before hashing: `u32ArrayListEnsureCapacity` and
`byteArrayListEnsureCapacity` both strip to
`rayListEnsureCapacity` and produce the same hash, causing gcc linker error
(`multiple definition of`).

**Root cause:** The mangling algorithm in `src/include/mangling.h` strips all
vowels from the function name, then hashes the result. Different original names
can reduce to the same stripped form. The hash is only a few hex digits,
compounding the collision probability.

**Workaround:** Use distinct **verbs** (not just different types) in function
names:

```zig
// COLLISION: both → "rayListGrow" after vowel strip
fn u32ArrayListEnsureCapacity(...) void;
fn byteArrayListEnsureCapacity(...) void;

// NO COLLISION: different verbs
fn u32ArrayListGrow(...) void;
fn byteArrayListGrow(...) void;
```

**Reproducer:** `bug04_name_mangling.zig`

---

## Bug 5: Cross-Module Name Mangling (Wrong Prefix)

**Status:** Confirmed. Workaround required.

**Summary:** When module A imports a function from module B and the import
statement uses a bare function reference (without a qualified module variable),
zig0 may mangle the call with module A's hash prefix instead of module B's
hash prefix. The linker then cannot find the symbol because the actual
definition uses module B's prefix.

**Root cause:** The name mangling prefix is derived from the source module
rather than the definition module when the import uses direct binding.

**Workaround:** Always import as a qualified module variable and call through
it:

```zig
// BROKEN: gets wrong module prefix
const stringInternerIntern = @import("string_interner.zig").stringInternerIntern;

// WORKING: gets correct module prefix
const interner_mod = @import("string_interner.zig");
// call: interner_mod.stringInternerIntern(self, text)
```

**Reproducer:** `bug05_cross_module_mangling.zig`

---

## Bug 6: `@panic(variable)` — Only `@panic("literal")` Works

**Status:** Confirmed. No fix planned.

**Summary:** Zig0 only supports `@panic` with a string literal argument.
Passing a variable (even a `[]const u8`) fails during C codegen.

**Root cause:** The `@panic` codegen path expects a `__bootstrap_panic` call
with a literal string. Variable expressions are not lowered to the required C
signature.

**Workaround:** Use `catch unreachable` instead of `@panic(msg)` where the
error path is truly unreachable. For test assertions, use hardcoded literal
strings in `@panic("failure message")`.

```zig
// BROKEN
const msg: []const u8 = "something went wrong";
@panic(msg);

// WORKING
@panic("something went wrong");

// Also works
catch unreachable;
```

**Reproducer:** `bug06_panic_variable.zig`

---

## Bug 7: `@src()` Returns Zeroes

**Status:** Confirmed. Not fixable without full source tracking.

**Summary:** `@src()` returns a `SrcLoc` struct with all fields set to zero
(`.file = 0`, `.line = 0`, `.column = 0`). Zig0 does not track source
locations for builtins.

**Workaround:** Pass source location manually or use `0` literal:

```zig
// BROKEN: all zeros
var loc = @src();

// WORKING: manual
assertEqBool(actual, expected, @intCast(u32, 0));
```

**Reproducer:** `bug07_src.zig`

---

## Bug 8: `@as(T, expr)` Not Supported

**Status:** Confirmed. Use nested `@intCast`.

**Summary:** Zig0 does not support the `@as()` builtin for type coercion.
Only `@intCast` and `@floatCast` are supported.

**Workaround:** Use `@intCast` (possibly nested for width/sign changes):

```zig
// BROKEN
var x = @as(u32, some_usize);

// WORKING
var x = @intCast(u32, some_usize);
```

**Reproducer:** `bug08_as.zig`

---

## Bug 9: `packed struct` with Union Field Rejected

**Status:** Confirmed. Use non-packed struct.

**Summary:** Zig0 supports `packed struct` for structs containing only integer
types (confirmed in `ast.zig:72`). However, `packed struct` is rejected when
the struct contains a union field.

**Workaround:** Use a non-packed struct, which follows natural alignment:

```zig
// REJECTED
const Token = packed struct {
    kind: TokenKind,
    span_start: u32,
    span_len: u16,
    value: TokenValue,   // ← union field triggers rejection
};

// ACCEPTED
const Token = struct {
    // ... same fields, but 24 bytes instead of 16
};
```

**Reproducer:** `bug09_packed_struct_union.zig`

---

## Bug 10: `0xFFFFFFFFFFFFFFFF` Emits C89 Decimal Warning

**Status:** Confirmed. Warning only, not an error.

**Summary:** Zig0 emits `0xFFFFFFFFFFFFFFFF` as the C89 decimal literal
`18446744073709551615`. C89 does not have a suffix for `unsigned long long`,
so this generates warnings about "decimal constant is unsigned only in ISO C90"
and "integer constant is so large that it is unsigned".

**Workaround:** Accept the warnings (they are harmless on C99+ compilers).
Add `-Wno-long-long` to the GCC flags to suppress.

```bash
gcc -std=c89 -Wno-long-long ...
```

**Reproducer:** `bug10_u64_max_literal.zig`

---

## Bug 11: `__make_slice_u8` Caller Has No Slice_u8 Declaration

**Status:** DOES NOT REPRODUCE with current zig0 binary. Linker errors from
missing `Slice_u8` declaration were not observed. Removing this as a duplicate
of bug01.

**Reproducer:** None (covered by bug01, which also does not reproduce).

---

## Bug 12: Arena-Returned Slice Lifetime Violation

**Status:** Confirmed. Cannot be fixed at Z98 level.

**Summary:** Returning a slice from an arena allocator function creates an
implicit lifetime dependency. The Z98 code allocates bytes and returns
`buf[0..len]`, which zig0 translates to a C struct by value. The pointer
inside the C struct may dangle when the arena resets.

**Root cause:** Z98's slice type `Slice_u8` is a C struct containing a pointer
and a length. Returning it from a function copies the struct, but the arena
owns the memory. Arena resets invalidate the pointer without the caller knowing.

**Workaround:** Return `[*]u8` (raw pointer) and have the caller construct
the slice inline:

```zig
// FRAGILE: lifetime ties to arena
fn getText(self: *Interner) []const u8 {
    return self.entries[self.id].text;  // dangling if arena resets
}

// ROBUST: caller controls lifetime
fn getText(self: *Interner) []const u8 {
    return self.entries[self.id].text;  // safe if arena is permanent
}

// For diagnostic printing, access the internal storage directly:
var entries = self.interner.entries;  // *InternArrayList
var text = entries.items[d.message_id].text;  // []const u8
writeStr(text);
```

**Reproducer:** `bug12_arena_slice_lifetime.zig`
