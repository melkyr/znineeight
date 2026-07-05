pub fn main() void { var c: bool = true; var r: ??i32 = if (c) @as(??i32, @as(?i32, @as(i32, 42))) else @as(??i32, @as(?i32, null)); _ = r; }
