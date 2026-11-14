# emission_opt_fptr_wrap_xmod — RED fixture for the optional-fn-ptr wrap gap (R-OPTFPTR)

Task 4.1 (2026-08-24), out-of-scope-residual closeout plan (Phase 4), branch `zig1_start`.
Compiler under test: `/tmp/fx_subfolder/zig1` (current at HEAD `2cbf1fd3`). Build recipe identical
to the other `emission_*_xmod` fixtures: emit with `--dump-c89 --output-dir`, compile emitted C with
`gcc -m32 -std=c89 -Wno-long-long -Wno-pointer-sign -I <repo>/sf/src/include`.

> **R-OPTFPTR VERIFY DIR:** this directory is re-verified by I-OPTFPTR (read-only) then F-OPTFPTR
> (fix). It must remain RED on `incompatible types when assigning to type 'zT_…_Opt_<n>' from type
> 'zT_…_FP_void'` at the `f = zT_1;` and `s.cb = zT_4;` lines. If it ever goes GREEN, the
> optional-wrap-for-fn-ptr-payload emission gap is fixed (reclassify as a control), not a fixture
> defect.

## Purpose

Full-graph (3-module: main/mod_a/mod_b + std) reproducer of the **optional-fn-ptr wrap emission
gap** (A-ANALYZE §6.1, incidental finding #1; plan Phase 4 root): `var f: ?fn () void = foo;`
(probe `pv3`) and struct field `cb: ?fn () void` store (probe `pvo1`) emit a **direct assign** of
the fn-pointer value into the optional struct WITHOUT the `.has_value`/`.value` wrap. gcc rejects
both assigns deterministically: the optional struct (`zT_…_Opt_<n>`) is not assignment-compatible
with the raw fn-pointer type (`zT_…_FP_void {aka 'void (*)(void)'}`).

## Fixture (verbatim)

`mod_a.zig` (fn-pointer source + graph filler — plain fn, no optional):
```zig
pub fn foo() void {}

pub fn addOne(x: i32) i32 {
    return x + 1;
}
```

`mod_b.zig` (THE emission site — both probe shapes: pv3 var-init + pvo1 struct-field store):
```zig
const mod_a = @import("mod_a.zig");

const Cb = struct {
    cb: ?fn () void,
};

pub fn run() i32 {
    var f: ?fn () void = mod_a.foo;
    var s: Cb = undefined;
    s.cb = mod_a.foo;
    var r: i32 = 0;
    if (f != null) {
        r = r + 1;
    }
    if (s.cb != null) {
        r = r + 2;
    }
    return r;
}
```

`main.zig` (graph filler — consumes `run` so it lowers; std sink for a realistic graph):
```zig
const std = @import("std");
const mod_a = @import("mod_a.zig");
const mod_b = @import("mod_b.zig");

pub fn main() void {
    var t = mod_b.run();
    t = mod_a.addOne(t);
    std.io.printInt(t);
}
```

Import graph: `main → mod_a`, `main → mod_b → mod_a`. 3 fixture modules + std.
`zig1` accepts the program with **rc=0** (two `warning[3000]` diagnostics on the fn-ptr→optional
init/assign lines — the frontend notes the type mismatch but proceeds).

## RED evidence (measured 2026-08-24, /tmp/fx_subfolder/zig1 @ 2cbf1fd3)

```
$ rm -rf /tmp/opf && mkdir -p /tmp/opf
$ timeout 60 /tmp/fx_subfolder/zig1 --dump-c89 --output-dir /tmp/opf \
    repro/mi_matrix/emission_opt_fptr_wrap_xmod/main.zig
zig_rc=0            (warnings only: warning[3000] on the two optional-fn-ptr assigns)
$ cd /tmp/opf && gcc -m32 -std=c89 -Wno-long-long -Wno-pointer-sign \
    -I /workspace/znineeight/sf/src/include -c *.c
gcc_rc=1
```

Exact gcc errors (both probe shapes, one error each — the target class, byte-identical to probes
pv3/pvo1 in A-ANALYZE §8):
```
mod_b_1718E5AA.c: In function 'zF_2ACD4ECA_run':
mod_b_1718E5AA.c:24:9: error: incompatible types when assigning to type 'zT_AEE9891C_Opt_30' from type 'zT_08C0D7CE_FP_void' {aka 'void (*)(void)'}
   24 |     f = zT_1;
      |         ^~~~
mod_b_1718E5AA.c:27:12: error: incompatible types when assigning to type 'zT_AEE9891C_Opt_30' from type 'zT_08C0D7CE_FP_void' {aka 'void (*)(void)'}
   27 |     s.cb = zT_4;
      |            ^~~~
```

Emitted C (the bug, both shapes present):
```c
    zT_AEE9891C_Opt_30 f;
    zT_54D9DDB0_Cb s;
    ...
    z_bb_0:
    zT_1 = zF_A9F37ED7_foo;
    f = zT_1;            <- THE BUG (pv3): direct assign of FP_void into Opt_30, no .has_value/.value wrap
    s = zT_3;
    zT_4 = zF_A9F37ED7_foo;
    s.cb = zT_4;         <- THE BUG (pvo1): same direct assign into the optional struct field
    ...
    zT_8 = f.has_value;      <- the optional is OBSERVED afterwards, so the missing wrap matters
    if (zT_8) goto z_bb_1; else goto z_bb_2;
    ...
    zT_11 = s.cb;
    zT_12 = zT_11.has_value;
```

## GREEN control (pins the class to the fn-ptr payload)

The SAME assign shape with a non-fn-ptr payload compiles GREEN — the optional wrap IS emitted for
`?i32` (measured 2026-08-24):
```zig
const std = @import("std");

pub fn main() void {
    var g: ?i32 = 5;
    var r: i32 = 0;
    if (g != null) { r = r + 1; }
    std.io.printInt(r);
}
```
`zig1 --dump-c89` rc=0; `gcc -c` rc=0. Emitted C takes the wrapped path:
```c
    zT_1 = 5;
    zT_2 = (int)zT_1;
    zT_3.has_value = 1;
    zT_3.value = zT_2;
    g = zT_3;
```
Compare the fn-ptr case: `f = zT_1;` with no `has_value`/`value` materialization. Same optional
init path, only the payload type differs → the gap is fn-ptr-specific.

## Root-cause pin

The optional-wrap materialization in the var-init / field-store assign path (`sf/src/lower.zig`
optional coercion / coerceOptional; emission in `sf/src/c89_emit.zig`) matches on payload type and
emits the `.has_value`/`.value` wrap for scalar/pointer payloads but takes the DIRECT-assign path
for fn-pointer payloads (`zT_…_FP_*`), dropping the wrap entirely. Since `Opt_N` and `FP_void` are
distinct C struct/function-pointer types, gcc rejects the direct assign (C89 6.5.16). I-OPTFPTR
(4.2) pins the exact locus; the class is: **optional-wrap missing for fn-pointer payloads in the
assign path**.

## Expected post-fix result

After F-OPTFPTR, the `?fn()void` var-init and struct-field store emit the wrap like the `?i32`
control (`.has_value` set + `.value`/payload assign into the optional struct, or equivalent):
`f = zT_1;` becomes `f.has_value = 1; f.value = zT_1;` (and likewise `s.cb`). `gcc -c` rc=0 and
the binary prints `4` (`r = 1 + 3` after `addOne`). This fixture flips to a GREEN control.
