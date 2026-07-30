const S2 = union(enum) { A: i32, B: f64 };
extern fn arena_alloc_default(size: usize) *void;
pub fn main() void {
    const ptr = @ptrCast(*S2, arena_alloc_default(@sizeOf(S2)));
    ptr.* = S2{ .A = 42 };
    _ = ptr;
}
