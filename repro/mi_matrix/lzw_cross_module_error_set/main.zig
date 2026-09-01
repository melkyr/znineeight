const types = @import("types.zig");
fn encode() types.LzwError!void { return types.LzwError.DictFull; }
pub fn main() void { _ = encode(); }
