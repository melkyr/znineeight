// stdlib_as_neg_operand_xmod — Task 8B regression: `@as(<signed>, <negative
// literal>)` used as a BINARY OPERAND must keep the target's width and
// signedness, matching official Zig 0.15.2.
//
// DEFECT (before the fix): `sf/src/lower.zig`'s `comptime_values` HIT path
// recovered the folded constant's target type for `@intCast` only; `@as` fell
// through to the `TYPE_USIZE` default, so `@as(i32,-2)` was materialised as the
// unsigned 64-bit literal `18446744073709551614ULL`. As a binary operand that
// produced wrong values (`v / @as(i32,-2)` printed `0`, Zig `-3`) or a
// `-fsafe` integer-overflow trap (`v + @as(i32,-2)`, rc 133).
//
// FIX (Task 8B): accept `self.as_name_id` alongside `self.int_cast_name_id` at
// `sf/src/lower.zig:4344`, so the folded `@as` result temp carries the target
// type. The fold itself (`sf/src/comptime_eval.zig`) was already correct.
//
// Operator ruling m1210: every signed width is pinned (`i8`/`i16`/`i32`/`i64`/
// `isize`), not only `i32`. Positive/unsigned `@as` operands and the
// already-correct control shapes are pinned too (over-correction guard).
//
// Contract: deterministic byte-exact stdout below, RUNRC=0.
//
//   div=-3
//   mul=-14
//   add=5
//   sub=9
//   mod=1
//   cmp=true
//   i8=5
//   i16=5
//   i64=5
//   isize=5
//   ctrl-pos=9
//   ctrl-neg=5
//   ctrl-unsigned=9
//   ctrl-direct=-2
//   ctrl-const=-3
//   ctrl-literal=-3
//   ctrl-nonfold=-3
//   ctrl-intcast=-3
//   done
const std = @import("std");

const K: i32 = -2;

fn nonfold(x: i32) i32 {
    return x;
}

pub fn main() void {
    var v: i32 = 7;

    var div: i32 = v / @as(i32, -2);
    if (div != -3) { @panic("div"); }
    std.io.print("div={d}\n", .{div});

    var mul: i32 = v * @as(i32, -2);
    if (mul != -14) { @panic("mul"); }
    std.io.print("mul={d}\n", .{mul});

    var add: i32 = v + @as(i32, -2);
    if (add != 5) { @panic("add"); }
    std.io.print("add={d}\n", .{add});

    var sub: i32 = v - @as(i32, -2);
    if (sub != 9) { @panic("sub"); }
    std.io.print("sub={d}\n", .{sub});

    var mod: i32 = v % @as(i32, -2);
    if (mod != 1) { @panic("mod"); }
    std.io.print("mod={d}\n", .{mod});

    if (@as(i32, 7) > @as(i32, -2)) {
        std.io.print("cmp=true\n", .{});
    } else {
        @panic("cmp");
    }

    var v8: i8 = 7;
    var r8: i8 = v8 + @as(i8, -2);
    if (r8 != 5) { @panic("i8"); }
    std.io.print("i8={d}\n", .{r8});

    var v16: i16 = 7;
    var r16: i16 = v16 + @as(i16, -2);
    if (r16 != 5) { @panic("i16"); }
    std.io.print("i16={d}\n", .{r16});

    var v64: i64 = 7;
    var r64: i64 = v64 + @as(i64, -2);
    if (r64 != 5) { @panic("i64"); }
    std.io.print("i64={d}\n", .{r64});

    var vis: isize = 7;
    var ris: isize = vis + @as(isize, -2);
    if (ris != 5) { @panic("isize"); }
    std.io.print("isize={d}\n", .{ris});

    var cpos: i32 = v + @as(i32, 2);
    if (cpos != 9) { @panic("ctrl-pos"); }
    std.io.print("ctrl-pos={d}\n", .{cpos});

    var cneg: i32 = v + -@as(i32, 2);
    if (cneg != 5) { @panic("ctrl-neg"); }
    std.io.print("ctrl-neg={d}\n", .{cneg});

    var cuns: i32 = v + @as(u32, 2);
    if (cuns != 9) { @panic("ctrl-unsigned"); }
    std.io.print("ctrl-unsigned={d}\n", .{cuns});

    var cdir: i32 = @as(i32, -2);
    if (cdir != -2) { @panic("ctrl-direct"); }
    std.io.print("ctrl-direct={d}\n", .{cdir});

    var cconst: i32 = v / K;
    if (cconst != -3) { @panic("ctrl-const"); }
    std.io.print("ctrl-const={d}\n", .{cconst});

    var clit: i32 = v / -2;
    if (clit != -3) { @panic("ctrl-literal"); }
    std.io.print("ctrl-literal={d}\n", .{clit});

    var w: i32 = -2;
    var cnon: i32 = v / @as(i32, nonfold(w));
    if (cnon != -3) { @panic("ctrl-nonfold"); }
    std.io.print("ctrl-nonfold={d}\n", .{cnon});

    var ccast: i32 = v / @intCast(i32, -2);
    if (ccast != -3) { @panic("ctrl-intcast"); }
    std.io.print("ctrl-intcast={d}\n", .{ccast});

    std.io.print("done\n", .{});
}
