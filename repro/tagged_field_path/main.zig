const Item = struct {
    key: []const u8,
    value: i32,
};

const MyUnion = union(enum) {
    List: []Item,
    Empty,
};

pub fn main() void {
    var u: MyUnion = undefined;
    switch (u) {
        .List => |items| {
            for (items) |item| {
                _ = item.key;
            }
        },
        .Empty => {},
    }
}
