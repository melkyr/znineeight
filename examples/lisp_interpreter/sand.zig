pub const LispSand = struct {
    start: [*]u8,
    pos: [*]u8,
    end: [*]u8,
};

pub fn lisp_sand_init(buffer: []u8) LispSand {
    return LispSand{
        .start = buffer.ptr,
        .pos = buffer.ptr,
        .end = buffer.ptr + buffer.len,
    };
}

pub fn lisp_sand_alloc(sand: *LispSand, size: usize, alignment: usize) anyerror![*]u8 {
    const mask = alignment - 1;
    const current_pos = @ptrToInt(sand.pos);
    const aligned_pos = (current_pos + mask) & ~mask;
    const new_p = aligned_pos + size;

    if (new_p > @ptrToInt(sand.end)) {
        return error.OutOfMemory;
    }

    const res_ptr = sand.pos + (aligned_pos - current_pos);
    sand.pos = res_ptr + size;
    return res_ptr;
}

pub fn lisp_sand_reset(sand: *LispSand) void {
    sand.pos = sand.start;
}
