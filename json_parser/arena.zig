extern fn arena_alloc(arena_ptr: *void, size: usize) *void;

pub fn alloc(arena_ptr: *void, comptime T: type, count: usize) []T {
    const ptr = @ptrCast([*]T, arena_alloc(arena_ptr, @sizeOf(T) * count));
    return ptr[0..count];
}
