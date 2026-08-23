const mod_a = @import("mod_a.zig");

pub fn useReturn(prefix: []const u8, seed: i32) ?i32 {
    var x = mod_a.maybe(seed) orelse return null;
    return x;
}

pub fn useContinue(prefix: []const u8, seed: i32) i32 {
    var acc: i32 = 0;
    var i: i32 = 0;
    while (i < 4) : (i += 1) {
        var x = mod_a.maybe(seed) orelse continue;
        acc += x;
    }
    return acc;
}
