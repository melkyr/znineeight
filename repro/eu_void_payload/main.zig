const MyError = error {
    Foo,
    Bar,
};

fn mayFail() MyError!void {
    return error.Foo;
}

pub fn main() void {
    mayFail() catch |err| {
        _ = err;
    };
}
