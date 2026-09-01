# emission_sibling_payload_xmod — RED fixture for root cause C (sibling-variant payload type conflation)

Task R (2026-08-20). Branch `zig1_start`. Compiler under test: `/tmp/fx_subfolder/zig1`.

## Purpose
Minimal reproducer of **root cause C** from the Task D discovery report: the
payload structs of sibling tagged-union variants are **distinct** types, but
the emission pass conflates them. The D-report mechanism: temps holding the
`ic`/`fc` payload values (loaded from `inst.payload.int_const._0` /
`float_const._0`) are *declared* with the sibling `int_cast` / `float_cast`
payload struct type → assigning two different payload structs to each other
→ gcc class-3 `incompatible types when assigning`. Matches the D-report
evidence `c89_emit_7CEF756E.c:33067: zT_1096 = ic;` (anon_39577 =
anon_39621).

The fixture drives the conflation by giving `getResult` >64 named locals
(`a0..a69`): lowering's `addLocalDecl` has a **64-slot** cap
(`sf/src/lower.zig:629`), so when the count overflows, the switch-arm capture
name (`ic`) is no longer tracked and `maybeDisambiguateCapture`
(`lower.zig:656-677`) stops disambiguating the sibling arms — both
`.int_const` and `.int_cast` bind to the same `ic`, and the payload structs
get conflated. (>64 locals is the smallest verified threshold; n=62
reproduces, n=61 does not.)

## Fixture (verbatim)
```zig
const std = @import("std");

const Inst = union(enum) {
    int_const: struct { value: u64, result: u32 },
    int_cast: struct { value: u32, target: u32, result: u32, is_checked: u8 },
    float_const: struct { value: f64, result: u32 },
    float_cast: struct { value: f64, target: u32, result: u32 },
};

fn getResult(inst: Inst) u32 {
    var acc: u32 = 0;
    var a0: u32 = 0; var a1: u32 = 0; ... (a0..a69, 70 locals)
    switch (inst) {
        .int_const => |ic| acc = ic.result,
        .int_cast => |ic| acc = ic.result,
        .float_const => |fc| acc = fc.result,
        .float_cast => |fc| acc = fc.result,
    }
    return acc + a0;
}
```
(Full source in `main.zig`.)

## RED baseline (measured 2026-08-20, /tmp/fx_subfolder/zig1)
```
$ timeout 120 /tmp/fx_subfolder/zig1 --dump-c89 --output-dir /tmp/rfx main.zig
rc=0
$ cd /tmp/rfx && gcc -m32 -std=c89 -Wno-long-long -Wno-pointer-sign \
    -I /workspace/znineeight/sf/src/include -c *.c
gcc_rc=1
```
Exact gcc errors (class 3, `incompatible types when assigning`):
```
main_4B58C4C8.c:738:14: error: incompatible types when assigning to type 'zT_037C983C_anon_17' from type 'zT_6B7025D5_anon_7'
main_4B58C4C8.c:752:14: error: incompatible types when assigning to type 'zT_8D81EEA8_anon_31' from type 'zT_077EDD1F_anon_23'
```
Emitted C (the conflation signature, mirroring the D report's `zT_1096 = ic`):
```
z_bb_1:  ic = inst.payload.int_const._0;  zT_216 = ic;  ...   // ic declared zT_6B7025D5_anon_7 (int_const payload)
z_bb_2:  zT_218 = inst.payload.int_cast._0;
         zT_219 = ic;      // zT_219 declared zT_037C983C_anon_17 (int_cast payload) = ic (int_const payload) → incompatible
z_bb_3:  fc = inst.payload.float_const._0;  ...
z_bb_4:  zT_225 = fc;      // zT_225 declared zT_8D81EEA8_anon_31 (float_cast payload) = fc (float_const payload) → incompatible
```
`ic` / `fc` are declared `zT_6B7025D5_anon_7` / `zT_077EDD1F_anon_23`
(int_const / float_const payload structs), while `zT_219` / `zT_225` are
declared with the sibling int_cast / float_cast payload structs.

## Root cause pinned
Payload-variant temp typing in `emitHoistedDecls` (`sf/src/c89_emit.zig:2521-3076`);
sibling payload structs in the emitted `zig_special_types.h`
(`int_cast`/`int_const`/`float_cast`/`float_const` payload anon structs);
`addLocalDecl` 64-slot cap and `maybeDisambiguateCapture`
(`sf/src/lower.zig:628-677`) enabling the capture-name collision. Root cause
C of the D report.

## Expected post-fix result
After fixing the payload-variant temp typing so temps holding
`int_const`/`float_const` payload values are declared with their own payload
struct type, gcc `-c` rc=0 and the binary prints `3`.
