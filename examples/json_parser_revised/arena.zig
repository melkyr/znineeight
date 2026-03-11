extern fn arena_alloc_default(size: usize) *void;

pub fn alloc(arena: *void, comptime T: type, count: usize) []T {
    const ptr = @ptrCast([*]T, arena_alloc_default(@sizeOf(T) * count));
    return ptr[0..count];
}

pub fn alloc_bytes(count: usize) []u8 {
    const ptr = @ptrCast([*]u8, arena_alloc_default(count));
    return ptr[0..count];
}
