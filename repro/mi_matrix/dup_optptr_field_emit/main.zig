const Node = struct {
    x: u8,
    left: ?*Node,
    right: ?*Node,
};

pub fn main() void {
    var node: Node = undefined;
    node.x = 5;
    node.left = null;
    node.right = null;
    _ = node;
}
