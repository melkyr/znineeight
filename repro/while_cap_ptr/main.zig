const Node = struct { next: ?*Node, val: i32 };
pub fn main() void {
    var cur: ?*Node = null;
    var sum: i32 = 0;
    while (cur) |node| {
        sum = sum + node.val;
        cur = node.next;
    }
    _ = sum;
}
