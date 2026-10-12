const X = struct {
    next: ?X,
};
pub fn main() void {
    var x: X = undefined;
    x.next = null;
    _ = x;
}
