const a = [2]i32{ switch (1) { 0 => 1, else => 7 }, 2 };

pub fn main() void {
    _ = a;
}
