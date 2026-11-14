const mod_a = @import("mod_a.zig");

const Cb = struct {
    cb: ?fn () void,
};

pub fn run() i32 {
    var f: ?fn () void = mod_a.foo;
    var s: Cb = undefined;
    s.cb = mod_a.foo;
    var r: i32 = 0;
    if (f != null) {
        r = r + 1;
    }
    if (s.cb != null) {
        r = r + 2;
    }
    return r;
}
