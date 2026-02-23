// arena.zig
extern fn arena_alloc(arena: *void, size: usize) *void;

pub fn alloc(arena: *void, size: usize) *void {
    return arena_alloc(arena, size);
}
