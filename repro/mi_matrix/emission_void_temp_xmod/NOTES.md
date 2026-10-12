# emission_void_temp_xmod — RED fixture for root cause E (temp type-inference leaves temps void/undeclared)

Task R (2026-08-20). Branch `zig1_start`. Compiler under test: `/tmp/fx_subfolder/zig1`.

## Purpose
Minimal reproducer of **root cause E** from the Task D discovery report:
`emitHoistedDecls` (`sf/src/c89_emit.zig:2521-3076`) runs a type-inference
pass (`written_type`/`written_flag`, `:2617-2968`) over the LIR and then
declares temps in a second pass (`:3021-3075`). The declaration loop **skips**
any temp whose effective type is `void` (`eff_type != 1` guard at `:3061`).
When the inference pass fails to propagate a concrete type to a temp (leaving
it void/undefined), the temp is omitted from the declaration block but is
still referenced in the emitted instruction stream → gcc class-1b
`'zT_<n>' undeclared`. Matches the D-report evidence
`c89_emit_7CEF756E.c:34369: zT_1159 = (unsigned int)zT_1158;` (referenced in
`emitHoistedDecls`, never declared there).

The trigger is a tagged-union payload capture in an `if` expression
(`if (i.a) |v| ... v.x`): the `v.x` load_field result temp is hoisted but the
type-inference pass never assigns it a concrete type, so its declaration is
skipped while the `*wty = zT_6;` statement still references it.

## Fixture (verbatim)
```zig
const std = @import("std");

const Inner = union(enum) {
    a: struct { x: u32 },
    b: struct { y: u32 },
};

fn emitInst(i: Inner, wty: *u32) void {
    if (i.a) |v| {
        wty.* = v.x;
    }
}

pub fn main() void {
    var inst = Inner{ .a = .{ .x = 7 } };
    var w: u32 = 0;
    emitInst(inst, &w);
    std.io.printInt(@intCast(i32, w));
}
```

## RED baseline (measured 2026-08-20, /tmp/fx_subfolder/zig1)
```
$ timeout 120 /tmp/fx_subfolder/zig1 --dump-c89 --output-dir /tmp/rfx main.zig
rc=0
$ cd /tmp/rfx && gcc -m32 -std=c89 -Wno-long-long -Wno-pointer-sign \
    -I /workspace/znineeight/sf/src/include -c *.c
gcc_rc=1
```
Exact gcc error (class 1b, `zT_<n> undeclared`):
```
main_FC3C0B8E.c:15:12: error: 'zT_6' undeclared (first use in this function); did you mean 'zT_5'?
```
Emitted C: `zT_6` is referenced inside `zF_2BFFB972_emitInst` but **never
declared in that function's hoisted-temp block**:
```
/* emitInst */
void zF_2BFFB972_emitInst(zT_7E9B6EC7_Inner i, unsigned int* wty) {
    zT_7E9B6EC7_Inner zT_2;
    zT_7E9B6EC7_Inner zT_3;
    unsigned int zT_4;
    zT_7E9B6EC7_Inner zT_5;
    zT_7E9B6EC7_Inner v;              // zT_6 missing from the declaration block
    ...
    z_bb_1:
    v = zT_3;
    *wty = zT_6;                      // ← referenced, never declared
    ...
```
(`zT_6` appears as a declared temp only in `main`'s block, which is a
different function — the temp numbering collision that also confuses gcc's
"did you mean 'zT_5'?" hint.)

## Root cause pinned
`sf/src/c89_emit.zig:2521-3076`, specifically the void-skip guard `:3061`
and the type-inference pass `:2617-2968` (a load_field result temp on an
`if`-capture payload is left without a concrete type). Root cause E of the D
report.

## Expected post-fix result
After fixing the type-inference pass so the `v.x` load_field result temp gets
its concrete type (u32), `zT_6` is declared in `emitInst`; gcc `-c` rc=0 and
the binary prints `7`.
