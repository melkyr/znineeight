# emission_zT_undeclared_xmod — RED fixture for the 194-closeout zT-undeclared class (R2, 68 errors)

Task R2 (2026-08-22). Branch `zig1_start`. Compiler under test: `/tmp/fx_subfolder/zig1`
(HEAD b5e3b7eb; R1 did not rebuild it). Build recipe identical to R1: emit with
`--dump-c89`, compile emitted C with `gcc -m32 -std=c89`.

## Purpose

Full-graph (3-module) reproducer of the self-compile residual class
**`'zT_<n>' undeclared (first use in this function); did you mean 'zT_<m>'?`**
(68 errors — c89_emit 38, type_registry 17, symbol_registrator 5, plus
import_resolver/main/module_registry/semantic_analyzer).

The mechanism under test is the **VOID-effective-type hoisted-temp decl-skip**:
`emitHoistedDecls` (`sf/src/c89_emit.zig:3148`) skips the C declaration of any
hoisted temp whose *effective* type is `TYPE_VOID` (`eff_type != 1` guard). A
field-access expression that the semantic analyzer resolves to `VOID` lowers
(`sf/src/lower.zig:2611-2612`) to a **bare VOID temp with no `load_field`
emitted**, so the temp is neither declared nor assigned — but it is still
*referenced* (as a call-argument copy) → gcc `'zT_<n>' undeclared`.

Self-compile evidence (e.g. `c89_emit_7CEF756E.c:61705:15`):
`zT_3331 = zT_3336;` — the `getTempTypeInfo(emitter, b.result, b.lhs, b.rhs,
&wty, &wsg)` arg copy, where `zT_3336/3337/3338` (the `b.result/b.lhs/b.rhs`
reads) are hoisted with `HT:zT_3336(1->1)w0` (type VOID, never written by the
inference pass) and are never declared.

## Fixture (verbatim)

`mod_a.zig` (the LirInst-like tagged union + factory):
```zig
pub const TypeId = u32;

pub const Inst = union(enum) {
    binary: struct { op: u8, lhs: u32, rhs: u32, result: u32 },
    call: struct { callee: u32, args_start: u32, args_count: u32, result: u32 },
    load_field: struct { base: u32, field_id: u32, result: u32, name_id: u32 },
    jump: u32,
    ret: u32,
    label: u32,
    ret_void: void,
    none,
};

pub fn makeJump(target: u32) Inst {
    return .{ .jump = target };
}
```
`mod_b.zig` (the emission site — scalar-payload capture field reads passed to a
helper, mirroring `c89_emit.zig:4945`):
```zig
const std = @import("std");
const mod_a = @import("mod_a.zig");
const Inst = mod_a.Inst;

fn resolveTempName(emitter: *Emitter, t: u32) u32 {
    _ = emitter;
    return t;
}

fn getTypeInfo(emitter: *Emitter, temp_id: u32, fb1: u32, fb2: u32, out_type: *u32, out_signed: *u8) void {
    _ = emitter;
    out_type.* = temp_id + fb1 + fb2;
    out_signed.* = 0;
}

pub const Emitter = struct {
    x: u32,
};

pub fn emitInst(emitter: *Emitter, inst: Inst) u32 {
    var acc: u32 = 0;
    switch (inst) {
        .jump => |t| {
            var wty: u32 = 0;
            var wsg: u8 = 0;
            getTypeInfo(emitter, t.result, t.target, 0, &wty, &wsg);
            acc = wty;
        },
        else => {},
    }
    return acc;
}
```
`main.zig`:
```zig
const std = @import("std");
const mod_a = @import("mod_a.zig");
const mod_b = @import("mod_b.zig");

pub fn main() void {
    var em = mod_b.Emitter{ .x = 0 };
    var i = mod_a.makeJump(5);
    std.io.printInt(@intCast(i32, mod_b.emitInst(&em, i)));
}
```
Import graph: `main → mod_a`, `main → mod_b → mod_a`. 3 modules + std.

## RED baseline (measured 2026-08-22, /tmp/fx_subfolder/zig1 @ b5e3b7eb)

```
$ mkdir -p /tmp/r2_194
$ timeout 120 /tmp/fx_subfolder/zig1 --dump-c89 --output-dir /tmp/r2_194 \
    repro/mi_matrix/emission_zT_undeclared_xmod/main.zig
rc=0
$ cd /tmp/r2_194 && gcc -m32 -std=c89 -Wno-long-long -Wno-pointer-sign \
    -I /workspace/znineeight/sf/src/include -c *.c
gcc_rc=1
```
Exact gcc errors (class `zT_<n> undeclared`, 2 hits):
```
mod_b_7760E57D.c:77:13: error: 'zT_19' undeclared (first use in this function); did you mean 'zT_18'?
mod_b_7760E57D.c:78:13: error: 'zT_20' undeclared (first use in this function); did you mean 'zT_24'?
```
Byte-for-byte identical to self-compile lines (e.g.
`c89_emit_7CEF756E.c:61705:15: error: 'zT_3336' undeclared (first use in this
function); did you mean 'zT_7336'?`): same message, same `did you mean` hint,
same format.

Emitting C — the referenced-but-never-declared temps:
```
z_bb_1:
t = inst.payload.jump._0;            // capture t (u32) from a scalar-payload variant
...
zT_13 = emitter;
zT_14 = zT_19;                       // arg #2 = t.result  → zT_19: referenced, NEVER declared
zT_15 = zT_20;                       // arg #3 = t.target  → zT_20: referenced, NEVER declared
zT_16 = zT_22;                       // arg #4 = 0
zT_17 = &wty;                        // arg #5
zT_18 = &wsg;                        // arg #6
zF_8C06BD7B_getTypeInfo(zT_13, zT_14, zT_15, zT_16, zT_17, zT_18);
```
`zT_19`/`zT_20` appear nowhere else: no declaration line and no load.
Marker run (`--markers`) confirms `HTT:t19Y1` / `HTT:t20Y1` — hoisted with type
1 (VOID). This mirrors the self-compile `HT:zT_3336(1->1)w0:zT_3336:void`.

## Probable mechanism (HYPOTHESIS — I may overturn this)

1. **Semantic resolution** (`semantic_analyzer.zig`): a field access on a value
   whose base type is *not* struct/union/tagged-union/slice/enum falls to the
   `else` arm and resolves to `TYPE_VOID` (`semantic_analyzer.zig:595-615`,
   `:634-637`). In the self-compile the base is a switch-capture payload that the
   analyzer has typed as a *scalar* (the emitInst `.binary` capture `b` — its
   payload field reads resolve to VOID; the first reads in the same arm resolve
   fine, the call-arg reads do not — the exact re-resolution state is the open
   question). In the fixture the base is a genuinely scalar-payload capture
   (`jump: u32`), which produces the same VOID resolution without relying on the
   analyzer bug.
2. **Lowering** (`lower.zig:2479, 2611-2612`): `fa_box[0] == VOID` →
   `nextTemp(TYPE_VOID)` creates the temp; the struct/union field lookup branch
   (`lower.zig:2480-2610`) never matches a scalar base, so the fall-through
   `return tid` emits **no `load_field`**.
3. **Emission** (`c89_emit.zig:3148`): the hoisted-temp declaration loop skips
   the temp because its effective type is `TYPE_VOID` (`eff_type != 1`), and the
   `.load_field` arm's `lf_res_void` guard (`c89_emit.zig:4581`) is moot (no
   load_field exists). The temp is still referenced by the call-argument
   `assign` (`c89_emit.zig:4441-4448`) → `zT_14 = zT_19;` → gcc
   `'zT_19' undeclared`.

Root-cause framing for the 68-error class: the emitter assumes every *hoisted*
temp either is written by the inference pass or has a concrete type; field
accesses that resolve to VOID slip through both the inference pass (which only
re-uses the hoisted type) and the decl-skip guard. Fix candidates (untested):
have the decl loop emit a safe scalar (`int`/`u32`) declaration for VOID
effective types instead of skipping; or make the semantic analyzer return the
field's declared type / reject scalar field access with a proper diagnostic
instead of VOID; or make lower.zig emit a real `load_field` (or a zero-value
store) for VOID field-access fall-throughs.

## Expected post-fix result

After the fix, `zT_19`/`zT_20` either get a C declaration or the field access
is rejected/handled at the front end; `gcc -c` rc=0 and the binary prints the
getTypeInfo result.
