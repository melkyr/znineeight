const ItemA = struct {
    x: u32,
};

const ItemB = struct {
    key: u32,
};

pub fn main() void {
    var list_a: [3]ItemA = undefined;
    var list_b: [3]ItemB = undefined;

    for (list_a) |item| {
        _ = item.x;
    }

    for (list_b) |item| {
        _ = item.key;
    }
}
