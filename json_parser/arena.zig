extern fn arena_alloc_default(size: usize) *void;

pub fn alloc(arena: *void, comptime T: type, count: usize) []T {
    _ = arena;
    const ptr = @ptrCast([*]T, arena_alloc_default(@sizeOf(T) * count));
    return ptr[0..count];
}

pub fn alloc_bytes(count: usize) struct { ptr: *void, len: usize } {
    const ptr = arena_alloc_default(count);
    var res: struct { ptr: *void, len: usize } = undefined;
    res.ptr = ptr;
    res.len = count;
    return res;
}
