const S = struct { x: i32, };
pub fn main() void {
    var o: ?S = undefined;
    o.x = 1;
}
