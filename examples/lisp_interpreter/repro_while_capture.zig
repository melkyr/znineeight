pub fn main() void {
    var cur: ?*i32 = null;
    while (cur) |node| {
        _ = node;
    }
}
