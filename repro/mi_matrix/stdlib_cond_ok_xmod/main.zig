// cond_ok_xmod — Task 9B positive runtime control: valid condition / `if` forms
// must still compile, link, and run. Covers `if`/`else if`/`else`, a value `if`
// expression WITH `else`, an optional capture (`if (opt) |v| ... else`), a null
// optional falling to the else arm, a `while` loop, and a void-then `if`
// statement. Each construct writes a result variable (rather than printing
// inside a branch) so the single trailing `print` is the whole golden output and
// the fixture is insensitive to block ordering. A guard `@panic`s if any
// result is wrong.
//
// Contract: stdout `2 10 7 -1 3 1\n`, rc 0, byte-exact 3x.
const std = @import("std");

pub fn main() void {
    var a: i32 = 2;
    var c1: i32 = 0;
    if (a == 1) {
        c1 = 1;
    } else if (a == 2) {
        c1 = 2;
    } else {
        c1 = 3;
    }
    var y: i32 = if (a == 2) 10 else 20;
    var o: ?i32 = 7;
    var c2: i32 = 0;
    if (o) |v| {
        c2 = v;
    } else {
        c2 = -1;
    }
    var none: ?i32 = null;
    var c3: i32 = 0;
    if (none) |v| {
        c3 = v;
    } else {
        c3 = -1;
    }
    var i: i32 = 0;
    var sum: i32 = 0;
    while (i < 3) {
        sum += i;
        i += 1;
    }
    var c4: i32 = 0;
    if (i == 3) {
        c4 = 1;
    }
    if (c1 != 2 or y != 10 or c2 != 7 or c3 != -1 or sum != 3 or c4 != 1) {
        @panic("cond_ok guard failed");
    }
    std.io.print("{} {} {} {} {} {}\n", .{c1, y, c2, c3, sum, c4});
}
