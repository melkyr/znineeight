const std = @import("std");
const types = @import("types.zig");
var buf: [256]u8 = undefined;

fn get_item() types.Item {
    var item: types.Item = undefined;
    item.tag = 1;
    item.data.Str = "hello";
    return item;
}

pub fn main() void {
    var holders = @ptrCast([*]types.Holder, &buf)[0..2];
    var kv = get_item();
    var name = kv.data.Str;
    holders[0].name = name;
    holders[0].val = 42;
    std.io.printInt(holders[0].val);
}
