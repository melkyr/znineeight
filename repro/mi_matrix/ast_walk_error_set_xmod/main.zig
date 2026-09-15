// ast_walk_error_set_xmod — Task-10 AST generic-walk regression fixture.
// `error_set_decl`'s extra children are tag NAME IDs (parser.zig), so
// nodeHasExtraChildren(error_set_decl) must not be treated as node children.
// The tag `u32` is collision-pinned: its interned id coincides with a low node
// index, so pre-fix the generic walk cycles -> arena OOM (dump rc=3). Contract:
// GREEN — dump rc=0, 4 .c, gcc-clean, self-contained link, run rc=0.
pub fn main() void {
    var e: error{Foo, u32} = error.Foo;
    _ = e;
}
