// labeled_block_break_maybe_warn.zig — Task 9h1 fix-round fixture.
//
// `break :blk` exits the labeled block while `q` still holds the non-null
// parameter; the fall-through path sets `q = null`. Both paths converge after
// the block, so the post-block state is `maybe` (WARN_6002), never a false
// ERR_2004 from the fall-through assignment.
fn labeled_block_break_maybe_warn(p: *u32, cond: bool) u32 {
    var q: ?*u32 = p;
    blk: {
        if (cond) {
            break :blk;
        }
        q = null;
    }
    return q.*;
}

pub fn main() void {
    var x: u32 = 1;
    _ = labeled_block_break_maybe_warn(&x, true);
}
