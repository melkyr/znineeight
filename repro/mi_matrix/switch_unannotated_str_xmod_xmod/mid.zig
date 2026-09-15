// switch_unannotated_str_xmod_xmod / mid.zig — the un-annotated switch lives in a
// NON-LAST module (imported by main.zig before last.zig). See main.zig for the full
// fixture header. `pick` returns the same `var s = switch (c) { .A => "alpha\r\n",
// .B => "gamma\r\n" };` un-annotated expression-switch with equal-length (7-byte)
// string-literal prongs.
pub const Cmd = enum { A, B };

pub fn pick(c: Cmd) []const u8 {
    var s = switch (c) {
        .A => "alpha\r\n",
        .B => "gamma\r\n",
    };
    return s;
}
