pub fn main() void {
    // @src() returns all-zero SrcLoc
    var loc = @src();
    _ = loc;
}
