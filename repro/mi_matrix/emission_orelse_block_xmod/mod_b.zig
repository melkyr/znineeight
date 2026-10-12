const mod_a = @import("mod_a.zig");

pub fn useRet(prefix: []const u8, seed: i32) ?i32 {
    _ = prefix;
    var x = mod_a.maybe(seed) orelse { return null; };
    return x;
}
