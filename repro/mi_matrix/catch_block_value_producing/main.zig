const std = @import("std");
const helper = @import("helper.zig");

pub fn main() void {
    var result = helper.try_compute() catch |err| {
        _ = err;
        99
    };
    std.io.printInt(result);
}
