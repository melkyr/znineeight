const std = @import("std.zig");

fn isLeapYear(year: u32) bool {
    return (year % 4 == 0) and (year % 100 != 0 or year % 400 == 0);
}

fn daysInMonth(month: u8, year: u32) u8 {
    const d = switch (month) {
        1, 3, 5, 7, 8, 10, 12 => 31,
        4, 6, 9, 11 => 30,
        2 => if (isLeapYear(year)) 29 else 28,
        else => 0, // invalid month
    };
    return @intCast(u8, d);
}

pub fn main() void {
    const year = 2024;
    std.debug.print("Days in month for year {}:\n", .{year});
    for (1..13) |m| {
        const month = @intCast(u8, m);
        const days = daysInMonth(month, year);
        std.debug.print("  Month {}: {} days\n", .{ month, days });
    }
}
