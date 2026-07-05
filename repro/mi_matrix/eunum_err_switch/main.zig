const E = error{Bad}; pub fn main() void { var v: u32 = 0; var r: E!u64 = switch(v) { 0 => error.Bad, 1 => @as(u32, 0), else => @as(u32, 0), }; _ = r; }
