// const std = @import("std");

const JsonValue = union(enum) {
    Null: void,
    Boolean: bool,
};

fn makeBoolean(b: bool) JsonValue {
    if (b) {
        return JsonValue{ .Boolean = true };
    } else {
        return JsonValue{ .Null = {} };
    }
}

pub fn main() void {
    _ = makeBoolean(true);
}
