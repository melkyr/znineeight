pub const Item = union(enum) { num: u32, none: void };
pub const InstList = struct { items: [*]Item, len: u32 };
pub const Blk = struct { insts: InstList };
pub const Inner = struct { v: u32 };
pub const Ctx = struct { store: *Inner, v: u32 };
pub var gctx = Ctx{ .store = undefined, .v = 7 };
pub var gblk = Blk{ .insts = InstList{ .items = undefined, .len = 0 } };
pub fn makeBlk() Blk {
    var b = Blk{ .insts = InstList{ .items = undefined, .len = 0 } };
    return b;
}
pub fn makeCtx() Ctx {
    var c = Ctx{ .store = undefined, .v = 7 };
    return c;
}
