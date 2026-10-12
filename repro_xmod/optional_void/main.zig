const lib = @import("lib.zig");

pub fn main() void {
    var opt = lib.getOpt();
    if (opt) |v| {
        _ = v;
    }
}
