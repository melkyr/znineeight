pub const Sand = struct {
    start: [*]u8,
    pos: usize,
    end: usize,
    peak: usize,
};

pub fn sandInit(buf: []u8) Sand {
    var s = Sand{
        .start = buf.ptr,
        .pos = @intCast(usize, 0),
        .end = buf.len,
        .peak = @intCast(usize, 0),
    };
    var used = s.pos;
    if (used > s.peak) s.peak = used;
    return s;
}

pub fn sandAlloc(sand: *Sand, size: usize, alignment: usize) ![*]u8 {
    var mask = alignment - @intCast(usize, 1);
    var aligned = (sand.pos + mask) & ~mask;
    var new_pos = aligned + size;
    if (new_pos > sand.end) return error.OutOfMemory;
    var result = sand.start + aligned;
    sand.pos = new_pos;
    if (new_pos > sand.peak) sand.peak = new_pos;
    return result;
}

pub fn sandReset(sand: *Sand) void {
    sand.pos = @intCast(usize, 0);
}

pub const CompilerAlloc = struct {
    permanent: Sand,
    module: Sand,
    scratch: Sand,
    max_mem: u32,
};

pub fn initCompilerAlloc() CompilerAlloc {
    var perm_buf: [1024 * 1024]u8 = undefined;
    var mod_buf: [512 * 1024]u8 = undefined;
    var scr_buf: [256 * 1024]u8 = undefined;
    return CompilerAlloc{
        .permanent = sandInit(perm_buf[0..]),
        .module = sandInit(mod_buf[0..]),
        .scratch = sandInit(scr_buf[0..]),
        .max_mem = @intCast(u32, 16 * 1024 * 1024),
    };
}

pub fn checkCombinedPeak(alloc: *CompilerAlloc) void {
    var total = @intCast(u32, alloc.permanent.peak + alloc.module.peak + alloc.scratch.peak);
    if (total > alloc.max_mem) {
        while (true) {}
    }
}
