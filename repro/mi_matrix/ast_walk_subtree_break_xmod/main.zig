// ast_walk_subtree_break_xmod — Task-10 astSubtreeHasBreak coverage fixture.
// semantic_analyzer.zig astSubtreeHasBreak is reached for a value-returning fn
// whose body is `while (true)` (A7F terminates check). Its generic walk visits
// the switch `|v|` capture prong; pre-fix it recursed into the capture NAME ID
// (swt_prong.child_1) as a node index. Contract: GREEN — dump rc=0, 4 .c,
// gcc-clean, self-contained link, run rc=0.
const U = union(enum) {
    done: i32,
    more: i32,
};

fn spin(u: U) i32 {
    while (true) {
        switch (u) {
            .done => |v| {
                return v;
            },
            .more => |v| {
                return v + 1;
            },
        }
    }
}

pub fn main() void {
    var got: i32 = spin(U{ .done = 7 });
    if (got != 7) {
        @panic("subtree break mismatch");
    }
}
