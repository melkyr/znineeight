const LzwError = error{ DictFull, InvalidCode };
fn encode() LzwError!void { return error.DictFull; }
pub fn main() void { _ = encode(); }
