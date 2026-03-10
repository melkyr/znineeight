extern fn print(msg: []const u8) void;

pub fn main() void {
    var x: i32 = 3;
    // Statement switch
    switch (x) {
        1...5 => print("stmt ok\n"),
        else => print("stmt else\n")
    }

    // Expression switch
    var y = switch (x) {
        1...5 => 10,
        else => 20
    };
    if (y == 10) print("expr ok\n");
}
