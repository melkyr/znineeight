fn pick(n: i32) void {
    var x = switch (n) {
        0 => 1,
        else => true,
    };
    _ = x;
}

pub fn main() void {
    pick(0);
}
