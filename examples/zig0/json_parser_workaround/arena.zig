extern fn arena_alloc_default(size: usize) *void;

pub fn alloc_bytes(count: usize) []u8 {
    const ptr = @ptrCast([*]u8, arena_alloc_default(count));
    return ptr[0..count];
}
