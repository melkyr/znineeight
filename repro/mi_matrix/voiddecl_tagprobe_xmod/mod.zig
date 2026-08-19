pub const Item = union(enum) { decl_temp: u32, assign: u32, nop: void };
pub const InstList = struct { items: [*]Item, len: usize };
pub const Blk = struct { id: u32, insts: InstList };
pub const BlkList = struct { items: [*]Blk, len: usize };
pub const Func = struct { blocks: BlkList };
