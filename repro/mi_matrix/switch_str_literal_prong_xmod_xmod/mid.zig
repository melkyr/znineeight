// switch_str_literal_prong_xmod_xmod / mid.zig — the buggy switch lives in a NON-LAST
// module (imported by main.zig before last.zig). See main.zig for the full fixture
// header. `pick` is the same `switch (c) { .A => "alpha\r\n", .B => "beta\r\n" }`
// expression-switch with string-literal prongs typed []const u8.
pub const Cmd = enum { A, B };

pub fn pick(c: Cmd) []const u8 {
    return switch (c) {
        .A => "alpha\r\n",
        .B => "beta\r\n",
    };
}
