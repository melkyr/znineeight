const std = @import("std.zig");
const Kind = enum(u16) { plus, minus, star };

fn shapeA() u32 {
    var a: u32 = 0;
    blk: {
        loop: while (true) {
            a = a + 1;
            if (a == 3) break :loop;
        }
    }
    return a;
}

fn shapeB() u32 {
    var i: u32 = 0;
    var count: u32 = 0;
    loop: while (i < 10) : (i += 1) {
        if (i == 3) { continue :loop; }
        if (i == 7) { break :loop; }
        count = count + 1;
    }
    return count;
}

fn shapeC() u32 {
    var total: u32 = 0;
    var idx: u32 = 0;
    loop: while (idx < 3) : (idx += 1) {
        var k: Kind = Kind.plus;
        if (idx == 1) { k = Kind.minus; }
        if (idx == 2) { k = Kind.star; }
        switch (k) {
            Kind.plus => continue :loop,
            Kind.minus => total = total + 10,
            Kind.star => break :loop,
            else => {},
        }
    }
    return total;
}

pub fn main() void {
    std.io.printInt(@intCast(i32, shapeA()));
    std.io.print("\n");
    std.io.printInt(@intCast(i32, shapeB()));
    std.io.print("\n");
    std.io.printInt(@intCast(i32, shapeC()));
    std.io.print("\n");
}
