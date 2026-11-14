fn pick(n: i32) i32 {
    return switch (n) {
        0 => 1,
        else => true,
    };
}

pub fn main() void {
    var r = pick(0);
    _ = r;
}
