// ast_walk_for_index_xmod — Task-10 AST generic-walk regression fixture.
// `for (arr) |v, i|` stores the index NAME ID in for_stmt.child_2 (parser.zig).
// Pre-fix the generic AST walkers pushed that name id as a NODE INDEX (cycle ->
// arena OOM, dump rc=3). Contract: GREEN — dump rc=0, 4 .c, gcc-clean,
// self-contained link, run rc=0.
pub fn main() void {
    var arr: [3]i32 = [3]i32{ 10, 20, 30 };
    var sum: i32 = 0;
    for (arr) |v, i| {
        sum += v + @intCast(i32, i);
    }
    if (sum != 63) {
        @panic("for index mismatch");
    }
}
