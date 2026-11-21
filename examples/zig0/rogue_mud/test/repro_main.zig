const repro_mod = @import("repro_mod.zig");

extern "c" fn __bootstrap_print_int(n: i32) void;

pub fn main() void {
    const val = repro_mod.TEST_CONST;
    __bootstrap_print_int(@intCast(i32, val));

    var s = repro_mod.TestStruct { .field = val };
    __bootstrap_print_int(@intCast(i32, s.field));
}
