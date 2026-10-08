# z9torr example — compiler defects found

This log records **compiler defects / gaps discovered while building the
`z9torr` BitTorrent example** (`examples/z98/z9torr/`), each with a minimal
reproducer, the exact failure, and the workaround the example uses. The
workarounds are example/spec-level; the underlying defects are compiler gaps
and remain **OPEN** (fixing them would change the compiler and rotate the
seed).

Related: `docs/superpowers/specs/2026-10-08-z9torr-bittorrent-client-design.md`
(the example's binding spec).

---

## D1 — A C keyword as a `union(enum)` tag emits invalid C89

**Status:** OPEN (compiler gap). Workaround in the example; no compiler change.

**Symptom.** A tagged union whose variant tag is a C keyword compiles as Zig
(Z98) but produces C that `gcc` rejects. The `std_bencode` `Value` type hit
this with the tag `int`:

```zig
pub const Value = union(enum) {
    int: i64,          // <-- tag name "int"
    bytes: []const u8,
    list: []Value,
    dict: []Entry,
};
```

Emitted `zig_special_types.h`:

```c
union {
    struct { long long _0; } int;   /* gcc: expected identifier before 'int' */
    ...
} zT_..._Value;
```

`gcc -m32 -std=c89` fails:

```
zig_special_types.h:693: error: expected identifier before 'int'
```

**Cause.** The emitter writes a `union(enum)` variant's tag **verbatim** as
the C union member name (`sf/src/c89_emit.zig` ~2008–2024). There is no
C-keyword mangling for union members. `@"int"` (the usual Zig escape for a
keyword identifier) is rejected by Z98 with `error[4]`, so the tag cannot be
kept and escaped.

**Minimal reproducer.**

```zig
// repro.zig
const std = @import("std.zig");

pub const V = union(enum) {
    int: i64,
    bytes: []const u8,
};

pub fn main() void {
    var v: V = .{ .int = 3 };
    switch (v) {
        .int => |x| { std.io.printInt(@intCast(i32, x)); std.io.write("\n"); },
        .bytes => |b| { _ = b; },
        else => {},
    }
}
```

```
zig1 -ffast -o /tmp/repro repro.zig
cd /tmp/repro && gcc -m32 -std=c89 -O0 -Wall -Wno-long-long \
    -Wno-pointer-sign -Wno-implicit-function-declaration -I . -c *.c
# -> error: expected identifier before 'int'
```

**Workaround (used by z9torr).** Spell the tag with a non-keyword name:
`int` → **`int_val`**. Semantics are identical; only the emitted C member
name changes. Recorded as the spec amendment of 2026-10-08
(`docs/superpowers/specs/2026-10-08-z9torr-bittorrent-client-design.md` §4.2),
commit `066d863a`.

**Rule going forward.** Never use a C keyword (`int`, `long`, `char`, `short`,
`float`, `double`, `struct`, `union`, `enum`, `default`, `register`, `return`,
`switch`, `case`, `signed`, `unsigned`, `void`, `volatile`, `const`, `static`,
`extern`, `sizeof`, `typedef`, `goto`, `if`, `else`, `for`, `while`, `do`,
`break`, `continue`, `inline`, `restrict`, …) as a `union(enum)` tag in Z98.

**Proper fix (not done; would rotate the seed).** C-keyword-mangle union
member names in `sf/src/c89_emit.zig` (or emit numeric member names with a
tag→name table), so any legal Z98 identifier tag compiles.

---

## How these defects are exposed

Each entry above pairs a **minimal Z98 program** with the **emit + gcc
commands** and the **exact compiler/gcc failure**, so the defect is
reproducible in isolation, outside the example. When a workaround is adopted,
the example's source and its spec are updated and the entry records the
workaround + commit; the defect itself stays listed as OPEN until (and unless)
the compiler is fixed.

_(Add new entries as D2, D3, … as they are found during M1–M4.)_
