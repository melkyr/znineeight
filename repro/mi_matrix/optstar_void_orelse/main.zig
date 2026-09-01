fn makeOptVoid() ?*void {
    var p: *void = undefined;
    return p;
}

pub fn main() void {
    var x = makeOptVoid() orelse return;
    _ = x;
}
