extern fn __bootstrap_print(s: [*]const u8) void; pub fn main() void { switch(1) { 1 => __bootstrap_print("OK\n"), else => {} } }
