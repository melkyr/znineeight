// diag_excerpt_multifile_xmod — imported module holding the diagnostic span.
// `y = nop();` (line 6, col 6) is the span: `nop()` is void, so the assignment
// emits a tolerated `warning[3000]`; the renderer must excerpt THIS file's line 6.
pub fn run() void {
    var y: u32 = 0;
    y = nop();
}

fn nop() void {
}
