// diag_excerpt_multifile_xmod — imported module holding the diagnostic span.
// The `y = missing;` assignment (line 6, col 6) is the RED span; the renderer
// must excerpt THIS file's line 6, not line 5. See `main.zig`.
pub fn run() void {
    var y: u32 = 0;
    y = missing;
}
