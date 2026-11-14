const mod_a = @import("mod_a.zig");

pub fn copyFieldA() u32 {
    var fb: []const u8 = "A";
    var out: u32 = 0;
    {
        var fb: [16]u8 = undefined;
        var src: [16]u8 = undefined;
        var i: usize = 0;
        while (i < 16) : (i += 1) {
            src[i] = @intCast(u8, i);
        }
        fb = src;
        out = fb[0];
    }
    return out + mod_a.addOne(fb.len);
}

pub fn copyFieldB() u32 {
    var fb: []const u8 = "B";
    var out: u32 = 0;
    {
        var fb: [16]u8 = undefined;
        var src: [16]u8 = undefined;
        var i: usize = 0;
        while (i < 16) : (i += 1) {
            src[i] = @intCast(u8, i);
        }
        fb = src;
        out = fb[0];
    }
    return out + mod_a.addOne(fb.len);
}

pub fn copyFieldC() u32 {
    var fb: []const u8 = "C";
    var out: u32 = 0;
    {
        var fb: [16]u8 = undefined;
        var src: [16]u8 = undefined;
        var i: usize = 0;
        while (i < 16) : (i += 1) {
            src[i] = @intCast(u8, i);
        }
        fb = src;
        out = fb[0];
    }
    return out + mod_a.addOne(fb.len);
}
