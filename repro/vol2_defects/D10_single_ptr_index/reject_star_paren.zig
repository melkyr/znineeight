// D10 sibling (FH conversion, 2026-09-27): `(*p)[i]` (a `type` base; prefix
// `*` is pointer-type syntax, not the `.*` dereference) silently compiled to
// wrong C on seed v88 (`arr[zT_12]`, traced initializer). It is now a clean
// `error[3066]` (`unable to resolve comptime value`), rc 2 / 0 `.c`.
const std = @import("std");

fn at(p: *i32, i: usize) i32 {
    return (*p)[i];
}

pub fn main() void {
    var arr = [2]i32{ 10, 20 };
    const p: *i32 = &arr[0];
    std.io.print("spi={}\n", .{at(p, 1)});
}
