extern fn print(msg: []const u8) void;

pub fn main() void {
    var x: i32 = 4;
    switch (x) {
        1, 3...5, 10 => {
            print("matched\n");
        },
        else => {
            print("not matched\n");
        }
    }
}
