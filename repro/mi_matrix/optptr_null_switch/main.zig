pub fn main() void { var v: u32 = 0; var r: ?*i32 = switch(v) { 0 => null, 1 => @intToPtr(*i32, 0), else => @intToPtr(*i32, 0), }; _ = r; }
