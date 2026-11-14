// stdlib_intcast_loop_capture_xmod — Task 7 positive runtime fixture.
//
// A one-argument `@intCast(expr)` (official Zig 0.15.2 infers the target type
// from context) must lower its operand: Z98 sema's single-argument builtin
// fallback types the expression as the operand's own type, so the cast is an
// identity here. Pre-fix (`sf/src/lower.zig`, the `builtin_call` arm's
// `ec_n >= 2` cast block), a one-argument `@intCast` fell through to the
// void-temp default; the emitter never declares void temps, so the emitted C
// referenced an undeclared `zT_<n>` (emit rc=0, no diagnostic, gcc
// `'zT_6' undeclared`).
//
// Covers:
//   * the reported shape — `@intCast(<for-range capture>)` in the capture's
//     own loop (identity)
//   * the same capture RENAMED (a same-named local in an earlier sibling
//     scope forces the internal synth name)
//   * `@intCast` on a copy of the capture
//   * a non-capture local `@intCast` (control)
//   * a parameter + return-position `@intCast` (control)
//   * a nested loop's outer capture (control)
//   * a fixed-array element capture (control)
//
// Every aggregate is `@panic`-guarded, so a wrong value traps (rc 133) instead
// of printing as if correct. Golden from the FIXED compiler, 3x byte-exact and
// cross-checked against a Zig 0.15.2 twin (`std.debug.print`).
const std = @import("std");

fn passthru(x: u32) u32 {
    return @intCast(x);
}

pub fn main() void {
    // Reported shape: `@intCast(<for-range capture>)` in the capture's loop.
    var cap: u32 = 0;
    for (0..4) |q| {
        cap += @intCast(q);
    }
    if (cap != 6) { @panic("range-capture @intCast guard failed"); }

    // The same with the capture renamed: an earlier sibling scope declares `q`,
    // so the loop capture takes an internal synth name.
    var ren: u32 = 0;
    {
        const q: u32 = 5;
        ren += q;
    }
    for (0..3) |q| {
        ren += @intCast(q);
    }
    if (ren != 8) { @panic("renamed-capture @intCast guard failed"); }

    // A copied variable (control).
    var cpy: u32 = 0;
    for (0..3) |q| {
        const c: u32 = q;
        cpy += @intCast(c);
    }
    if (cpy != 3) { @panic("copied-variable @intCast guard failed"); }

    // A non-capture local (control).
    var n: u32 = 2;
    var loc: u32 = 0;
    loc += @intCast(n);
    if (loc != 2) { @panic("non-capture @intCast guard failed"); }

    // Parameter + return position (control).
    if (passthru(n) != 2) { @panic("param @intCast guard failed"); }

    // A nested loop's outer capture (control).
    var nest: u32 = 0;
    for (0..2) |i| {
        for (0..2) |j| {
            nest += @intCast(i);
            _ = j;
        }
    }
    if (nest != 2) { @panic("nested outer-capture @intCast guard failed"); }

    // A fixed-array element capture (control).
    var arr: [3]u32 = [3]u32{ 1, 2, 3 };
    var sl: u32 = 0;
    for (arr) |x| {
        sl += @intCast(x);
    }
    if (sl != 6) { @panic("array-capture @intCast guard failed"); }

    std.io.print("cap={} ren={} cpy={} loc={} nest={} sl={}\n", .{ cap, ren, cpy, loc, nest, sl });
}
