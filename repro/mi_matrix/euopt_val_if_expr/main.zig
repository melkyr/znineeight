pub fn main() void { var c: bool = true; var r: E!?i32 = if (c) @as(E!?i32, @as(?i32, @as(i32, 42))) else @as(E!?i32, @as(?i32, null)); _ = r; }
