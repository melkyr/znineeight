// D4 control: grouped returns via a named struct (positional `.{...}` literal
// coerced by field order). The tuple TYPE spelling `struct { T1, T2 }` is what
// fails; the named-struct form works.
const std = @import("std");

const DivMod = struct { q: i32, r: i32 };

fn divmod(a: i32, b: i32) DivMod {
    return .{ a / b, a % b };
}

pub fn main() void {
    const d = divmod(17, 5);
    std.io.print("q={} r={}\n", .{ d.q, d.r });
}
