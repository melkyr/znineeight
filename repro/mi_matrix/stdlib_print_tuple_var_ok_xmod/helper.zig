// Helper module for stdlib_print_tuple_var_ok_xmod (FD2): a cross-module
// named tuple type printed from inside the helper (a tuple-typed parameter
// used directly as the print container).
const std = @import("std");

pub const Pair = struct { i32, i32 };

pub fn logPair(v: Pair) void {
    std.io.print("xmod={} {}\n", v);
}
