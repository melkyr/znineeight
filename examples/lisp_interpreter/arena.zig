pub const LispArena = struct {
    start: [*]u8,
    pos: [*]u8,
    end: [*]u8,
};

pub fn lisp_arena_init(buffer: []u8) LispArena {
    return LispArena{
        .start = buffer.ptr,
        .pos = buffer.ptr,
        .end = buffer.ptr + buffer.len,
    };
}

pub fn lisp_alloc(arena: *LispArena, size: usize, alignment: usize) ![*]u8 {
    const mask = alignment - 1;
    const current_pos = @ptrToInt(arena.pos);
    const aligned_pos = (current_pos + mask) & ~mask;
    const new_p = aligned_pos + size;

    if (new_p > @ptrToInt(arena.end)) {
        return error.OutOfMemory;
    }

    const res_ptr = arena.pos + (aligned_pos - current_pos);
    arena.pos = res_ptr + size;
    return res_ptr;
}

pub fn lisp_reset(arena: *LispArena) void {
    arena.pos = arena.start;
}
