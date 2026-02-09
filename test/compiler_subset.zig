// Simulates structures from zig1 compiler
// Simplified to ensure it parses in the bootstrap compiler

const Type = struct {
    kind: i32,
    size: i32,
    alignment: i32,
};

const ASTNode = struct {
    kind: i32,
    resolved_type: i32,
};

fn add(a: i32, b: i32) i32 {
    return a + b;
}

fn process(node: *ASTNode) void {
    if (node.kind == 1) {
        node.resolved_type = 42;
    }
}

fn main() void {
    var x: i32 = 10;
    var y: i32 = 20;
    var z = add(x, y);

    var node: ASTNode = ASTNode {
        .kind = 1,
        .resolved_type = 0,
    };

    process(&node);
}
