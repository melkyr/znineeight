pub const Sand = struct {
    start: [*]u8,
    pos: usize,      // next free byte
    end: usize,      // buffer limit
    permanent: bool, // flag: reset allowed?
};

pub fn sand_init(buffer: []u8, permanent: bool) Sand {
    return Sand{
        .start = buffer.ptr,
        .pos = @intCast(usize, 0),
        .end = buffer.len,
        .permanent = permanent,
    };
}

pub fn sand_alloc(sand: *Sand, size: usize, alignment: usize) ![*]u8 {
    const min_align = @intCast(usize, 8);
    const actual_align = if (alignment < min_align) min_align else alignment;
    const mask = actual_align - 1;
    const aligned_pos = (sand.pos + mask) & ~mask;
    if (aligned_pos + size > sand.end) {
        return error.OutOfMemory;
    }
    const res = sand.start + aligned_pos;
    sand.pos = aligned_pos + size;
    return res;
}

pub fn sand_reset(sand: *Sand) void {
    sand.pos = @intCast(usize, 0);
}

// MUD-specific: reset temp arena between game ticks
pub fn sand_reset_temp(sand: *Sand) void {
    if (!sand.permanent) {
        sand.pos = @intCast(usize, 0);  // reclaim all temp allocations
    }
}

pub fn sand_dupe_z(sand: *Sand, s: []const u8) ![*]const u8 {
    const mem = try sand_alloc(sand, s.len + 1, 1);
    const ptr = @ptrCast([*]u8, mem);
    var i: usize = 0;
    while (i < s.len) : (i += 1) {
        ptr[i] = s[i];
    }
    ptr[s.len] = @intCast(u8, 0);
    return @ptrCast([*]const u8, ptr);
}
