pub const Arena = struct {
    start: [*]u8,
    pos: [*]u8,
    end: [*]u8,
};

pub fn arena_init(buffer: []u8) Arena {
    return Arena{
        .start = buffer.ptr,
        .pos = buffer.ptr,
        .end = buffer.ptr + buffer.len,
    };
}

pub fn arena_alloc(arena: *Arena, size: usize, alignment: usize) ![*]u8 {
    const mask = alignment - 1;
    const current_pos = @ptrToInt(arena.pos);
    const aligned_pos = (current_pos + mask) & ~mask;
    const new_pos = aligned_pos + size;

    if (new_pos > @ptrToInt(arena.end)) {
        return error.OutOfMemory;
    }

    const result = arena.pos + (aligned_pos - current_pos);
    arena.pos = result + size;
    return result;
}

pub fn arena_reset(arena: *Arena) void {
    arena.pos = arena.start;
}
