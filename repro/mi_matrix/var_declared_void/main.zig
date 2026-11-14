fn noop() void {
    return;
}

pub fn main() void {
    var x = noop();
    _ = x;
}
