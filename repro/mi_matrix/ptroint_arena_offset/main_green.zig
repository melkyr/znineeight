const Arena = struct {
    start: [*]u8,
    pos: usize,
    end: usize,
};
fn alloc(a: *Arena, size: usize) [*]u8 {
    var p = a.pos;
    a.pos += size;
    return a.start + p;
}
pub fn main() void {
    var buf: [64]u8 = undefined;
    var a = Arena{ .start = &buf, .pos = 0, .end = 64 };
    var p = alloc(&a, 8);
    _ = p;
}
