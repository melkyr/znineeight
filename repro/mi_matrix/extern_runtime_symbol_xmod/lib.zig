extern "c" fn arena_alloc_default(n: u32) [*]u8;

pub fn alloc(n: u32) [*]u8 {
    return arena_alloc_default(n);
}
