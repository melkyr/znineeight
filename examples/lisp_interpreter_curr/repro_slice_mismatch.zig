extern fn __bootstrap_print(s: [*]const u8) void;

fn print_str(s: []const u8) void {
    _ = s;
}

pub fn main() void {
    print_str("Hello");
}
