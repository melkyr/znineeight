const Node = struct { v: i32, next: ?*Node };

var g: ?*Node = null;

pub fn get() ?*Node {
    return g;
}
