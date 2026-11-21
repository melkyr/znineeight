const lib = @import("lib.zig");

pub fn main() void {
    lib.mayFail() catch |err| {
        _ = err;
    };
}
