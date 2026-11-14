const CbC = fn(i32) void;
const CbS = extern "stdcall" fn(i32) void;
extern fn z98_cdecl_probe(x: i32) void;

pub fn main() void {
    var c: CbC = z98_cdecl_probe;
    var s: CbS = c;
    _ = s;
}
