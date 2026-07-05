extern fn getp() *i32; pub fn main() void { var v: u32 = 0; var r: E!?*i32 = switch(v) { 0 => @as(?*i32, getp()), 1 => @as(?*i32, getp()), else => @as(?*i32, getp()), }; _ = r; }
