// analyzer_labeled_reject_xmod — FX8 reject fixture for the diagnostics the
// `labeled_stmt` traversal now reaches (error[3034]/error[3035] class).
//
// After the FX8 fix, a labeled block/loop body is walked like any other
// statement: a definite null deref inside a labeled block or labeled loop is
// the same `error[3034]` the bare-block/if controls already produced, and a
// double free split across a labeled block is the definite `error[3035]`.
// PRE (`ff059647`) every labeled shape below was silent (rc 0), so only the
// `nullDerefInIf` control rejected.
//
// Contract POST: dump rc=2, 0 `.c`, exactly
//   error[3034] x3  (nullDerefInIf control, nullDerefInLabeledBlock,
//                    nullDerefInLabeledWhile)
//   error[3035] x1  (doubleFreeInLabeledBlock: free inside the labeled block,
//                    second free after it)
//   warning[3037] x3 (the shared analyzeExpr null-deref warning, one per
//                     null site)
// PRE: rc=2, error[3034] x1 + warning[3037] x1 (the if control only).
// Note: a free split across a LABELED LOOP does not reject — the loop-body
// fork/merge joins the body's `freed` with the enclosing `allocated` as
// `unknown`, the same conservative join an unlabeled loop has; that shape is
// the pre-existing loop-merge behavior, not changed by FX8.
extern fn arena_alloc(size: usize) *u8;
extern fn arena_free(alloc: usize, p: *u8) void;

fn nullDerefInIf(c: bool) void {
    var p: ?*i32 = null;
    if (c) {
        if (p.* == 0) {
        }
    }
}

fn nullDerefInLabeledBlock() void {
    var p: ?*i32 = null;
    blk: {
        if (p.* == 0) {
        }
    }
}

fn nullDerefInLabeledWhile(c: bool) void {
    var p: ?*i32 = null;
    lw: while (c) {
        if (p.* == 0) {
        }
    }
}

fn doubleFreeInLabeledBlock() void {
    var p: *u8 = arena_alloc(8);
    blk: {
        arena_free(0, p);
    }
    arena_free(0, p);
}

pub fn main() void {
    nullDerefInIf(true);
    nullDerefInLabeledBlock();
    nullDerefInLabeledWhile(true);
    doubleFreeInLabeledBlock();
}
