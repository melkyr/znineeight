# emission_zT_undeclared_xmod — RED fixture for the 194-closeout zT-undeclared class (R2, 68 errors)

Task R2 (2026-08-22). Branch `zig1_start`. Compiler under test: `/tmp/fx_subfolder/zig1`
(HEAD b5e3b7eb; R1 did not rebuild it). Build recipe identical to R1: emit with
`--dump-c89`, compile emitted C with `gcc -m32 -std=c89`.

## Purpose

Full-graph (3-module) reproducer of the self-compile residual class
**`'zT_<n>' undeclared (first use in this function); did you mean 'zT_<m>'?`**
(68 errors — c89_emit 38, type_registry 17, symbol_registrator 5, plus
import_resolver/main/module_registry/semantic_analyzer).

## REWORK (2026-08-22, review finding)

The original fixture used `t.result`/`t.target` on a scalar capture (`jump: u32`)
— spec-INVALID Zig (field access on a scalar). A spec-correct compiler would
reject it at the front end, so a "reject scalar field access" fix would GREEN
the fixture while the 68-error emission class remains. This fixture is reworked
to a **spec-valid** trigger that mirrors the self-compile's real pattern: a
**struct-typed payload capture** whose field reads are valid Zig, but whose
effective type is lost to VOID in the call-arg/load path via a **same-function
scalar shadowing `var b`**.

## Mechanism under test (HYPOTHESIS)

The hoisted-decl emitter (`sf/src/c89_emit.zig:3148`) skips the C declaration of
any hoisted temp whose *effective* type is `TYPE_VOID` (`eff_type != 1` guard).
The temp is still *referenced* (as a call-argument copy) → gcc
`'zT_<n>' undeclared`.

In the self-compile the base is a struct capture (`.binary => |b|`); the
call-arg reads `b.result/b.lhs/b.rhs` resolve to VOID because the analyzer's
LIFO local-decl stack re-resolves the ident `b` to a **scalar** u8: the same
function's `.string_const` arm declares `var b = str[si]` (u8), registered on
top of the struct capture, shadowing it for later reads (marker evidence:
`D7:n3053 → L:t8`). The first reads in the arm resolve fine (struct); the later
call-arg reads resolve scalar → `fa_box[0] == VOID` → bare VOID temp with no
`load_field` (`sf/src/lower.zig:2611-2612`) → decl skipped, reference emitted.

## Fixture (verbatim)

`mod_a.zig` (LirInst-like tagged union + factories):
```zig
pub const TypeId = u32;

pub const Inst = union(enum) {
    binary: struct { op: u8, lhs: u32, rhs: u32, result: u32 },
    call: struct { callee: u32, args_start: u32, args_count: u32, result: u32 },
    load_field: struct { base: u32, field_id: u32, result: u32, name_id: u32 },
    branch: struct { cond: u32, then_bb: u32, else_bb: u32 },
    string_const: struct { string_id: u32, result: u32 },
    jump: u32,
    ret: u32,
    label: u32,
    ret_void: void,
    none,
};

pub fn makeJump(target: u32) Inst {
    return .{ .jump = target };
}

pub fn makeBinary(op: u8, lhs: u32, rhs: u32, result: u32) Inst {
    return .{ .binary = .{ .op = op, .lhs = lhs, .rhs = rhs, .result = result } };
}
```
`mod_b.zig` (the emission site — struct-capture field reads passed to a helper,
mirroring `c89_emit.zig:4945`, plus a shadowing `var b`):
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
        .binary => |b| {
            var result = resolveTempName(emitter, b.result);
            var lhs = resolveTempName(emitter, b.lhs);
            var rhs = resolveTempName(emitter, b.rhs);
            if (b.op >= 16) {
                var wty: u32 = 0;
                var wsg: u8 = 0;
                getTypeInfo(emitter, b.result, b.lhs, b.rhs, &wty, &wsg);
                acc = result + lhs + rhs + wty;
            }
        },
        .string_const => |sc| {
            var str: []const u8 = "hi";
            var si: usize = 0;
            while (si < str.len) : (si += 1) {
                var b = str[si];
                acc = acc + b;
            }
            acc = acc + sc.result;
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
    var i = mod_a.makeBinary(20, 1, 2, 3);
    std.io.printInt(@intCast(i32, mod_b.emitInst(&em, i)));
}
```
Import graph: `main → mod_a`, `main → mod_b → mod_a`. 3 modules + std.

All field accesses (`b.result/b.lhs/b.rhs/b.op`, `sc.result`, `b` as u8 loop var)
are valid Zig; `zig1` accepts the program with rc=0 and **no diagnostics**.

## RED evidence (measured 2026-08-22, /tmp/fx_subfolder/zig1 @ b5e3b7eb)

```
$ mkdir -p /tmp/r2_194/verify3
$ timeout 120 /tmp/fx_subfolder/zig1 --dump-c89 --output-dir /tmp/r2_194/verify3 \
    repro/mi_matrix/emission_zT_undeclared_xmod/main.zig
zig_rc=0            (no diagnostics)
$ cd /tmp/r2_194/verify3 && gcc -m32 -std=c89 -Wno-long-long -Wno-pointer-sign \
    -I /workspace/znineeight/sf/src/include -c *.c
gcc_rc=1
```
Exact gcc errors (class `zT_<n> undeclared`, 3 hits):
```
mod_b_BDDAF9B0.c:169:13: error: 'zT_37' undeclared (first use in this function); did you mean 'zT_57'?
mod_b_BDDAF9B0.c:170:13: error: 'zT_38' undeclared (first use in this function); did you mean 'zT_58'?
mod_b_BDDAF9B0.c:171:13: error: 'zT_39' undeclared (first use in this function); did you mean 'zT_59'?
```
Byte-for-byte identical to self-compile lines (e.g.
`c89_emit_7CEF756E.c:61705:15: error: 'zT_3336' undeclared (first use in this
function); did you mean 'zT_7336'?`): same message, same `did you mean` hint,
same format.

Emitting C — the referenced-but-never-declared temps (the `getTypeInfo` call args):
```
z_bb_1:
b = inst.payload.binary._0;        // struct capture
...
zT_10 = b.result;                  // first read — load_field, temp DECLARED
zT_15 = b.lhs;                     // first read — DECLARED
zT_20 = b.rhs;                     // first read — DECLARED
zT_22 = b.op;                      // condition read — DECLARED
zT_24 = zT_22 >= zT_23;            // 16
...
zT_31 = emitter;                   // arg #1
zT_32 = zT_37;                     // arg #2 = b.result  → zT_37: referenced, NEVER declared
zT_33 = zT_38;                     // arg #3 = b.lhs     → zT_38: referenced, NEVER declared
zT_34 = zT_39;                     // arg #4 = b.rhs     → zT_39: referenced, NEVER declared
zT_40 = &wty;                      // arg #5
zT_41 = &wsg;                      // arg #6
zF_8C06BD7B_getTypeInfo(zT_31, zT_32, zT_33, zT_34, zT_35, zT_36);
```
`zT_37/38/39` appear nowhere else: no declaration line and no load.

Marker run (`--markers`) — exact mirror of the self-compile class:
```
HT:zT_37(1->1)w0:zT_37:void
HT:zT_38(1->1)w0:zT_38:void
HT:zT_39(1->1)w0:zT_39:void
zT_37=UNWRITTEN INT:tl5
```
vs self-compile `HT:zT_3336(1->1)w0:zT_3336:void` — hoisted type 1 (VOID),
never written by the inference pass. The capture `b` (name 55) sequence:
`SCFE:t30` (struct) → first reads `D7:t30` → `VD:N55` (`var b`, u8) registered →
later reads `D7:t8` (scalar) → field access on scalar → VOID.

## Probable mechanism (HYPOTHESIS — I may overturn this)

1. **Semantic resolution** (`semantic_analyzer.zig`): the switch-arm capture `b`
   is registered on a flat LIFO `local_decl` stack (`semantic_analyzer.zig:1306`).
   In the same function a *later* statement registers another local named `b`
   with a scalar type (`var b = str[si]`, u8). Local-decl entries are never
   popped, so subsequent ident resolutions of `b` return the **scalar** u8
   (`D7:n55 → L:t8`), shadowing the struct capture.
2. **Field access** (`semantic_analyzer.zig:443+`): base type is now scalar →
   `semanticAnalyzerResolveFieldAccess` falls to the final `else`/field-not-found
   arm and resolves to `TYPE_VOID`.
3. **Lowering** (`lower.zig:2479, 2611-2612`): `fa_box[0] == VOID` →
   `nextTemp(TYPE_VOID)` creates the temp; the struct/union field branch
   (`lower.zig:2480-2610`) never matches a scalar base, so the fall-through
   `return tid` emits **no `load_field`**.
4. **Emission** (`c89_emit.zig:3148`): the hoisted-temp declaration loop skips
   the temp because its effective type is `TYPE_VOID` (`eff_type != 1`). The
   temp is still referenced by the call-argument `assign` copy
   (`c89_emit.zig:4441-4448`) → `zT_32 = zT_37;` → gcc `'zT_37' undeclared`.

Root-cause framing for the 68-error class: the emitter assumes every *hoisted*
temp either is written by the inference pass or has a concrete type. An ident
that resolves to a shadowing scalar makes a field-access temp VOID; such temps
slip through both the inference pass (which only re-uses the hoisted type) and
the decl-skip guard. Fix candidates (untested): have the decl loop emit a safe
scalar (`int`/`u32`) declaration for VOID effective types instead of skipping;
or make the semantic analyzer's ident resolution scope-correct so a later local
does not shadow an outer capture; or make lower.zig emit a real `load_field`
(or a zero-value store) for VOID field-access fall-throughs.

## Expected post-fix result

After the fix, `zT_37/38/39` either get a C declaration or resolve to the struct
field type (u32); `gcc -c` rc=0 and the binary prints the getTypeInfo result.
