const mod_a = @import("mod_a.zig");

pub fn copyArr() u32 {
    var fb: [16]u8 = undefined;
    var src: [16]u8 = undefined;
    var i: usize = 0;
    while (i < 16) : (i += 1) {
        src[i] = @intCast(u8, i);
    }
    if (true) {
        fb = src;
    }
    return mod_a.addOne(@intCast(u32, fb[0]));
}
