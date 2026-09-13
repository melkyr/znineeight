const Cb = extern "stdcall" fn(i32) void;
extern "stdcall" fn z98_stdcall_probe(x: i32) void;

pub fn main() void {
    var cb: Cb = z98_stdcall_probe;
    _ = cb;
}
