const std = @import("std.zig");

fn isPrime(n: u32) bool {
    if (n < 2) { return false; }
    var i: u32 = 2;
    while (i * i <= n) {
        if (n % i == 0) { return false; }
        i += 1;
    }
    return true;
}

pub fn main() void {
    var i: u32 = 1;
    while (i <= 10) {
        if (isPrime(i)) {
            std.debug.printInt(@intCast(i32, i));
        }
        i += 1;
    }
}
