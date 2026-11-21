// D5 fix-round-2 companion module: the cdecl extern definition is owned here,
// while sibling_xmod_fnptr.zig (another module) takes its function value.

pub extern fn cv(x: u32) i32 {
    return @intCast(i32, x) + 6;
}
