const mod_a = @import("mod_a.zig");

pub fn useCatch(prefix: []const u8) ?i32 {
    _ = prefix;
    var x = mod_a.maybeErr() catch blk: { return null; };
    return x;
}
