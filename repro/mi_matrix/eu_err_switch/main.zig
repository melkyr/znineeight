const E = error{Bad}; pub fn main() void { var v: u32 = 0; var r: E!i32 = switch(v) { 0 => error.Bad, 1 => 0, else => 0, }; _ = r; }
