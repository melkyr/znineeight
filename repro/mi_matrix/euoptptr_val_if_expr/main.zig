extern fn getp() *i32; pub fn main() void { var c: bool = true; var r: E!?*i32 = if (c) @as(E!?*i32, @as(?*i32, getp())) else @as(E!?*i32, @as(?*i32, getp())); _ = r; }
