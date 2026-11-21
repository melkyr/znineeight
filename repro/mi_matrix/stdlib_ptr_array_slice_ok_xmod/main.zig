// stdlib_ptr_array_slice_ok_xmod — FX5 pointer / `*[N]T` slice siblings
// positive runtime fixture (Volume II fix group FX5).
//
// DEFECT (before FX5): `*[N]T[a..b]` with `a > 0` emitted `pa + a`, scaling
// the offset by the whole array (`pa[1..2]` read garbage); the open ends
// `pa[1..]`/`pa[0..]` ICEd `error[3043]`; `pa.*[i]` materialised the
// dereferenced array (`zT = *pa; zT[i]`) and gcc rejected the C
// ("assignment to expression with array type").
//
// FIX: a `*[N]T` base is cast to its element many-pointer before the offset
// (`(T*)pa + start`), the omitted end is the array length N, and `pa.*[i]`
// lowers the POINTER (`(*pa)[i]`). `*[N]T` ranges keep the Z98 slice `[]T`;
// an open-ended many-item-pointer range (`mp[s..]`, FX5 fix round 1) is
// accepted as `[*]T` — the pointer offset by `start`, Zig 0.15.2 parity.
//
// Contract: stdout is byte-identical to the Zig-0.15.2 `std.debug.print`
// twin (comparison only; per row), rc 0, byte-exact 3x. Every observation is
// `@panic`-guarded.
const std = @import("std");
const helper = @import("helper.zig");

const Holder = struct { arr: [5]i32 };

fn sum(s: []i32) i32 {
    var t: i32 = 0;
    var i: usize = 0;
    while (i < s.len) {
        t += s[i];
        i += 1;
    }
    return t;
}

pub fn main() void {
    var arr = [5]i32{ 10, 20, 30, 40, 50 };
    const pa: *[5]i32 = &arr;

    // Comptime ranges: start 0, start > 0, empty, full, nested.
    const s13 = pa[1..3];
    const s12 = pa[1..2];
    const s05 = pa[0..5];
    const s55 = pa[5..5];
    const nest = s13[1..2];
    if (s13.len != 2 or s13[0] != 20 or s13[1] != 30) @panic("pa[1..3]");
    if (s12.len != 1 or s12[0] != 20) @panic("pa[1..2]");
    if (s05.len != 5 or s05[0] != 10 or s05[4] != 50) @panic("pa[0..5]");
    if (s55.len != 0) @panic("pa[5..5]");
    if (nest.len != 1 or nest[0] != 30) @panic("nested");

    // Open ends: omitted end is the array length N.
    const s0o = pa[0..];
    const s1o = pa[1..];
    const s5o = pa[5..];
    if (s0o.len != 5 or s0o[0] != 10 or s0o[4] != 50) @panic("pa[0..]");
    if (s1o.len != 4 or s1o[0] != 20 or s1o[3] != 50) @panic("pa[1..]");
    if (s5o.len != 0) @panic("pa[5..]");

    // Runtime bounds: `pa[a..b]`, `pa[a..]` and `pa[0..b]`.
    var a: usize = 1;
    var b: usize = 4;
    const r = pa[a..b];
    const ro = pa[a..];
    const r0 = pa[0..b];
    if (r.len != 3 or r[0] != 20 or r[2] != 40) @panic("pa[a..b]");
    if (ro.len != 4 or ro[0] != 20 or ro[3] != 50) @panic("pa[a..]");
    if (r0.len != 4 or r0[0] != 10 or r0[3] != 40) @panic("pa[0..b]");

    // Cross-module `*[N]T` parameter and the loop/window uses.
    const x = helper.mid(pa);
    if (x.len != 3 or x[0] != 20 or x[2] != 40) @panic("xmod");
    var acc: i32 = 0;
    var i: usize = 0;
    while (i < 3) {
        acc += sum(pa[i..i + 3]);
        i += 1;
    }
    if (acc != 270) @panic("loop windows");

    // Decayed struct array FIELD (many-pointer base): closed + open + runtime.
    var h = Holder{ .arr = [_]i32{ 10, 20, 30, 40, 50 } };
    const f = h.arr[1..4];
    const fo = h.arr[2..];
    const fr = h.arr[a..b];
    if (f.len != 3 or f[0] != 20 or f[2] != 40) @panic("field range");
    if (fo.len != 3 or fo[0] != 30 or fo[2] != 50) @panic("field open");
    if (fr.len != 3 or fr[0] != 20 or fr[2] != 40) @panic("field runtime");

    // Many-item pointer open end: accepted as `[*]T` (Zig 0.15.2 parity), the
    // pointer offset by `start` — no length (index it, pass it on, or slice it
    // closed again). FX5 fix round 1, operator ruling.
    var marr = [5]i32{ 10, 20, 30, 40, 50 };
    const mp: [*]i32 = &marr;
    const mo0 = mp[0..];
    const mo1 = mp[1..];
    var ma: usize = 2;
    const mor = mp[ma..];
    const mp2 = helper.midmp(mp);
    if (mo0[0] != 10 or mo0[3] != 40) @panic("mp[0..]");
    if (mo1[0] != 20 or mo1[2] != 40 or mo1[3] != 50) @panic("mp[1..]");
    if (mor[0] != 30 or mor[1] != 40) @panic("mp[a..]");
    if (mp2[0] != 20 or mp2[2] != 40) @panic("mp xmod");
    const back: []i32 = mo1[0..2];
    if (back.len != 2 or back[0] != 20 or back[1] != 30) @panic("closed from open");

    // `pa.*[i]`: index the dereferenced array directly (read/write/address).
    pa.*[2] = 99;
    pa.*[0] = 77;
    const p: *i32 = &pa.*[1];
    p.* = 88;
    var j: usize = 2;
    pa.*[j] += 5;
    if (arr[0] != 77 or arr[1] != 88 or arr[2] != 104 or pa.*[4] != 50) @panic("pa.*[i]");

    std.io.print("s13={} {} {}\n", .{ s13.len, s13[0], s13[1] });
    std.io.print("s12={} {}\n", .{ s12.len, s12[0] });
    std.io.print("s05={} {} {}\n", .{ s05.len, s05[0], s05[4] });
    std.io.print("s55={}\n", .{s55.len});
    std.io.print("nest={} {}\n", .{ nest.len, nest[0] });
    std.io.print("s0o={} {} {}\n", .{ s0o.len, s0o[0], s0o[4] });
    std.io.print("s1o={} {} {}\n", .{ s1o.len, s1o[0], s1o[3] });
    std.io.print("s5o={}\n", .{s5o.len});
    std.io.print("r={} {} {}\n", .{ r.len, r[0], r[2] });
    std.io.print("ro={} {} {}\n", .{ ro.len, ro[0], ro[3] });
    std.io.print("r0={} {} {}\n", .{ r0.len, r0[0], r0[3] });
    std.io.print("x={} {} {}\n", .{ x.len, x[0], x[2] });
    std.io.print("acc={}\n", .{acc});
    std.io.print("f={} {} {}\n", .{ f.len, f[0], f[2] });
    std.io.print("fo={} {} {}\n", .{ fo.len, fo[0], fo[2] });
    std.io.print("fr={} {} {}\n", .{ fr.len, fr[0], fr[2] });
    std.io.print("mo0={} {}\n", .{ mo0[0], mo0[3] });
    std.io.print("mo1={} {} {}\n", .{ mo1[0], mo1[2], mo1[3] });
    std.io.print("mor={} {}\n", .{ mor[0], mor[1] });
    std.io.print("mp2={} {}\n", .{ mp2[0], mp2[2] });
    std.io.print("back={} {} {}\n", .{ back.len, back[0], back[1] });
    std.io.print("star={} {} {} {}\n", .{ pa.*[0], pa.*[1], pa.*[2], pa.*[4] });
}
