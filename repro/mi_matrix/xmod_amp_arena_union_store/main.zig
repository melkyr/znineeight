extern var zig_default_arena: *void;
const Tag = enum { A, B };
const TData = union { x: i32, y: f64 };
const S = struct { tag: Tag, data: TData };
extern fn arena_alloc_default(size: usize) *void;
pub fn main() void {
    const arena = &zig_default_arena;
    const ptr = @ptrCast(*S, arena_alloc_default(@sizeOf(S)));
    ptr.tag = Tag.A;
    ptr.data.x = 42;
    _ = ptr;
    _ = arena;
}
