# slice_of_slice_xmod — D2 repro (slice whose element is a synthetic composite)  [Task I2, 2026-10-09]

## What it tests
A struct with **two distinct nested-slice types** in Zig/Z98:

```zig
pub const T = struct {
    announce_list: [][]const u8,   // slice of slice
    piece_hashes:  [][20]u8,       // slice of array
};
```

In Zig `[][]const u8` and `[][20]u8` are **distinct types**, so each field must
get its own C slice typedef. This dir puts the slice-of-slice field first so the
emitter registers the slice-of-slice element first and the *shared* typedef is
the slice-of-slice shape. `main` builds one element of each and prints both
lengths. Expected stdout after a correct fix: `11\n` (and no warnings).

## Zig semantics (the reference)
`[][]const u8` (element `[]const u8`, a slice) and `[][20]u8` (element `[20]u8`,
an array) are different types. A backend must emit a different C typedef for
each; today both collapse because a *synthetic* element type has `name_id == 0`
and the slice branch of `getCTypeName` takes the element name from that id.

## Pre-fix symptom (seed v94, /tmp/z9_m0_seed/zig1_5_clean) — classified OK-by-compile, WITH warning
`zig1 -ffast` accepts the program; the emitted C compiles (gcc rc=0) but with a
`-Wincompatible-pointer-types` warning. The single shared slice typedef is
written with the **slice-of-slice** element pointer:

Emitted `zig_special_types.h`:
```c
/* []const u8 */
typedef struct { unsigned char* ptr; unsigned int len; } zT_8F083A69_Slice_zT_0B42B2F8_u;
/* [][]const u8 AND [][20]u8 share this one (empty-name hash zT_811C9DC5_) */
typedef struct { zT_8F083A69_Slice_zT_0B42B2F8_u* ptr; unsigned int len; } zT_9DFA8D74_Slice_zT_811C9DC5_;
```

Emitted `main_E4438E27.h` (both fields declared with the SAME typedef):
```c
struct zT_D10C0B43_T {
	zT_9DFA8D74_Slice_zT_811C9DC5_ announce_list;
	zT_9DFA8D74_Slice_zT_811C9DC5_ piece_hashes;   /* slice-of-array field */
};
```

gcc (canonical corpus flags) exact warning (`main_E4438E27.c:95`):
```
main_E4438E27.c:95:15: warning: assignment to 'zT_8F083A69_Slice_zT_0B42B2F8_u *' from incompatible pointer type 'unsigned char (*)[20]' [-Wincompatible-pointer-types]
   95 |     zT_30.ptr = zT_28;
      |               ^
```
(`zT_28` is the slice-of-array element pointer `zT_4028D896_Arr_unsigned_char_2*`,
i.e. `unsigned char (*)[20]`; the field expects the slice-of-slice element
pointer.) The warning names the collapse exactly. The runtime value is correct
only by luck of the hoisted temp: `build_target.sh` links rc=0 and `prog` prints
`11`.

## Compiler locus (seed v94, `sf/src/c89_emit.zig`)
- **Slice branch** `getCTypeName` **`:1028-1036`** — element name taken from the
  element's `name_id` at **`:1031`**:
  `nameManglerMangle(mangler, elem_ty2.name_id, 2, 0)`. A synthetic element
  (`name_id == 0`) mangles to the empty-name string `zT_811C9DC5_`, so every
  `[]synthetic` element yields the same `Slice_zT_811C9DC5_`.
- **Array branch** `:959-967` (`emitArrayType` `:2116-2137`) — already correct:
  recurses `getCTypeName(reg, mangler, ap.elem)` (so `[20]u8` →
  `Arr_unsigned_char_2`, a distinct name).
- **Tuple branch** `:972-979` — already correct: uses the dense type id
  (`Tup_<tid>`), with a comment noting the same empty-name hazard.
- **Shared builder** `syntheticTypeName` `:882` — the name `[][]const u8` /
  `[][20]u8` both land on via the empty-name mangle.

## Classification
**OK pre-fix, but with the `-Wincompatible-pointer-types` warning above** (gcc
rc=0, so the compile-only corpus classify buckets it OK). It must be
**warning-free** after task F2 while keeping `[]u8`/`[]i32`/`[]Struct` typedefs
byte-identical.

## Exact repro commands
```
Z=/tmp/z9_m0_seed/zig1_5_clean
O=/tmp/i2_slice_of_slice_xmod; rm -rf "$O"; mkdir -p "$O"
$Z -ffast -o "$O" repro/mi_matrix/slice_of_slice_xmod/main.zig
for f in "$O"/*.c; do
  gcc -m32 -std=c89 -O0 -Wall -Wno-long-long -Wno-pointer-sign \
      -Wno-implicit-function-declaration -I sf/src/include -c "$f" -o /dev/null
done
# -> main_E4438E27.c:95:15 warning: assignment to
#    'zT_8F083A69_Slice_zT_0B42B2F8_u *' from incompatible pointer type
#    'unsigned char (*)[20]' [-Wincompatible-pointer-types]

# full link path
sh "$O/build_target.sh" linux "$O/prog" && "$O/prog"   # -> 11
```

## Perf/gates
- Corpus baseline at this HEAD: `1115 = 941 OK / 58 GREEN / 116 FAIL / 0 ICE / 0 CRASH`.
  This dir adds 1 OK (with warning) pre-fix; post-F2 it stays OK and warning-free.
- Stdlib: 283 PASS / 0 FAIL. Seed v94 fixed point `296c48f676deec290387b57132e4e2bd`.
