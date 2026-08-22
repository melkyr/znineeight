# emission_misc_xmod — RED fixture for the 194-closeout `misc` class (R6, 5 errors)

Task R6 (2026-08-22). Branch `zig1_start`. Compiler under test: `/tmp/fx_subfolder/zig1`
(current; R tasks have not rebuilt it). Build recipe identical to the other emission_*_xmod
fixtures: emit with `--dump-c89 --output-dir`, compile emitted C with
`gcc -m32 -std=c89 -Wno-long-long -Wno-pointer-sign -I <repo>/sf/src/include`.

## Purpose

Full-graph (3-module: main/mod_a/mod_b + std) reproducer of the self-compile
residual `misc` class (5 errors):

| shape | self-compile site | text |
|---|---|---|
| subscripted value ×3 | `c89_emit_7CEF756E.c:59429,60066,60245:11` | `subscripted value is neither array nor pointer nor vector` |
| too few arguments ×1 | `main_9472B9CB.c:608:5` | `too few arguments to function 'zF_EA90E208_main'` |
| aggregate value ×1 | `c89_emit_7CEF756E.c:63706:5` | `aggregate value used where an integer was expected` |

## Self-compile lines reproduced (source of truth: `/tmp/emit_errs_e2down.txt`)

```
c89_emit_7CEF756E.c:59429:11: error: subscripted value is neither array nor pointer nor vector
c89_emit_7CEF756E.c:60066:11: error: subscripted value is neither array nor pointer nor vector
c89_emit_7CEF756E.c:60245:11: error: subscripted value is neither array nor pointer nor vector
main_9472B9CB.c:608:5: error: too few arguments to function 'zF_EA90E208_main'
c89_emit_7CEF756E.c:63706:5: error: aggregate value used where an integer was expected
```

## Fixture (verbatim)

`mod_a.zig` (graph filler — cross-module function so the chain is 3+):
```zig
pub fn addOne(x: u32) u32 {
    return x + 1;
}
```

`mod_b.zig` (THE emission site for the dominant `subscripted value` shape — three
functions `copyFieldA/B/C`, each mirroring the self-compile's array field-copy loop
`fb[_i] = src[_i]` inside `emitFieldAssign` / the `fb` locals of `emitInst`):
```zig
const mod_a = @import("mod_a.zig");

pub fn copyFieldA() u32 {
    var fb: []const u8 = "A";          // outer scope: fb is a SLICE
    var out: u32 = 0;
    {
        var fb: [16]u8 = undefined;    // disjoint inner scope: fb is an ARRAY
        var src: [16]u8 = undefined;
        var i: usize = 0;
        while (i < 16) : (i += 1) {
            src[i] = @intCast(u8, i);
        }
        fb = src;                      // array copy → emits fb[_i] = src[_i] loop
        out = fb[0];
    }
    return out + mod_a.addOne(fb.len);
}
// copyFieldB, copyFieldC: identical with "B"/"C" string literals
```

`main.zig` (reproduces the `too few arguments` shape — a `main` with parameters,
mirroring `sf/src/main.zig`'s `pub fn main(argc: u32, argv: [][*]u8)`):
```zig
const std = @import("std");
const mod_a = @import("mod_a.zig");
const mod_b = @import("mod_b.zig");

pub fn main(argc: u32, argv: [][*]u8) void {
    _ = argv;
    var t = mod_b.copyFieldA();
    t = mod_b.copyFieldB();
    t = mod_b.copyFieldC();
    t = mod_a.addOne(t);
    std.io.printInt(@intCast(i32, t + argc));
}
```

Import graph: `main → mod_a`, `main → mod_b → mod_a`. 3 fixture modules + std.
`zig1` accepts the program with **rc=0 and no diagnostics**.

## Why it triggers the class

### Shape 1 — `subscripted value` (dominant; reproduced ×3)

Same-named locals **in disjoint scopes** (legal Zig): an outer `fb: []const u8`
(slice) and an inner `fb: [16]u8` (array) whose `fb = src` triggers the emitter's
element-copy loop path. Mechanism (name-keyed conflation):

1. Lowering emits two `decl_local` LIR insts both carrying the same `name_id` for
   `fb` (one slice-typed temp, one array-typed temp).
2. `emitHoistedDecls` (`c89_emit.zig:2667-2689`) keys the local table by
   `name_id`; the FIRST `fb` decl (the outer slice, block order) wins the name
   slot and its C type, and the duplicate array `fb` decl is dropped
   (`ldup` guard). The emitted C declaration is therefore
   `zT_8F083A69_Slice_zT_0B42B2F8_u fb;` (a struct).
3. The array-copy `.assign` handler (`c89_emit.zig:4288-4307`) checks the *dst
   temp's hoisted type* (array → `is_arr=1`, `arr_len=16`) and writes the copy
   loop `fb[_i] = zT_N[_i];` using `mangleLocalName` for the dst name.
4. gcc sees `fb[_i]` where `fb` is declared as a slice struct →
   `subscripted value is neither array nor pointer nor vector`.

The self-compile's identical lines are in `emitFieldAssign`'s array-copy path
(`c89_emit.zig:290-301`, `fb: [16]u8` at :281) and the `fb` locals in `emitInst`
(:4605/:4680/:4695 array vs the `format_f64` slice `fb` at :5176). The emitted C
decl `zT_8F083A69_Slice_zT_0B42B2F8_u fb;` and copy loop
`fb[_i] = zT_1727[_i];` (c89_emit_7CEF756E.c:59429) are byte-identical in shape.

### Shape 2 — `too few arguments` (reproduced ×1)

`emitMainWrapper` (`c89_emit.zig:2442-2481`) emits the C `main` wrapper calling
the Zig `main` function with **no arguments** (`zF_EA90E208_main();`). If the Zig
`pub fn main` takes parameters (as `sf/src/main.zig` does), the emitted wrapper's
zero-arg call mismatches the emitted signature → gcc
`too few arguments to function 'zF_EA90E208_main'`. Byte-identical to
`main_9472B9CB.c:608:5` (self-compile's `pub fn main(argc, argv)`).

### Shape 3 — `aggregate value` (NOT cleanly reproduced; same B5 `ct` root cause)

The self-compile site `c89_emit_7CEF756E.c:63706` is
`zT_4875 = (unsigned int)zT_3406;` where `zT_3406` is declared
`zT_8F083A69_Slice_zT_0B42B2F8_u zT_3406;` — an int_cast emitted on a
slice-typed temp in the `.call` case of `emitInst` (`ct = ht.type_id` u32 vs the
`ct = getCTypeName(...)` slice at :4960/:5046, B5 in the V audit). In minimal
form, the same-name slice/u32 local pattern instead yields the sibling B5 text
`incompatible types when assigning to type 'Slice' from type 'unsigned int'`
(also produced here, at mod_b:87/197/307 from the outer `fb` store path) — a
different gcc message but the same conflated-name region. Full-graph temp-id
reuse that yields the exact `(unsigned int)<slice>` cast could not be isolated
with valid source; recorded honestly per task instruction.

## RED evidence (measured 2026-08-22, /tmp/fx_subfolder/zig1)

```
$ rm -rf /tmp/r6_194/fx && mkdir -p /tmp/r6_194/fx
$ timeout 120 /tmp/fx_subfolder/zig1 --dump-c89 --output-dir /tmp/r6_194/fx \
    repro/mi_matrix/emission_misc_xmod/main.zig
zig_rc=0            (no diagnostics)
$ cd /tmp/r6_194/fx && gcc -m32 -std=c89 -Wno-long-long -Wno-pointer-sign \
    -I /workspace/znineeight/sf/src/include -c *.c
gcc_rc=1
```

Exact gcc errors for the target class:
```
main_21AF4F8B.c:39:5: error: too few arguments to function 'zF_EA90E208_main'
mod_b_4D0E08C3.c:54:11: error: subscripted value is neither array nor pointer nor vector
mod_b_4D0E08C3.c:164:11: error: subscripted value is neither array nor pointer nor vector
mod_b_4D0E08C3.c:274:11: error: subscripted value is neither array nor pointer nor vector
```

Message text byte-identical to the self-compile lines; columns match exactly
(`:11` for subscripted, `:5` for too-few-args). Emitted C:
```
void zF_EA90E208_main(unsigned int argc, zT_9DFA8D74_Slice_zT_811C9DC5_ argv) {   // main_21AF4F8B.c:2
    ...
int main(void) {                                                                // main_21AF4F8B.c:36
    ...
    zF_EA90E208_main();                                                         // :39 (0 args)
```
```
    zT_8F083A69_Slice_zT_0B42B2F8_u fb;                                         // mod_b_4D0E08C3.c:29
    ...
    while (_i < 16) {
        fb[_i] = zT_8[_i];                                                      // :54 (×3)
        _i++;
    }
```

Co-occurring non-target errors (documented, NOT the misc class): each copyField
also emits `incompatible types when assigning to type 'Slice' from type 'unsigned
char *'` (the B5 name-conflation store path, family of R1) and `'zT_N' undeclared`
(the R2 zT-undeclared class). The misc-class errors are independent of those and
remain RED even if the R2 temp-declaration fix lands.

## Per-shape coverage

- **subscripted value (dominant, ×3): REPRODUCED** — exact text + column 11.
- **too few arguments (×1): REPRODUCED** — exact text + column 5.
- **aggregate value (×1): NOT REPRODUCED cleanly** — same-name slice/u32 pattern
  yields the sibling B5 text `incompatible types when assigning` instead of the
  exact `aggregate value used where an integer was expected`. Shares the B5 `ct`
  root cause (already tracked from the V audit); the exact `(unsigned int)<slice>`
  cast needs full-graph temp-id reuse not isolatable here.

## Probable mechanism (HYPOTHESIS — I may overturn this)

1. **Name-keyed local table** (`emitHoistedDecls`, `c89_emit.zig:2667-2689`):
   `local_name_ids`/`local_types` are keyed by `name_id`, not by temp. Two
   same-named locals in disjoint scopes (legal Zig) collapse to ONE C declaration
   — the first in block order wins its C type. A later scope's different-typed
   local keeps its own hoisted temp type for the array-copy check but reuses the
   first name.
2. **Array-copy `.assign` handler** (`c89_emit.zig:4276-4307`): `is_arr` is
   decided from the dst TEMP's hoisted type (`array_type`), but the emitted dst
   NAME comes from `fl_name_ids`/`mangleLocalName` (the conflated first decl).
   Slice-struct name + array-copy loop → `fb[_i]` → gcc subscripted error.
3. **`emitMainWrapper`** (`c89_emit.zig:2448-2453`): the C wrapper always calls
   `zF_..._main();` with zero args regardless of the Zig `main` signature →
   `too few arguments` when `main` has params.
4. **B5 `ct` region** (`c89_emit.zig:4960/5046` slice `ct` vs :5330 u32 `ct` in
   `emitInst`): an int_cast on a slice-typed temp → `aggregate value used where an
   integer was expected` (self-compile only; sibling `incompatible types` text
   reproduced here).

Fix candidates (untested): declare every distinct decl_local (no name-keyed
dedup — key by temp instead), or have the array-copy path verify the dst name's
declared C type is a C array before emitting the copy loop, or emit the loop with
the dst temp name; emit args in `emitMainWrapper` from the function's params.

## Expected post-fix result

After the fix, `fb[_i]` on the slice decl either disappears (copy loop keyed by a
distinct array name/temp) and `zF_EA90E208_main()` is called with its declared
args. `gcc -c` rc=0.
