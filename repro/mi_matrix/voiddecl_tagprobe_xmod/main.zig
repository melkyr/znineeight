const std = @import("std");
const mod = @import("mod.zig");

pub fn findTailCall(func: *mod.Func) void {
    var bi: usize = 0;
    while (bi < func.blocks.len) : (bi += 1) {
        var blk = func.blocks.items[bi];
        var ii: usize = 0;
        while (ii < blk.insts.len) : (ii += 1) {
            var inst = blk.insts.items[ii];
            var tg = @enumToInt(inst.tag);
            std.io.printInt(tg);
        }
    }
}

pub fn main() void {
    var f = mod.Func{ .blocks = mod.BlkList{ .items = undefined, .len = 0 } };
    findTailCall(&f);
    std.io.printInt(7);
}
