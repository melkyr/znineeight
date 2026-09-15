// switch_unannotated_diffstr_xmod_xmod / mid.zig — the un-annotated switch lives in a
// NON-LAST module (imported by main.zig before last.zig). See main.zig for the full
// fixture header. `pick` returns the same differing-length (7 vs 6) string-literal
// switch expression.
pub const Cmd = enum { A, B };

pub fn pick(c: Cmd) []const u8 {
    var s = switch (c) {
        .A => "alpha\r\n",
        .B => "beta\r\n",
    };
    return s;
}
