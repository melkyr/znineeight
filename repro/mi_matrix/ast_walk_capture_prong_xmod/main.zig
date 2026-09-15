// ast_walk_capture_prong_xmod — Task-10 AST generic-walk regression fixture.
// A union(enum) switch with `|x|` capture prongs stores the capture NAME ID in
// swt_prong.child_1 (parser.zig). Pre-fix every generic AST walker (notably
// async_analysis.zig scanFunction, which runs on every fn) pushed that name id
// as a NODE INDEX, causing a traversal cycle and an arena OOM (dump rc=3).
// Contract: GREEN — dump rc=0, 4 .c, gcc-clean, self-contained link, run rc=0.
const U = union(enum) {
    empty: void,
    value: i32,
};

pub fn main() void {
    var u: U = U{ .value = 42 };
    var got: i32 = 0;
    switch (u) {
        .empty => |x| {
            _ = x;
        },
        .value => |n| {
            got = n;
        },
    }
    if (got != 42) {
        @panic("capture prong mismatch");
    }
}
