const std = @import("std");

pub fn ping() void {
    std.io.write("range live ping\n");
}
