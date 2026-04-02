const token = @import("multi_module_token.zig");

pub fn main() void {
    const t = token.Token.Eof;
    _ = t;
}
