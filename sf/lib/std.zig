// Z98 Standard Library stub
// This file provides the minimal std namespace required by zig1.
// Compiled by zig0, imported as @import("std") by compiler source.

pub const debug = struct {
    pub fn print(comptime fmt: []const u8, args: anytype) void {
        _ = fmt;
        _ = args;
    }
};

pub const mem = struct {
    pub fn eql(a: []const u8, b: []const u8) bool {
        _ = a;
        _ = b;
        return false;
    }
};

pub const io = struct {
    pub const Writer = struct {
        pub fn write(self: *Writer, data: []const u8) !void {
            _ = self;
            _ = data;
        }
    };
};

pub const ArrayList = struct {
    // Placeholder — will be replaced by concrete implementation
};

pub fn eql(a: []const u8, b: []const u8) bool {
    _ = a;
    _ = b;
    return false;
}
