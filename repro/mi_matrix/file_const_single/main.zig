pub const File = void;

fn makeOptFile() ?*File {
    var f: *File = undefined;
    return f;
}

pub fn main() void {
    var x = makeOptFile() orelse return;
    _ = x;
}
