const std = @import("std");

fn subChain(a: i32, b: i32, c: i32) i32 {
    return a - b - c;
}

fn divChain(a: i32, b: i32, c: i32) i32 {
    return a / b / c;
}

fn addSubChain(a: i32, b: i32, c: i32) i32 {
    return a + b - c;
}

fn addChain(a: i32, b: i32, c: i32) i32 {
    return a + b + c;
}

fn mulChain(a: i32, b: i32, c: i32) i32 {
    return a * b * c;
}

fn revDigits(n: i32) void {
    var tmp: [12]u8 = undefined;
    var len: usize = 0;
    var v: i32 = n;
    if (v == 0) {
        tmp[0] = '0';
        len = 1;
    } else {
        while (v > 0) {
            tmp[len] = '0' + @intCast(u8, v % 10);
            len += 1;
            v = v / 10;
        }
    }
    var k: usize = 0;
    while (k < len) : (k += 1) {
        std.io.writeByte(tmp[len - 1 - k]);
    }
    std.io.writeByte('\n');
}

pub fn main() void {
    std.io.printInt(subChain(10, 4, 3));
    std.io.writeByte('\n');
    std.io.printInt(divChain(100, 10, 2));
    std.io.writeByte('\n');
    std.io.printInt(addSubChain(1, 2, 3));
    std.io.writeByte('\n');
    std.io.printInt(addChain(1, 2, 3));
    std.io.writeByte('\n');
    std.io.printInt(mulChain(2, 3, 4));
    std.io.writeByte('\n');
    revDigits(55);
    revDigits(321);
}
