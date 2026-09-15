// if_unannotated_str_xmod_xmod / mid.zig — the un-annotated if-expression lives in a
// NON-LAST module (imported by main.zig before last.zig). See main.zig for the full
// fixture header.
pub fn pick(b: bool) []const u8 {
    var s = if (b) "alpha\r\n" else "gamma\r\n";
    return s;
}
