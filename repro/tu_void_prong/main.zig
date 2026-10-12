const MyUnion = union(enum) {
    Empty: void,
    Value: i32,
};

pub fn main() void {
    var u: MyUnion = undefined;
    switch (u) {
        .Empty => |x| {
            _ = x;
        },
        .Value => |n| {
            _ = n;
        },
    }
}
