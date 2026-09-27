// D10 control (FH conversion, 2026-09-27): the three legal `*T` slice forms
// are accepted with Zig 0.15.2's result types (`*[0]T`/`*[1]T`, qualifiers
// carried), plus the unchanged `*[N]T` and deref/many-pointer paths.
// Contract: stdout `lens=0 1 0 v=42 sl0=42 c=42 pa1=20 pas1=20 dv=42 mp=20`,
// rc 0. Exercised outside run_all.sh (the case's main.zig is the reject
// census).
const std = @import("std");

pub fn main() void {
    var x: i32 = 42;
    const p: *i32 = &x;
    const t00: *[0]i32 = p[0..0];
    const t01: *[1]i32 = p[0..1];
    const t11: *[0]i32 = p[1..1];
    const v = t01[0];
    const sl: []i32 = t01;
    const cp: *const i32 = &x;
    const ct01: *const [1]i32 = cp[0..1];

    var arr = [3]i32{ 10, 20, 30 };
    const pa: *[3]i32 = &arr;
    const pa1 = pa[1];
    const pas = pa[0..2];
    const psl: []i32 = pas;

    const dv = p.*;
    var marr = [3]i32{ 10, 20, 30 };
    const mp: [*]i32 = marr;
    const mpv = mp[1];

    std.io.print("lens={} {} {} v={} sl0={} c={} pa1={} pas1={} dv={} mp={}\n", .{ t00.len, t01.len, t11.len, v, sl[0], ct01[0], pa1, psl[1], dv, mpv });
}
