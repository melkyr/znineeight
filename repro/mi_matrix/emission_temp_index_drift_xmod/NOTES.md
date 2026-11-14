# emission_temp_index_drift_xmod — RED fixture for the R2/R1-closeout zT temp-index drift class (residual 11)

Task R-R2 (2026-08-24). Branch `zig1_start`. Compiler under test: `/tmp/fx_subfolder/zig1`
(std reinstalled in `/tmp/fx_subfolder/lib`). Build recipe identical to R1/R2: emit with
`--dump-c89`, compile emitted C with `gcc -m32 -std=c89 -Wno-long-long -Wno-pointer-sign`.

## Purpose

Full-graph (3-module) reproducer of the self-compile residual class
**`'zT_<n>' undeclared (first use in this function); did you mean 'zT_<m>'?`** (m = n + offset),
the "temp-index drift" sub-class. The plan targets 12 residual self-compile gcc errors
(R2 `zT_<n>` undeclared ×11 + R1 Opt_10 ×1); this fixture reproduces the R2 class's dominant
shape — the c89_emit ×6 group, all of which are `zT_N = (unsigned int)zT_{N-1}`-style references
to a **comptime array-length temp that is never declared**.

This is DISTINCT from the already-closed void-temp/E fixtures (`emission_void_temp_xmod`,
`emission_void_temp_scale_xmod`, …): those are GREEN on the current compiler (verified
2026-08-24), while this array-`.len` trigger is still RED. Same gcc error class, different
producer (comptime array `.len` in an `@intCast` vs. call-arg union-literal / load_field payload).

## Fixture (verbatim)

`mod_a.zig` (SwitchCase + Inst tagged union + factories):
```zig
pub const SwitchCase = struct {
    value: u32,
    target_bb: u32,
};

pub const Inst = union(enum) {
    switch_br: struct { cond: u32, cases_start: u32, cases_count: u32, else_bb: u32 },
    ret: u32,
    none,
};

pub fn makeSwitchBr(cond: u32, cases_count: u32, else_bb: u32) Inst {
    return .{ .switch_br = .{ .cond = cond, .cases_start = 0, .cases_count = cases_count, .else_bb = else_bb } };
}

pub fn makeCase(value: u32, target_bb: u32) SwitchCase {
    return SwitchCase{ .value = value, .target_bb = target_bb };
}
```
`mod_b.zig` (the emission site — mirrors `c89_emit.zig:5573-5594`, the `.switch_br` arm's
`@intCast(u32, <array>.len)` buffer-slicing):
```zig
const std = @import("std");
const mod_a = @import("mod_a.zig");
const Inst = mod_a.Inst;

pub const Emitter = struct {
    buf: [128]u8,
    pos: usize,
};

fn emitCase(emitter: *Emitter, c: mod_a.SwitchCase) void {
    var val_buf: [20]u8 = undefined;
    var val_len: usize = 3;
    var val_start = @intCast(usize, @intCast(u32, val_buf.len) - @intCast(u32, 1) - val_len);
    var val_end = @intCast(usize, @intCast(u32, val_buf.len) - @intCast(u32, 1));
    var i: usize = val_start;
    while (i < val_end) : (i += 1) {
        if (emitter.pos < 128) {
            emitter.buf[emitter.pos] = val_buf[i];
            emitter.pos += 1;
        }
    }
    var bb_buf: [10]u8 = undefined;
    var bb_len: usize = 2;
    var bb_start = @intCast(usize, @intCast(u32, bb_buf.len) - @intCast(u32, 1) - bb_len);
    var bb_end = @intCast(usize, @intCast(u32, bb_buf.len) - @intCast(u32, 1));
    var j: usize = bb_start;
    while (j < bb_end) : (j += 1) {
        if (emitter.pos < 128) {
            emitter.buf[emitter.pos] = bb_buf[j];
            emitter.pos += 1;
        }
    }
}

pub fn emitInst(emitter: *Emitter, inst: Inst, cases: []mod_a.SwitchCase) void {
    switch (inst) {
        .switch_br => |s| {
            var i: u32 = s.cases_start;
            var end = s.cases_start + s.cases_count;
            while (i < end) : (i += 1) {
                emitCase(emitter, cases[@intCast(usize, i)]);
            }
            var def_buf: [10]u8 = undefined;
            var def_len: usize = 2;
            var def_start = @intCast(usize, @intCast(u32, def_buf.len) - @intCast(u32, 1) - def_len);
            var def_end = @intCast(usize, @intCast(u32, def_buf.len) - @intCast(u32, 1));
            var k: usize = def_start;
            while (k < def_end) : (k += 1) {
                if (emitter.pos < 128) {
                    emitter.buf[emitter.pos] = def_buf[k];
                    emitter.pos += 1;
                }
            }
        },
        else => {},
    }
}
```
`main.zig`:
```zig
const std = @import("std");
const mod_a = @import("mod_a.zig");
const mod_b = @import("mod_b.zig");

pub fn main() void {
    var em = mod_b.Emitter{ .buf = undefined, .pos = 0 };
    var cases: [2]mod_a.SwitchCase = undefined;
    cases[0] = mod_a.makeCase(1, 3);
    cases[1] = mod_a.makeCase(2, 4);
    var inst = mod_a.makeSwitchBr(0, 2, 5);
    mod_b.emitInst(&em, inst, cases[0..]);
    std.io.printInt(@intCast(i32, @intCast(u32, em.pos)));
}
```
Import graph: `main → mod_a`, `main → mod_b → mod_a`. 3 modules + std. All expressions are
dialect-valid Zig; `zig1` accepts the program with rc=0 and **no diagnostics**.

## RED evidence (measured 2026-08-24, /tmp/fx_subfolder/zig1)

```
$ cd repro/mi_matrix/emission_temp_index_drift_xmod
$ mkdir -p /tmp/rr2_verify
$ timeout 120 /tmp/fx_subfolder/zig1 --dump-c89 --output-dir /tmp/rr2_verify main.zig
zig_rc=0            (no diagnostics)
$ cd /tmp/rr2_verify && gcc -m32 -std=c89 -Wno-long-long -Wno-pointer-sign \
    -I /workspace/znineeight/sf/src/include -c *.c
gcc_rc=1
```
Exact gcc errors (class `zT_<n> undeclared`, 6 hits — same count as the c89_emit residual group):
```
mod_b_1718E5AA.c:94:26: error: 'zT_8' undeclared (first use in this function); did you mean 'zT_58'?
mod_b_1718E5AA.c:102:27: error: 'zT_15' undeclared (first use in this function); did you mean 'zT_65'?
mod_b_1718E5AA.c:141:27: error: 'zT_40' undeclared (first use in this function); did you mean 'zT_60'?
mod_b_1718E5AA.c:149:27: error: 'zT_47' undeclared (first use in this function); did you mean 'zT_57'?
mod_b_1718E5AA.c:321:27: error: 'zT_25' undeclared (first use in this function); did you mean 'zT_45'?
mod_b_1718E5AA.c:329:27: error: 'zT_32' undeclared (first use in this function); did you mean 'zT_42'?
```
Byte-identical class to the self-compile residual, e.g.
`c89_emit_7CEF756E.c:65076:29: error: 'zT_5666' undeclared (first use in this function); did you mean 'zT_7666'?`
— same message, same `did you mean` hint, same format.

Emitting C — the referenced-but-never-declared temps (the `@intCast(u32, <array>.len)` comptime
values `val_buf.len`/`bb_buf.len`/`def_buf.len`):
```
    zT_5 = 3;                    // val_len
    zT_6 = (unsigned int)zT_5;
    val_len = zT_6;
    zT_9 = (unsigned int)zT_8;   // <-- zT_8 = val_buf.len (comptime 20): referenced, NEVER declared
    zT_10 = 1;
    zT_11 = zT_9 - zT_10;
    zT_12 = zT_11 - val_len;
```
`zT_8`, `zT_15`, `zT_40`, `zT_47`, `zT_25`, `zT_32` appear in the referencing function's body
but have NO declaration in its hoisted-temp block (the block skips them; the numbering gap is
visible in the emitted decl list).

Marker run (`--markers`) — the referenced temps' hoisted type is VOID:
```
HT:zT_8(1->1)w0:zT_8:void
HT:zT_15(1->1)w0:zT_15:void
HT:zT_25(1->1)w0:zT_25:void
HT:zT_32(1->1)w0:zT_32:void
HT:zT_40(1->1)w0:zT_40:void
HT:zT_47(1->1)w0:zT_47:void
```
(hoisted type 1 = `TYPE_VOID`, never written by the inference pass) — the same
`HT:zT_<n>(1->1)w0:zT_<n>:void` signature as the residual class (compare
`emission_zT_undeclared_xmod`'s `HT:zT_37(1->1)w0:zT_37:void`).

## Root-cause hypothesis (temp-index drift — evidenced by the emitted C)

The comptime field access `<array>.len` on an **array-typed** value resolves to `TYPE_VOID` in
the semantic analyzer: `semanticAnalyzerResolveFieldAccess` handles `.len` only for
**slice** bases (`sf/src/semantic_analyzer.zig:584-592`); an array base falls through to the
final `else` and `resolvedTypeTableSet(…, TYPE_VOID)` (`semantic_analyzer.zig:649`). In
lowering, the field-access path (`sf/src/lower.zig:2568-2701`) allocates `nextTemp(fa_box[0])`
with that VOID resolved type, and since the base kind is `array_type` (not slice/struct/union),
no branch emits a `load_field`/`int_const` — the temp is returned **never-written**.
`@intCast(u32, <that temp>)` still emits `zT_N = (unsigned int)zT_{N-1}`, referencing it.

In the hoisted-decl emitter (`sf/src/c89_emit.zig:3158`) the temp's effective type is `TYPE_VOID`
(`eff_type != 1` guard), so its C declaration is **skipped** — but the reference remains →
gcc `'zT_<n>' undeclared … did you mean 'zT_<m>'?` (m = n + offset: gcc's nearest-declared-name
hint). The index drift is the gap between the referenced temp id (allocated, hoisted VOID) and
the declaration range (emitted for the non-VOID temps around it).

This is the same emission defect family as the void-temp class (decl-skip on VOID-effective
type), but the **trigger is distinct and still live**: comptime array `.len` materialized inside
an `@intCast`, matching the c89_emit residual's `.switch_br` arm (`c89_emit.zig:5573-5594`,
`var val_start = @intCast(usize, @intCast(u32, val_buf.len) - @intCast(u32, 1) - val_len);`).
The closed void-temp fixtures (call-arg union literals, load_field payload) are GREEN today;
this array-`.len` producer is NOT covered by those fixes.

## Expected post-fix result

After a fix (either give the comptime array-`.len` field access its real `usize` type in
`semanticAnalyzerResolveFieldAccess`/lowering, or emit a C declaration for VOID-effective temps
instead of skipping), `zT_8/zT_15/zT_40/zT_47/zT_25/zT_32` either get declared or resolve to
`usize`; `gcc -c` rc=0 and the binary prints the emitter byte count.
