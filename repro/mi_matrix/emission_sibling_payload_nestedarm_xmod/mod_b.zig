const std = @import("std");
const mod_a = @import("mod_a.zig");
const Inst = mod_a.Inst;
const Inst2 = mod_a.Inst2;

pub fn emit(inst: Inst) void {
    switch (inst) {
        .store => |s| {
            switch (mod_a.makeInst2()) {
                .tag => |s| {
                    var s: []const u8 = " = *";
                    std.io.write(s);
                },
                .data => |d| {
                    std.io.printInt(@intCast(i32, d.n));
                },
            }
        },
        .load => |l| {
            std.io.printInt(@intCast(i32, l.result));
        },
    }
}
