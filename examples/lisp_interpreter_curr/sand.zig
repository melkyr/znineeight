pub const Sand = struct {
    start: [*]u8,
    pos: usize,
    end: usize,
};

pub fn sand_init(buffer: []u8) Sand {
    return Sand{
        .start = buffer.ptr,
        .pos = @intCast(usize, 0),
        .end = buffer.len,
    };
}

pub fn sand_alloc(sand: *Sand, size: usize, alignment: usize) util.LispError![*]u8 {
    const actual_align = if (alignment < @intCast(usize, 8)) @intCast(usize, 8) else alignment;
    const mask = actual_align - @intCast(usize, 1);
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

pub fn points_to_arena(v: *void, sand_start: [*]u8, sand_range: usize) bool {
    const addr = @ptrToInt(v);
    const start = @ptrToInt(sand_start);
    const end = start + sand_range;
    return addr >= start and addr < end;
}

const util = @import("util.zig");
