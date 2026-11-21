// D6 control: an unannotated (inferred) F64 tagged-union init compiles and
// runs. (The f32 form is the defect; see red_inferred_f32.zig.)
const std = @import("std");

const Value = union(enum) {
    i: i32,
    f: f64,
};

pub fn main() void {
    var v = Value{ .f = 2.5 };
    std.io.print("{d}\n", .{ v.f });
}
