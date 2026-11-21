// callconv_stdcall_fnptr_xmod — Task 3 convention fn-pointer typedef fixture.
// Task 3R additionally asserts the extern function-value use is cast to the
// `FS_...` typedef: `zT_1 = ((FS_...)z98_stdcall_probe);` (no forced prototype).
const Cb = extern "stdcall" fn(i32) void;
extern "stdcall" fn z98_stdcall_probe(x: i32) void;

pub fn main() void {
    var cb: Cb = z98_stdcall_probe;
    _ = cb;
}
