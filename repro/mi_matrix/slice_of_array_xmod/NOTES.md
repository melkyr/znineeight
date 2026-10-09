# slice_of_array_xmod — D2 repro (slice whose element is a synthetic composite)  [Task I2, 2026-10-09]

## What it tests
Same two distinct nested-slice types as `slice_of_slice_xmod`, but with the
**field order reversed** so the emitter registers the slice-of-array element
first and the *shared* typedef is the slice-of-array shape:

```zig
pub const T = struct {
    piece_hashes:  [][20]u8,       // slice of array  (registered first here)
    announce_list: [][]const u8,   // slice of slice
};
```

This pins the **other direction** of the D2 collapse: whichever synthetic
element is registered first wins the shared `Slice_zT_811C9DC5_` typedef, and the
*other* field's assignment is the one gcc warns about. Expected stdout after a
correct fix: `11\n` (and no warnings).

## Zig semantics (the reference)
`[][20]u8` (element `[20]u8`, an array) and `[][]const u8` (element `[]const u8`,
a slice) are different types; each must get its own C typedef.

## Pre-fix symptom (seed v94, /tmp/z9_m0_seed/zig1_5_clean) — classified OK-by-compile, WITH warning
`zig1 -ffast` accepts the program; the emitted C compiles (gcc rc=0) but with a
`-Wincompatible-pointer-types` warning. The single shared slice typedef is
written with the **slice-of-array** element pointer:

Emitted `zig_special_types.h`:
```c
/* [20]u8 */
typedef unsigned char zT_4028D896_Arr_unsigned_char_2[20];
/* []const u8 */
typedef struct { unsigned char* ptr; unsigned int len; } zT_8F083A69_Slice_zT_0B42B2F8_u;
/* [][]const u8 AND [][20]u8 share this one (empty-name hash zT_811C9DC5_) */
typedef struct { zT_4028D896_Arr_unsigned_char_2* ptr; unsigned int len; } zT_9DFA8D74_Slice_zT_811C9DC5_;
```

Emitted `main_24C946E8.h` (both fields declared with the SAME typedef):
```c
struct zT_D10C0B43_T {
	zT_9DFA8D74_Slice_zT_811C9DC5_ piece_hashes;   /* slice-of-array field */
	zT_9DFA8D74_Slice_zT_811C9DC5_ announce_list;   /* slice-of-slice field */
};
```

gcc (canonical corpus flags) exact warning (`main_24C946E8.c:95`):
```
main_24C946E8.c:95:15: warning: assignment to 'unsigned char (*)[20]' from incompatible pointer type 'zT_8F083A69_Slice_zT_0B42B2F8_u *' [-Wincompatible-pointer-types]
   95 |     zT_30.ptr = zT_28;
      |               ^
```
(`zT_28` is the slice-of-slice element pointer `zT_8F083A69_Slice_zT_0B42B2F8_u*`;
the field expects the slice-of-array element pointer `unsigned char (*)[20]`.)
The runtime value is correct only by luck of the hoisted temp:
`build_target.sh` links rc=0 and `prog` prints `11`.

## Compiler locus (seed v94, `sf/src/c89_emit.zig`)
- **Slice branch** `getCTypeName` **`:1028-1036`** — element name taken from the
  element's `name_id` at **`:1031`**; a synthetic element has `name_id == 0` and
  mangles to the empty-name string `zT_811C9DC5_`, collapsing all `[]synthetic`
  element slices onto `Slice_zT_811C9DC5_`.
- **Array branch** `:959-967` (`emitArrayType` `:2116-2137`) — already correct
  (recurses the element); this is why `[20]u8` gets `Arr_unsigned_char_2`.
- **Tuple branch** `:972-979` — already correct (dense type id `Tup_<tid>`).
- **Shared builder** `syntheticTypeName` `:882`.

## Classification
**OK pre-fix, but with the `-Wincompatible-pointer-types` warning above** (gcc
rc=0). It must be **warning-free** after task F2.

## Exact repro commands
```
Z=/tmp/z9_m0_seed/zig1_5_clean
O=/tmp/i2_slice_of_array_xmod; rm -rf "$O"; mkdir -p "$O"
$Z -ffast -o "$O" repro/mi_matrix/slice_of_array_xmod/main.zig
for f in "$O"/*.c; do
  gcc -m32 -std=c89 -O0 -Wall -Wno-long-long -Wno-pointer-sign \
      -Wno-implicit-function-declaration -I sf/src/include -c "$f" -o /dev/null
done
# -> main_24C946E8.c:95:15 warning: assignment to 'unsigned char (*)[20]'
#    from incompatible pointer type 'zT_8F083A69_Slice_zT_0B42B2F8_u *'
#    [-Wincompatible-pointer-types]

# full link path
sh "$O/build_target.sh" linux "$O/prog" && "$O/prog"   # -> 11
```

## Perf/gates
- Corpus baseline at this HEAD: `1115 = 941 OK / 58 GREEN / 116 FAIL / 0 ICE / 0 CRASH`.
  This dir adds 1 OK (with warning) pre-fix; post-F2 it stays OK and warning-free.
- Stdlib: 283 PASS / 0 FAIL. Seed v94 fixed point `296c48f676deec290387b57132e4e2bd`.
