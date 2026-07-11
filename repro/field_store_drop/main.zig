const pal = @import("pal");

const AggTri = struct {
    s: []const u8,
    b: i32,
    c: i32,
};

fn store(s: []const u8, b: i32, c: i32) AggTri {
    var t: AggTri = undefined;
    t.s = s;
    t.b = b;
    t.c = c;
    return t;
}

pub fn main() void {
    var msg: []const u8 = "OK";
    var x = store(msg, 20, 30);
    pal.stderr_write(x.s);
    pal.stderr_write("\n");
    __bootstrap_print_int(x.b);
    pal.stderr_write("\n");
    __bootstrap_print_int(x.c);
    pal.stderr_write("\n");
}
