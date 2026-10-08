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

## D2 — A slice whose element is a synthetic composite aliases another nested-slice C typedef

**Status:** OPEN (compiler gap). Workaround in the example; no compiler change.

**Symptom.** Two different nested-slice types emit the *same* C slice typedef
name, so the second field is declared with the first's element pointer type.
`gcc` accepts it with a warning (`-Wincompatible-pointer-types`), and the value
is correct only by luck of the emitted temporary. A struct with both a
`[][]const u8` field and a `[][20]u8` field triggers it.

**Cause.** In `sf/src/c89_emit.zig`, `getCTypeName` derives a slice's C name
from its element's **name id**:

```zig
// slice branch, ~c89_emit.zig:1028-1035
var elem_ty2 = reg.types_items[sp.elem];
var elem_mid2 = nameManglerMangle(mangler, elem_ty2.name_id, 2, 0);  // <-- name_id
```

Every *synthetic* type (slice/array/tuple/optional) has `name_id == 0`, so a
slice whose element is itself a synthetic composite gets its element name from
id 0 — the same mangled string (`…Slice_zT_811C9DC5_`, the hash of the empty
string) for every such element kind. The **array** branch of the same function
recurses correctly (`c89_emit.zig:959-966`, `getCTypeName(reg, mangler,
ap.elem)`), and the tuple branch already sidesteps this with a per-type id.

**Minimal reproducer.**

```zig
// repro.zig
const std = @import("std.zig");

pub const T = struct {
    announce_list: [][]const u8,
    piece_hashes: [][20]u8,
};

pub fn main() void {
    var buf: [64]u8 = undefined;
    var inner: []const u8 = buf[0..4];
    var list: [1][]const u8 = undefined;
    list[0] = inner;
    var hashes: [1][20]u8 = undefined;
    var t: T = .{ .announce_list = list[0..1], .piece_hashes = hashes[0..1] };
    std.io.printInt(@intCast(i32, t.piece_hashes.len));
    std.io.write("\n");
}
```

```
zig1 -ffast -o /tmp/d2repro/out repro.zig
cd /tmp/d2repro/out && sh build_target.sh linux prog
# -> repro_*.c: warning: assignment to
#    'zT_..._Slice_zT_0B42B2F8_u *' from incompatible pointer type
#    'unsigned char (*)[20]' [-Wincompatible-pointer-types]
```

Emitted `zig_special_types.h` shows the collapse — the `[][]const u8` typedef is
reused for the `[][20]u8` field:

```c
/* []const u8 */
typedef struct { unsigned char* ptr; unsigned int len; }
    zT_8F083A69_Slice_zT_0B42B2F8_u;
/* [][]const u8 AND [][20]u8 share this one */
typedef struct { zT_8F083A69_Slice_zT_0B42B2F8_u* ptr; unsigned int len; }
    zT_9DFA8D74_Slice_zT_811C9DC5_;
```

**Workaround (used by z9torr, spec amendment 2026-10-08).** Keep at most one
"slice of a synthetic composite" type in the program. `piece_hashes` becomes a
flat `[]const u8` (20 bytes per piece) instead of `[][20]u8`, leaving
`announce_list: [][]const u8` as the only nested-slice type — and therefore the
correct owner of the shared typedef. Semantics unchanged; `info_hash` unaffected.

**Proper fix (not done; would rotate the seed).** Recursively derive the slice
element's C name as the array branch already does. A targeted form — recurse
only when the element's `name_id == 0` — leaves primitive slices (`[]u8`,
`[]i32`) byte-identical and fixes only nested-composite slices. Any `[][]T`
program hits this today.

---

## How these defects are exposed

Each entry above pairs a **minimal Z98 program** with the **emit + gcc
commands** and the **exact compiler/gcc failure**, so the defect is
reproducible in isolation, outside the example. When a workaround is adopted,
the example's source and its spec are updated and the entry records the
workaround + commit; the defect itself stays listed as OPEN until (and unless)
the compiler is fixed.

_(Add new entries as D2, D3, … as they are found during M1–M4.)_
