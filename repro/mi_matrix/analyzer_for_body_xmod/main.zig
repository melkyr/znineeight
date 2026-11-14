// analyzer_for_body_xmod — Task-10 analyzer for-loop body regression fixture.
// sf/src/analyzer.zig visitStatement's for_stmt arm walked node.child_0 (the
// iterated PATTERN) instead of node.child_1 (the BODY), so the null/lifetime/
// double-free analyzers never descended into `for` bodies. This fixture puts a
// detectable double free inside a for body. Contract: GREEN — exactly one
// error[2005] (double free), dump rc=2, 0 .c. Pre-fix: no error[2005],
// dump rc=0, 4 .c (body not walked).
extern fn sandAlloc(size: usize) *void;
extern fn arena_free(arena: *void, ptr: *void) void;

pub fn main() void {
    var a: *void = undefined;
    var p: *void = sandAlloc(8);
    var arr: [2]i32 = [2]i32{ 1, 2 };
    for (arr) |x| {
        _ = x;
        arena_free(a, p);
        arena_free(a, p);
    }
}
