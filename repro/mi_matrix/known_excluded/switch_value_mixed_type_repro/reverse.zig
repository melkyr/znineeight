fn pick(n: i32) i32 {
    return switch (n) {
        0 => true,
        else => 1,
    };
}

pub fn main() void {
    var r = pick(0);
    _ = r;
}
