const Arena = struct {
    start: [*]u8,
    pos: [*]u8,
    end: [*]u8,
};
fn alloc(a: *Arena, size: usize) [*]u8 {
    var p = a.pos;
    a.pos = @intToPtr([*]u8, @ptrToInt(a.pos) + size);
    return p;
}
pub fn main() void {
    var buf: [64]u8 = undefined;
    var a = Arena{ .start = &buf, .pos = &buf, .end = &buf + 64 };
    var p = alloc(&a, 8);
    _ = p;
}
