pub const MyError = error {
    Foo,
    Bar,
};

pub fn mayFail() MyError!void {
    return error.Foo;
}
