const std = @import("std");

const Writer = struct {
    write_fn: fn(s: []const u8) void,
};

fn stdoutWrite(s: []const u8) void {
    std.io.print(s.ptr);
}

pub fn main() void {
    var w: Writer = undefined;
    w.write_fn = stdoutWrite;
    _ = w;
}
