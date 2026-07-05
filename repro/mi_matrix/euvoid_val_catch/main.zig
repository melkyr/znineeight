fn h() E!void { return @as(E!void, {}); } pub fn main() void { var r = h() catch {}; }
