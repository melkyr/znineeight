const repro_mod = @import("repro_mod.zig");
const std = @import("../../mud_server/std.zig");

pub fn main() void {
    const val = repro_mod.TEST_CONST;
    std.io.printInt(@intCast(i32, val));

    var s = repro_mod.TestStruct { .field = val };
    std.io.printInt(@intCast(i32, s.field));
}
