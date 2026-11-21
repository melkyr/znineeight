pub const Foo = struct {
    x: i32,

    // zig0 rejects pub fn inside struct declarations (parser.cpp:1464)
    pub fn bar(self: *Foo) void {
        _ = self;
    }
};

pub fn main() void {}
