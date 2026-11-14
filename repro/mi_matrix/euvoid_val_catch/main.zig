const E = error{Bad}; fn h() E!void { return {}; } pub fn main() void { var r = h() catch {}; }
