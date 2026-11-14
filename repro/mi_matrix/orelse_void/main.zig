fn makeOptPtr() ?*u32 {
    var p: *u32 = undefined;
    return p;
}

pub fn main() void {
    var x = makeOptPtr() orelse return;
    _ = x;
}
