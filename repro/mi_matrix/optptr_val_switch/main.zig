extern fn getp() *i32; pub fn main() void { var v: u32 = 0; var r: ?*i32 = switch(v) { 0 => getp(), 1 => getp(), else => getp(), }; _ = r; }
