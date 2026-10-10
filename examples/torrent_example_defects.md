# z9torr example — compiler defects found

This log records **compiler defects / gaps discovered while building the
`z9torr` BitTorrent example** (`examples/z98/z9torr/`), each with a minimal
reproducer, the exact failure, and the workaround the example uses. The
workarounds are example/spec-level. **All five defects (D1–D5) are now FIXED**
in the compiler (plan `2026-10-09-zig1-codegen-defects-plan`, seed v95 rotated
2026-10-10); each entry below records its fix commit id and a note that the fix
reproduces **Zig semantics**, not merely `gcc` acceptance.

Related: `docs/superpowers/specs/2026-10-08-z9torr-bittorrent-client-design.md`
(the example's binding spec).

---

## D1 — A C keyword as a `union(enum)` tag emits invalid C89

**Status:** FIXED (F1, commit `69e82cd8`, 2026-10-09). Union member names are C-keyword-mangled consistently at the declaration and every access site, so any valid Z98 tag compiles. The fix reproduces Zig semantics (any identifier is a valid tag), not merely `gcc` acceptance.

**Symptom (pre-fix).** A tagged union whose variant tag is a C keyword compiles as Zig
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

**Status:** FIXED (F2, commit `e21dd31b`, 2026-10-09). A slice whose element is synthetic now recurses to derive a distinct element C name, so `[][]const u8`, `[][20]u8`, etc. get distinct typedefs (primitive/named element slices stay byte-identical). The fix reproduces Zig semantics (each `[]synthetic` is a distinct type), not merely `gcc` acceptance.

**Symptom (pre-fix).** Two different nested-slice types emit the *same* C slice typedef
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

**Status:** FIXED (F3, commit `06a7a793`, merged D3+D4, 2026-10-09). The shared frame-save fix pre-resolves the suppressed `load_global` alias (`temp_global_map`) before the save block, so the frame save/restore names a declared temp. The fix reproduces Zig semantics (a coroutine captures referenced state across a suspension; a save stores a declared temp/global), not merely `gcc` acceptance.

**Symptom (pre-fix).** In a coroutine that passes the address of a module-global
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

**Status:** FIXED (F3, commit `06a7a793`, merged D3+D4, 2026-10-09). Same shared frame-save fix as D3 (the undeclared temp is the loop-carried `load_global` alias of the module global). The fix reproduces Zig semantics (the by-value struct-return is materialised and the aliased global is named), not merely `gcc` acceptance.

**Symptom (pre-fix).** Assigning a **struct-returning call's result** directly to a
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

**Cause (corrected 2026-10-09, I4).** Same frame-save temp-declaration defect as
D3. The undeclared temp is **not** the struct-return temporary — that one *is*
materialised and declared (`zT_398`). It is the **loop-carried `load_global`
alias of the module global** (`g_reader`), lowered by `lowerLValueAddr`
(`sf/src/lower.zig:2264-2268`) → `lowerGlobalRef:3931-3932`, then suppressed by the
declaration loop (`sf/src/c89_emit.zig:3800-3909`) while `temp_global_map`
(`resolveTempName:6614-6628`) is still empty at the frame-save site. Observed
trigger: `g_reader = std_stream.initMsgReader(...)` inside a suspending function
followed by two `&g_reader` call sites in a loop. D3 and D4 share one fix
(operator ruling 2026-10-09).

**Workaround (used by z9torr, M2 Task 4).** Do not route a struct-return
temporary through a global in the coroutine: initialise the `MsgReader` field
by field (`reader.src = ...; reader.buf = ...; reader.pending = ...;`) on a
coroutine local.

**Proper fix (not done; would rotate the seed).** Declare frame-save temps in
the emitted preamble; or materialise struct-return temps into a named local
before the global store in the async lowering.

---

## D5 — A store through a slice-index aggregate lvalue is silently lost (writes into a by-value copy)

**Status:** FIXED (F5, commit `ae156d26`, 2026-10-09). Non-tuple index-assign bases now route through address-taking exactly as `lowerFieldStore` does, so the chain `(slice.ptr + idx)->field[...]` is addressed once and the store lands in the element. The fix reproduces Zig semantics (index/field chains are lvalues) — the runtime repro output flips wrong→correct — not merely `gcc` acceptance.

**Symptom.** Writing a nested aggregate field through a slice/array index compiles
and links, but the store is **lost**: the emitter materialises a *by-value copy* of
the element struct and writes into the copy. `z9torr` hit this writing the client
peer_id into a scheduler slot:

```zig
// examples/z98/z9torr/main.zig (spawnPeerAt)
g_sched.peers[slot].peer_id[pid_i] = peer_id[pid_i];
```

Emitted C (`/tmp/z9_linbin/main_B8D622A5.c`, `spawnPeerAt`):

```c
zT_11 = zT_10[slot];      /* Peer copied BY VALUE into a local temp */
zT_12 = zT_11.peer_id;    /* pointer into the LOCAL copy */
zT_12[pid_i] = zT_7;      /* the store lands in the temp, not g_sched.peers[slot] */
```

So `g_sched.peers[slot].peer_id` stays zero and every outgoing handshake
advertises an all-zero peer_id (visible in `lin_bin/z9torr.log`). No gate caught it
because the mocks validate only `info_hash`.

**Zig semantics (the reference).** In real Zig, index/field chains are **lvalues**:
`arr[i].field[j] = x` writes through the address `&arr[i].field[j]`. Z98 must
reproduce that, not copy.

**Root cause.** The by-value materialisation happens in lowering, not (only) in
emission:

- `sf/src/lower.zig` `lowerAssignLValue`, `index_access` arm — **`:2484-2531`**: the
  base is lowered with a **value read** (`lowerExpr(...)` at `:2487`) instead of an
  address; the address path exists only for the *tuple* sub-case (`:2493-2508`).
  Contrast the correct sibling `lowerFieldStore`, which takes nested bases by address
  at **`:2878-2928`** (`index_access` base ptr+idx / `load_index{decay=1}`
  `:2878-2909`; field/deref/paren base `lowerLValueAddr` `:2910-2928`).
- The emission side then chains value copies: `emitBaseIdxAccess` **`c89_emit.zig:204-267`**
  (`load` `:229-251` value-copies the element; `assign` `:252-266`), `load_index`
  **`:7593-7596`**, `load_field` **`:7456-7513`**, `assign_index` **`:7226-7271`**,
  `store_field` **`:7514-7591`**, `addr_of_field` **`:7655-7694`**.

**Reproducer.** A standalone op in which a store through `slice[i].field[j]` must be
observed by a subsequent read/print (a runtime assertion — the compile-only corpus
classify cannot see a lost write):
`repro/mi_matrix/slice_index_field_store_xmod/`.

**Fix (proper Zig semantics).** Route non-tuple index-assign bases through
address-taking exactly as `lowerFieldStore` already does, so the whole chain
`(slice.ptr + idx)->field[...]` is addressed once and the store lands in the element.
The array branch is already correct.

**Equivalence gate.** The repro's runtime output changes from wrong→correct; the
z9torr `peer_id` becomes the real `-Z9T01-…`; all compiler gates (fixed point,
corpus, stdlib, examples, dump-MD5 re-baseline) apply.

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
the entry records the workaround + commit; the defect itself is listed **FIXED**
once the compiler is fixed. All five (D1–D5) are now FIXED; each entry records
its fix commit and that the fix reproduces Zig semantics. (D4 later became
reducible to the standalone `repro/mi_matrix/async_frame_structret_xmod`, whose
classify class flipped FAIL→OK at F3.)

_(Add new entries as D5, … as they are found during M1–M4.)_

---

## D6 — `@ptrFromInt` with a type argument is silently miscompiled instead of rejected

**Status:** OPEN (filed 2026-10-10 during the M5 `-fsafe` work). This is a
**compiler validation / wrong-accept** defect, **not** the anticipated `-fsafe`
failure: there is **no `-fsafe`/`-ffast` divergence** (both modes emit the same
wrong code). It did not block the M5 `-fsafe` mission — the example uses the
correct one-argument `@ptrFromInt(expr)` form — but it is filed here per the
standing rule that any compiler (not example) defect is recorded, never silently
skipped.

**Symptom.** Z98's language spec (`docs/reference/Language_Spec_Z98.md` §4) and
manual define `@ptrFromInt(expr)` — **one** argument, result type from context;
the two-argument form is `@intToPtr(T, value)`. `@ptrFromInt` with an explicit
type argument (`@ptrFromInt(*T, value)`) is nevertheless **accepted** and emits
wrong code: the cast's source operand is the **destination variable itself**
(an uninitialised local), not the constant/expression. The intended `value` is
dropped. The compiler should reject the extra argument with a diagnostic.

**Minimal reproducer.**

```zig
// repro.zig
const std = @import("std");
pub fn main() void {
    var p: *u8 = @ptrFromInt(*u8, 7);
    std.io.printInt(@intCast(i32, @intFromPtr(p)));
    std.io.write("\n");
}
```

```
zig1 -fsafe -o /tmp/d6out repro.zig
cd /tmp/d6out && sh build_target.sh linux /tmp/d6out/prog
/tmp/d6out/prog          # prints garbage (observed `1`), not `7`
zig1 -ffast -o /tmp/d6outf repro.zig   # identical emitted C
```

**Emitted C (both `-fsafe` and `-ffast`, byte-identical for this function).**

```c
void zF_EA90E208_main(void) {
    unsigned char* zT_1;
    ...
    unsigned char* p;
    zT_1 = (unsigned char*)(unsigned int)p;   /* reads p (uninitialised) -- should be 7 */
    p = zT_1;
    ...
}
```

`value` (`7`) never appears; the `@ptrFromInt` type argument is consumed and the
integer argument is lost, so the lowering's `int_to_ptr.value` temp resolves to
the result variable's slot. `@ptrFromInt(7)` (one argument) and
`@intToPtr(*u8, 7)` (two arguments, old spelling) both emit correct code
(`zT_1 = (unsigned char*)(unsigned int)zT_2;` with `zT_2 = 7;`), so the defect is
specific to `@ptrFromInt` receiving an extra type argument.

**Workaround (used by the M5 fix).** Use the documented one-argument
`@ptrFromInt(expr)` (result type inferred from the annotated target) or the
two-argument `@intToPtr(T, value)`. `peer.zig`'s `zeroPieceIO` uses
`@ptrFromInt(0)`.

**Proper fix (not done; compiler frozen during this task).** Diagnose an
`@ptrFromInt` call whose argument count exceeds one, or lower the extra type
argument explicitly if the two-argument spelling is meant to be supported.
