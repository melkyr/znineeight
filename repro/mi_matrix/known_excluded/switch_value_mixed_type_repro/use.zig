fn pick(n: i32) i32 {
    var x = switch (n) {
        0 => 1,
        else => true,
    };
    return x + 1;
}

pub fn main() void {
    var r = pick(0);
    _ = r;
}
