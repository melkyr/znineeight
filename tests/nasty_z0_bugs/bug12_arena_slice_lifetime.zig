pub const Arena = struct {
    buf: [256]u8,
    pos: usize,
};

pub fn arenaAlloc(self: *Arena, size: usize) []u8 {
    var result = self.buf[self.pos..self.pos + size];
    self.pos += size;
    return result; // returned slice's ptr depends on arena lifetime
}

pub fn main() void {
    var arena = Arena{ .buf = undefined, .pos = 0 };
    var slice = arenaAlloc(&arena, 42);
    // arena can reset, making slice.ptr dangle
    _ = slice;
}
