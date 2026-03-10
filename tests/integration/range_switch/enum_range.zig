const Color = enum {
    Red,
    Green,
    Blue,
    Yellow,
};

extern fn print(msg: []const u8) void;

pub fn main() void {
    var c = Color.Green;
    switch (c) {
        Color.Red...Color.Blue => {
            print("primary or green\n");
        },
        else => {
            print("other color\n");
        }
    }
}
