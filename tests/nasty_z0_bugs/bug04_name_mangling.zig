// Two functions with different names that collide after vowel stripping.
// Both have "rrayListGrow" after removing vowels → same hash → linker error.
// Run: ./zig0 -o /tmp/repro.c tests/nasty_z0_bugs/bug04_name_mangling.zig
// Expected: zig0 generates C but symbols collide at link time.

pub fn u32ArrayListGrow(self: *U32ArrayList) void {
    _ = self;
}

pub fn byteArrayListGrow(self: *ByteArrayList) void {
    _ = self;
}

pub const U32ArrayList = struct {
    items: [*]u32,
    len: usize,
    capacity: usize,
};

pub const ByteArrayList = struct {
    items: [*]u8,
    len: usize,
    capacity: usize,
};

pub fn main() void {}
