extern fn print(msg: []const u8) void;
extern fn print_int(val: i32) void;

pub fn main() void {
    var x: i32 = 3;
    switch (x) {
        1...5 => {
            print("x is in range 1-5\n");
            print_int(x);
        },
        else => {
            print("x is not in range 1-5\n");
        }
    }
}
