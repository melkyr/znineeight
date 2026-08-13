const std = @import("std.zig");

const MyErr = error{ Worse, Bad, Terrible };

fn do_work() MyErr!u32 {
    return error.Bad;
}

pub fn main() void {
    const result = do_work();
    const val = result catch |err| {
        var ec = @intCast(u32, @enumToInt(err));
        var ei: i32 = @intCast(i32, ec);
        std.io.printInt(ei);
        return;
    };
    std.io.printInt(@intCast(i32, val));
}
