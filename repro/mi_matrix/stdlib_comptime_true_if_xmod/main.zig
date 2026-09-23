// stdlib_comptime_true_if_xmod — Task 9D positive runtime control: a no-`else`
// value `if` whose condition is comptime-known-true must compile + run (matching
// official Zig 0.15.2), and a void-then value `if` must lower without the
// undeclared-result-temp defect.
//
// Covers, with a local `const` condition operand (Task 9D Gap B — function-local
// consts were invisible to the fold):
//   * int comparisons `==` `!=` `<` `<=` `>` `>=`
//   * bool `and` / `or` / `!`
//   * a short-circuit `true or <runtime>` and the mirrored rhs-decisive
//     `<runtime> or true` (fix round 1)
//   * an arithmetic-derived comparison (`a + 1 == 2`)
//   * const-of-const (`const c: bool = a == 1;`)
//   * a module const (`MA == 5`)
//   * fixed-width const comparisons by DECLARED type (fix round 1): a `u64`
//     const above i64 max (`umax > 0`, `umax > zero`), a declared `i8` negative,
//     a declared `u8` positive, and an untyped local negative (`an < 0`)
// and the void-then value `if` forms:
//   * `_ = if (vc) foo();`          (absent else, runtime bool cond, void then)
//   * `_ = if (vc) foo() else bar();`
//   * `_ = if (o) |v| { _ = v; foo(); };` (capture condition)
//
// Every result is `@panic`-guarded. Contract: stdout
// `10 11 12 13 14 15 16 17 18 19 30 32 34 40 41 42 43 44 45\nFFF\n`, rc 0,
// byte-exact 3x.
const std = @import("std");

const MA: i32 = 5;

fn foo() void {
    std.io.print("F", .{});
}

fn bar() void {
    std.io.print("B", .{});
}

pub fn main() void {
    const a: i32 = 1;
    var x1: i32 = if (a == 1) 10;
    var x2: i32 = if (a != 2) 11;
    var x3: i32 = if (a < 2) 12;
    var x4: i32 = if (a <= 1) 13;
    var x5: i32 = if (a > 0) 14;
    var x6: i32 = if (a >= 1) 15;
    const b: bool = true;
    var x7: i32 = if (b and true) 16;
    var x8: i32 = if (b or false) 17;
    const bf: bool = false;
    var x9: i32 = if (!bf) 18;
    var x10: i32 = if (a + 1 == 2) 19;
    const c: bool = a == 1;
    var x11: i32 = if (c) 30;
    var x12: i32 = if (MA == 5) 32;
    var run: bool = true;
    run = !run;
    var x13: i32 = if (true or run) 34;
    const umax: u64 = 18446744073709551615;
    const zero: u64 = 0;
    var x14: i32 = if (umax > 0) 40;
    var x15: i32 = if (umax > zero) 41;
    const an = -1;
    var x16: i32 = if (an < 0) 42;
    const n: i8 = -1;
    var x17: i32 = if (n < 0) 43;
    const u: u8 = 200;
    var x18: i32 = if (u > 0) 44;
    var x19: i32 = if (run or true) 45;
    if (x1 != 10 or x2 != 11 or x3 != 12 or x4 != 13 or x5 != 14 or x6 != 15 or x7 != 16 or x8 != 17 or x9 != 18 or x10 != 19 or x11 != 30 or x12 != 32 or x13 != 34 or x14 != 40 or x15 != 41 or x16 != 42 or x17 != 43 or x18 != 44 or x19 != 45) {
        @panic("comptime_true_if guard failed");
    }
    std.io.print("{} {} {} {} {} {} {} {} {} {} {} {} {} {} {} {} {} {} {}\n", .{ x1, x2, x3, x4, x5, x6, x7, x8, x9, x10, x11, x12, x13, x14, x15, x16, x17, x18, x19 });
    var vc: bool = false;
    vc = !vc;
    _ = if (vc) foo();
    _ = if (vc) foo() else bar();
    var o: ?i32 = null;
    o = 7;
    _ = if (o) |v| {
        _ = v;
        foo();
    };
    std.io.print("\n", .{});
}
