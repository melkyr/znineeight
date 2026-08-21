const std = @import("std");
const mod_a = @import("mod_a.zig");
const Inst = mod_a.Inst;

pub fn emit(inst: Inst) void {
    switch (inst) {
        .store => |s| {
            var s: []const u8 = " = *";
            std.io.write(s);
        },
        .load => |l| {
            std.io.printInt(@intCast(i32, l.result));
        },
    }
}
