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

**Variants the compiler fix must cover.** `sf/src/main.zig:93`
(`include_dirs: [16][]const u8`) proves arrays-of-slices are fine — the
collision is on the element side of a *slice* `[]T` when `T` itself is
synthetic:
- `[][]const u8` — slice of slice (the original reproducer).
- `[][20]u8` — slice of array.
- `[][*]u8` — slice of many-pointer (z9torr argv; fixed in M1a).
- `[]?T` — slice of optional (expected to collide the same way).
- `[]tuple` — slice of tuple (expected to collide the same way).

All collapse to the same `…Slice_zT_811C9DC5_` typedef because each element type
is synthetic and therefore has `name_id == 0`.

**Design rule (safe/unsafe).** A Z98 slice `[]T` is safe **iff** `T` is a
primitive or a *named* type (struct/union/enum). It is **unsafe** when `T` is a
synthetic type (slice/array/pointer/optional/tuple): two different `[]synthetic`
types alias. To hold composites, use flat bytes (`[]const u8` + manual stride),
a fixed `[N]T` (the array branch recurses correctly), or a *named* wrapper
struct.

**Workaround (used by z9torr, spec amendments 2026-10-08 / M1a).** Remove every
`[]`-of-synthetic type by design: `piece_hashes` is a flat `[]const u8` (20
bytes per piece) instead of `[][20]u8`; `announce_list` is the fixed
`[8][]const u8` + `announce_count: u32` (extras dropped) instead of
`[][]const u8`; argv is `[*][*]u8` instead of `[][*]u8`. No slice whose element
is synthetic remains, so no shared typedef can be mis-applied. Semantics
unchanged; `info_hash` unaffected.

**Proper fix (not done; would rotate the seed).** Recursively derive the slice
element's C name as the array branch already does. A targeted form — recurse
only when the element's `name_id == 0` — leaves primitive slices (`[]u8`,
`[]i32`) byte-identical and fixes only nested-composite slices. Any `[][]T`
program hits this today.

---

## D3 — A module-global struct whose address is passed to a suspending call emits a frame-save from an undeclared temp

**Status:** OPEN (compiler gap). Workaround in the example; no compiler change.

**Symptom.** In a coroutine that passes the address of a module-global
`std_stream.MsgReader` to a suspending, cross-module call
(`wire.readMessageAsync`), the deferred-frame save emitted for the caller
performs a struct assignment **from a temporary that the emitter never
declares**. `zig1` accepts the program; `gcc` rejects the emitted C:

```
peer_07FFFED1.c:865:15: error: 'zT_144' undeclared (first use in this function); did you mean 'zT_194'?
```

Line 865 is inside the frame-save block (`*zT_455 = zT_144;`, where `zT_455`
is a `MsgReader *` into the coroutine frame and `zT_144` should be a
`MsgReader` value). `zT_144` is never declared; a sibling step function in the
same module declares an unrelated `zT_144`, so the temp-id counter appears to
collide across `__Z98Step_*` bodies.

**Reproducer (in-example; see note).** The defect is sensitive to the
enclosing step-function temp layout — it was **not** reducible to a
standalone two-function program (see "Reduction attempts"). The smallest
reliable reproducer is the two-line change to
`examples/z98/z9torr/peer.zig` at commit `a1e83657` that reverts the D3
workaround: make the `MsgReader` a **module global** and pass `&g_reader` to
`wire.readMessageAsync`:

```diff
--- a/examples/z98/z9torr/peer.zig
+++ b/examples/z98/z9torr/peer.zig
@@ var g_ps: piece.PieceState = undefined;
+var g_reader: std_stream.MsgReader = undefined;
 var g_ps: piece.PieceState = undefined;
@@ -225,4 +226,4 @@
-    var reader: std_stream.MsgReader = undefined;
-    reader.src = &peer.sock;
-    reader.buf = peer.read_buf[0..];
-    reader.pending = peer.read_buf[0..0];
+    g_reader.src = &peer.sock;
+    g_reader.buf = peer.read_buf[0..];
+    g_reader.pending = peer.read_buf[0..0];
@@
-        wire.readMessageAsync(&reader, &msg) catch break;
+        wire.readMessageAsync(&g_reader, &msg) catch break;
```

```
# from the repo root, with the patch applied to examples/z98/z9torr/peer.zig:
mkdir -p /tmp/d3out
/tmp/z9_m0_seed/zig1_5_clean -ffast -o /tmp/d3out examples/z98/z9torr/main.zig   # rc 0
# link (emits *.c then gcc -m32 -std=c89):
sh /tmp/d3out/build_target.sh linux /tmp/d3out/prog
# -> peer_*.c:<n>: error: 'zT_NNN' undeclared (first use in this function)
```

Exact observed (throwaway run `/tmp/z9_d3full_out`):

```
$ sh /tmp/z9_d3full_out/build_target.sh linux /tmp/z9_d3full_out/prog
env -u LD ... gcc -m32 -std=c89 ... peer_07FFFED1.c ...
peer_07FFFED1.c:865:15: error: 'zT_144' undeclared (first use in this function); did you mean 'zT_194'?
```

**Reduction attempts.** Standalone programs of the form "coroutine caller
passes `&g` (a global named struct) to a suspending callee" — including a
global `std_stream.MsgReader` (`/tmp/d3b.zig`, `/tmp/d3g.zig`), a global struct
with slice fields (`/tmp/d3e.zig`), a two-step cross-module wrapper
(`/tmp/d3g.zig` + `d3wrap.zig`), and a global struct with multiple slice fields
plus a local struct (`/tmp/d3h.zig`) — all **linked cleanly** (`gcc` rc 0).
The collision is therefore a function of the caller's total temp count and
ordering, not of any single construct; a minimal standalone reproducer would
require matching the emitted temp layout.

**Workaround (used by z9torr, M2 Task 4).** Keep the `MsgReader` a
**coroutine local** (`var reader: std_stream.MsgReader`), field-initialised in
place, and pass `&reader` to the suspending call. This lowers correctly and is
the form committed in `peer.zig`.

**Proper fix (not done; would rotate the seed).** In the async frame-save pass
(`sf/src/c89_emit.zig`), declare every temp that the save/restore emits for a
frame slot (do not assume a temp id is already declared from a sibling step
function's preamble), or allocate frame slots without a by-value struct temp.

---

## D4 — A by-value struct-return temporary assigned to a module global in a suspending function emits a frame-save from an undeclared temp

**Status:** OPEN (compiler gap). Workaround in the example; no compiler change.

**Symptom.** Assigning a **struct-returning call's result** directly to a
module-global inside a suspending function (here
`g_reader = std_stream.initMsgReader(...)`) makes the caller's frame-save
reference an undeclared temp of the returned struct type. Same emitted-C
symptom as D3, different trigger. `gcc`:

```
peer_E7BBEDD8.c:1804:15: error: 'zT_135' undeclared (first use in this function)
```

(`*zT_446 = zT_135;`, `zT_446` a `MsgReader *` frame slot.)

**Reproducer.** Same in-example patch as D3 but restore the **global
struct-return assignment** form instead of field-initialising:

```diff
-    var reader: std_stream.MsgReader = undefined;
-    reader.src = &peer.sock;
-    reader.buf = peer.read_buf[0..];
-    reader.pending = peer.read_buf[0..0];
+    g_reader = std_stream.initMsgReader(&peer.sock, peer.read_buf[0..]);
```

```
mkdir -p /tmp/d4out
/tmp/z9_m0_seed/zig1_5_clean -ffast -o /tmp/d4out examples/z98/z9torr/main.zig   # rc 0
sh /tmp/d4out/build_target.sh linux /tmp/d4out/prog
# -> peer_*.c:<n>: error: 'zT_NNN' undeclared (first use in this function)
```

Observed (first build of the Task-4 `peer.zig`):
```
peer_E7BBEDD8.c:1804:15: error: 'zT_135' undeclared (first use in this function)
```
(Removing the struct-return temp while keeping the global reader moved the
error to `zT_141`, i.e. D3's trigger; with a coroutine-local, field-initialised
reader the module links clean.)

**Cause.** Same deferred-frame-save temp-declaration defect as D3. A
by-value temporary produced by a struct-returning call is not declared in the
emitted function preamble, yet the frame-save block stores it into a
frame slot. It is filed separately because the trigger (a struct-return temp)
is independent of D3's (a global's address passed to a suspending call), and
both were observed while bringing up `peer.zig`.

**Workaround (used by z9torr, M2 Task 4).** Do not route a struct-return
temporary through a global in the coroutine: initialise the `MsgReader` field
by field (`reader.src = ...; reader.buf = ...; reader.pending = ...;`) on a
coroutine local.

**Proper fix (not done; would rotate the seed).** Declare frame-save temps in
the emitted preamble; or materialise struct-return temps into a named local
before the global store in the async lowering.

---

## How these defects are exposed

**D1/D2** each pair a **standalone minimal Z98 program** with the **emit + gcc
commands** and the **exact compiler/gcc failure**, so the defect is
reproducible in isolation, outside the example.

**D3/D4 are NOT reducible to a standalone minimal program.** Both are
deferred-frame-save temp-declaration defects that depend on the enclosing
coroutine step-function's **total temp count and ordering**, not on any single
construct: six standalone variants (a global `std_stream.MsgReader`, a global
struct with slice fields, a two-step cross-module wrapper, a multi-slice struct
plus a local struct, …) all linked cleanly. D3/D4 therefore ship the smallest
reliable **in-example patch reproducer** (the two-line change to
`examples/z98/z9torr/peer.zig`) together with the exact build/emit/link
commands and the observed `gcc` failure. This limitation is recorded explicitly
in each of the D3/D4 "Reduction attempts" / "Cause" notes. A true standalone
minimal reproducer would require matching the emitted temp layout.

When a workaround is adopted, the example's source and its spec are updated and
the entry records the workaround + commit; the defect itself stays listed as
OPEN until (and unless) the compiler is fixed.

_(Add new entries as D5, … as they are found during M1–M4.)_
